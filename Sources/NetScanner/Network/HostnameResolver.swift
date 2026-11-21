//
//  HostnameResolver.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin
import dnssd

enum HostnameResolver {
    /// Unicast reverse DNS (PTR) through the system resolver, e.g. your router's DHCP names.
    static func reverseDNS(_ address: IPAddress) -> String? {
        address.withSocketAddress(port: 0) { sa, length in
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, length, &host, socklen_t(host.count), nil, 0, NI_NAMEREQD) == 0 else { return nil }
            let name = String(cString: host).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !name.isEmpty, IPAddress(name) == nil else { return nil }
            return name
        }
    }

    /// Multicast DNS reverse lookups: asks every device on the link "who is d.c.b.a.in-addr.arpa?".
    /// Apple devices, Linux (Avahi), printers and many IoT devices answer with their `.local` name.
    static func multicastReverse(_ addresses: [IPAddress], timeout: TimeInterval, cancel: CancelToken,
                                 onResult: @escaping (IPAddress, String) -> Void) {
        guard !addresses.isEmpty else { return }

        final class Query {
            let address: IPAddress
            let onResult: (IPAddress, String) -> Void
            var ref: DNSServiceRef?
            var answered = false
            init(address: IPAddress, onResult: @escaping (IPAddress, String) -> Void) {
                self.address = address
                self.onResult = onResult
            }
        }

        let queue = DispatchQueue(label: "netscanner.mdns-ptr")
        var queries: [Query] = []

        queue.sync {
            for address in addresses {
                let query = Query(address: address, onResult: onResult)
                var interfaceIndex: UInt32 = 0
                if case .v6(let a) = address, a.isLinkLocal { interfaceIndex = a.scopeID }
                var ref: DNSServiceRef?
                let error = DNSServiceQueryRecord(&ref, DNSServiceFlags(kDNSServiceFlagsForceMulticast), interfaceIndex,
                                                  address.reversePointerName, UInt16(kDNSServiceType_PTR), UInt16(kDNSServiceClass_IN),
                                                  { _, flags, _, error, _, _, _, rdLength, rdata, _, rawContext in
                    guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let rawContext, let rdata,
                          flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0 else { return }
                    let query = Unmanaged<Query>.fromOpaque(rawContext).takeUnretainedValue()
                    guard !query.answered, let name = HostnameResolver.decodeDNSName(rdata, Int(rdLength)) else { return }
                    query.answered = true
                    query.onResult(query.address, name)
                }, Unmanaged.passUnretained(query).toOpaque())
                guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let ref else { continue }
                query.ref = ref
                DNSServiceSetDispatchQueue(ref, queue)
                queries.append(query)
            }
        }

        Blocking.sleep(timeout, cancel: cancel)

        queue.sync {
            for query in queries {
                if let ref = query.ref { DNSServiceRefDeallocate(ref) }
                query.ref = nil
            }
        }
        withExtendedLifetime(queries) {}
    }

    /// Decodes an uncompressed DNS wire-format name ("\x05host\x05local\x00").
    static func decodeDNSName(_ pointer: UnsafeRawPointer, _ length: Int) -> String? {
        let bytes = UnsafeRawBufferPointer(start: pointer, count: length)
        var labels: [String] = []
        var i = 0
        while i < length {
            let labelLength = Int(bytes[i])
            if labelLength == 0 { break }
            guard labelLength < 64, i + 1 + labelLength <= length else { return nil }
            labels.append(String(decoding: bytes[(i + 1)..<(i + 1 + labelLength)], as: UTF8.self))
            i += 1 + labelLength
        }
        let name = labels.joined(separator: ".")
        return name.isEmpty ? nil : name
    }

    /// "Abdys-MacBook-Pro.local" → "Abdys-MacBook-Pro"; FQDNs keep only the first label.
    static func shortName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if IPAddress(trimmed) != nil { return trimmed }
        return trimmed.split(separator: ".").first.map(String.init) ?? trimmed
    }
}
