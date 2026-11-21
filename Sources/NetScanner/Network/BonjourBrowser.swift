//
//  BonjourBrowser.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import dnssd

struct BonjourService: Sendable, Hashable, Identifiable {
    let name: String
    /// e.g. "_airplay._tcp"
    let type: String
    let domain: String
    var host: String = ""
    var port: UInt16 = 0
    var txt: [String: String] = [:]
    let interfaceIndex: UInt32

    var id: String { "\(name).\(type)" }
}

/// Browses Bonjour services with the system mDNSResponder (dns_sd), resolves each instance
/// to host, port and TXT record, then resolves the host to IPv4 and IPv6 addresses.
/// All dns_sd callbacks run on one private serial queue.
final class BonjourBrowser: @unchecked Sendable {
    typealias Handler = (BonjourService, IPAddress) -> Void

    static let defaultTypes = [
        "_device-info._tcp", "_airplay._tcp", "_raop._tcp", "_companion-link._tcp", "_apple-mobdev2._tcp",
        "_sleep-proxy._udp", "_smb._tcp", "_afpovertcp._tcp", "_adisk._tcp", "_ssh._tcp", "_sftp-ssh._tcp",
        "_rfb._tcp", "_http._tcp", "_https._tcp", "_ipp._tcp", "_ipps._tcp", "_printer._tcp",
        "_pdl-datastream._tcp", "_scanner._tcp", "_uscan._tcp", "_googlecast._tcp", "_spotify-connect._tcp",
        "_hap._tcp", "_hap._udp", "_homekit._tcp", "_matter._tcp", "_matterc._udp", "_sonos._tcp",
        "_workstation._tcp", "_daap._tcp", "_touch-able._tcp", "_mediaremotetv._tcp", "_amzn-wplay._tcp",
        "_androidtvremote2._tcp", "_airport._tcp", "_home-assistant._tcp", "_esphomelib._tcp",
        "_ewelink._tcp", "_remotepairing._tcp",
    ]

    fileprivate final class Context {
        enum Kind {
            case meta
            case browse
            case resolve(BonjourService)
            case address(String)
        }

        weak var browser: BonjourBrowser?
        let kind: Kind
        var ref: DNSServiceRef?

        init(browser: BonjourBrowser, kind: Kind) {
            self.browser = browser
            self.kind = kind
        }
    }

    private let queue = DispatchQueue(label: "netscanner.bonjour")
    private var contexts: [Context] = []
    private var browsedTypes = Set<String>()
    private var resolving = Set<String>()
    private var hostServices: [String: [BonjourService]] = [:]
    private var hostAddresses: [String: Set<IPAddress>] = [:]
    private var handler: Handler?
    private var stopped = false

    func start(types: [String] = BonjourBrowser.defaultTypes, handler: @escaping Handler) {
        queue.async { [self] in
            self.handler = handler
            browse("_services._dns-sd._udp", meta: true)
            for type in types { browse(type, meta: false) }
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            for context in contexts {
                if let ref = context.ref { DNSServiceRefDeallocate(ref) }
                context.ref = nil
            }
            contexts.removeAll()
            handler = nil
        }
    }

    // MARK: Browse

    private func browse(_ type: String, meta: Bool) {
        guard !stopped, browsedTypes.insert(type).inserted else { return }
        let context = Context(browser: self, kind: meta ? .meta : .browse)
        var ref: DNSServiceRef?
        let error = DNSServiceBrowse(&ref, 0, 0, type, "local.", { _, flags, interfaceIndex, error, name, regtype, domain, rawContext in
            guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let rawContext, let name, let regtype, let domain else { return }
            let context = Unmanaged<BonjourBrowser.Context>.fromOpaque(rawContext).takeUnretainedValue()
            context.browser?.didBrowse(context, flags: flags, interfaceIndex: interfaceIndex,
                                       name: String(cString: name), regtype: String(cString: regtype),
                                       domain: String(cString: domain))
        }, Unmanaged.passUnretained(context).toOpaque())
        register(context, ref: ref, error: error)
    }

    private func register(_ context: Context, ref: DNSServiceRef?, error: DNSServiceErrorType) {
        guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let ref else { return }
        context.ref = ref
        contexts.append(context)
        DNSServiceSetDispatchQueue(ref, queue)
    }

    private func release(_ context: Context) {
        if let ref = context.ref { DNSServiceRefDeallocate(ref) }
        context.ref = nil
    }

    fileprivate func didBrowse(_ context: Context, flags: DNSServiceFlags, interfaceIndex: UInt32,
                               name: String, regtype: String, domain: String) {
        guard !stopped, flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0 else { return }

        if case .meta = context.kind {
            // Meta-query answers look like name "_airplay", regtype "_tcp.local."
            let proto = regtype.split(separator: ".").first.map(String.init) ?? ""
            guard name.hasPrefix("_"), proto == "_tcp" || proto == "_udp" else { return }
            browse("\(name).\(proto)", meta: false)
            return
        }

        let type = regtype.split(separator: ".").prefix(2).joined(separator: ".")
        let service = BonjourService(name: name, type: type, domain: domain, interfaceIndex: interfaceIndex)
        guard resolving.insert("\(service.id)#\(interfaceIndex)").inserted else { return }

        let resolveContext = Context(browser: self, kind: .resolve(service))
        var ref: DNSServiceRef?
        let error = DNSServiceResolve(&ref, 0, interfaceIndex, name, regtype, domain, { _, _, interfaceIndex, error, _, hostTarget, port, txtLength, txtRecord, rawContext in
            guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let rawContext, let hostTarget else { return }
            let context = Unmanaged<BonjourBrowser.Context>.fromOpaque(rawContext).takeUnretainedValue()
            let txt = BonjourBrowser.parseTXT(txtRecord, Int(txtLength))
            context.browser?.didResolve(context, host: String(cString: hostTarget), port: UInt16(bigEndian: port),
                                        txt: txt, interfaceIndex: interfaceIndex)
        }, Unmanaged.passUnretained(resolveContext).toOpaque())
        register(resolveContext, ref: ref, error: error)
    }

    // MARK: Resolve

    fileprivate func didResolve(_ context: Context, host: String, port: UInt16, txt: [String: String], interfaceIndex: UInt32) {
        guard !stopped, case .resolve(var service) = context.kind else { return }
        release(context)
        service.host = host
        service.port = port
        service.txt = txt

        let hostKey = "\(host.lowercased())#\(interfaceIndex)"
        hostServices[hostKey, default: []].append(service)
        for address in hostAddresses[hostKey] ?? [] { handler?(service, address) }

        guard hostAddresses[hostKey] == nil else { return }
        hostAddresses[hostKey] = []

        let addressContext = Context(browser: self, kind: .address(hostKey))
        var ref: DNSServiceRef?
        let protocols = DNSServiceProtocol(kDNSServiceProtocol_IPv4) | DNSServiceProtocol(kDNSServiceProtocol_IPv6)
        let error = DNSServiceGetAddrInfo(&ref, 0, interfaceIndex, protocols, host, { _, flags, interfaceIndex, error, _, address, _, rawContext in
            guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let rawContext, let address,
                  flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0 else { return }
            let context = Unmanaged<BonjourBrowser.Context>.fromOpaque(rawContext).takeUnretainedValue()
            guard var ip = IPAddress(socketAddress: address) else { return }
            if case .v6(var v6) = ip, v6.isLinkLocal, v6.scopeID == 0 {
                v6.scopeID = interfaceIndex
                ip = .v6(v6)
            }
            context.browser?.didResolveAddress(context, ip)
        }, Unmanaged.passUnretained(addressContext).toOpaque())
        register(addressContext, ref: ref, error: error)
    }

    fileprivate func didResolveAddress(_ context: Context, _ ip: IPAddress) {
        guard !stopped, case .address(let hostKey) = context.kind else { return }
        guard hostAddresses[hostKey, default: []].insert(ip).inserted else { return }
        for service in hostServices[hostKey] ?? [] { handler?(service, ip) }
    }

    static func parseTXT(_ pointer: UnsafeRawPointer?, _ length: Int) -> [String: String] {
        guard let pointer, length > 0 else { return [:] }
        let bytes = UnsafeRawBufferPointer(start: pointer, count: length)
        var result: [String: String] = [:]
        var i = 0
        while i < length {
            let entryLength = Int(bytes[i])
            i += 1
            guard entryLength > 0, i + entryLength <= length else {
                i += entryLength
                continue
            }
            let entry = String(decoding: bytes[i..<(i + entryLength)], as: UTF8.self)
            if let eq = entry.firstIndex(of: "=") {
                result[entry[..<eq].lowercased()] = String(entry[entry.index(after: eq)...])
            } else {
                result[entry.lowercased()] = ""
            }
            i += entryLength
        }
        return result
    }
}

// MARK: - Human-readable service names

enum BonjourCatalog {
    private static let titles: [String: String] = [
        "_airplay._tcp": "AirPlay", "_raop._tcp": "AirPlay Audio", "_companion-link._tcp": "Apple Companion Link",
        "_device-info._tcp": "Device Info", "_apple-mobdev2._tcp": "Apple Mobile Device", "_sleep-proxy._udp": "Bonjour Sleep Proxy",
        "_smb._tcp": "SMB File Sharing", "_afpovertcp._tcp": "AFP File Sharing", "_adisk._tcp": "Time Machine",
        "_ssh._tcp": "SSH", "_sftp-ssh._tcp": "SFTP", "_rfb._tcp": "Screen Sharing (VNC)",
        "_http._tcp": "Web Server", "_https._tcp": "Secure Web Server", "_http-alt._tcp": "Web Server (alt)",
        "_ipp._tcp": "Printer (IPP)", "_ipps._tcp": "Printer (IPPS)", "_printer._tcp": "Printer (LPD)",
        "_pdl-datastream._tcp": "Printer (RAW 9100)", "_scanner._tcp": "Scanner", "_uscan._tcp": "Scanner (eSCL)",
        "_uscans._tcp": "Scanner (eSCL TLS)", "_print-caps._tcp": "Print Capabilities",
        "_googlecast._tcp": "Google Cast", "_googlezone._tcp": "Google Cast Group", "_googcrossdevice._tcp": "Google Cross-Device",
        "_spotify-connect._tcp": "Spotify Connect", "_hap._tcp": "HomeKit", "_hap._udp": "HomeKit (Thread)",
        "_homekit._tcp": "HomeKit", "_matter._tcp": "Matter", "_matterc._udp": "Matter Commissioning",
        "_sonos._tcp": "Sonos", "_workstation._tcp": "Workstation", "_daap._tcp": "Music Sharing",
        "_touch-able._tcp": "Apple TV Remote", "_mediaremotetv._tcp": "Apple TV Media Remote",
        "_amzn-wplay._tcp": "Amazon Fire TV", "_androidtvremote2._tcp": "Android TV Remote",
        "_airport._tcp": "AirPort Base Station", "_home-assistant._tcp": "Home Assistant",
        "_esphomelib._tcp": "ESPHome", "_ewelink._tcp": "eWeLink", "_remotepairing._tcp": "Remote Pairing",
        "_asquic._udp": "Apple Services (QUIC)", "_mqtt._tcp": "MQTT", "_net-assistant._udp": "Apple Remote Desktop",
    ]

    static func title(for type: String) -> String { titles[type] ?? type }
}
