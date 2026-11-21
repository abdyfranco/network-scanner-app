//
//  UniFiConsole.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin

/// A UniFi OS console (Dream Machine, Cloud Gateway, Cloud Key…), which hosts the UniFi Network app.
struct UniFiConsole: Sendable, Hashable {
    let address: IPv4Address
    let name: String?
    /// The console's own MAC, as UniFi Network lists it. It can differ from the MAC its LAN
    /// address answers ARP with (a Dream Machine Pro answers with a different port's MAC).
    let mac: MACAddress?
    /// e.g. "<console id>.id.ui.direct": resolves to the console's LAN address and carries a
    /// trusted certificate, so the browser opens it without a certificate warning.
    let directConnectDomain: String?

    /// Every Network app page lives under this, e.g. https://<host>/network/default/devices.
    private var host: String { directConnectDomain ?? address.description }

    /// One adopted device's panel, or the device list when the device's MAC is unknown. UniFi OS's
    /// own web code links devices exactly this way. The panel's tabs (Overview, Insights, Settings)
    /// aren't addressable: UniFi Network reads only the MAC from this path and keeps the tab in memory,
    /// so Settings is one click away in the panel.
    func networkURL(deviceMAC: MACAddress?, site: String = "default") -> URL? {
        var path = "/network/\(site)/devices"
        if let deviceMAC {
            path += "/properties/\(deviceMAC.description.lowercased())/overview"
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        return components.url
    }

    /// Asks a host for UniFi OS's public system summary (`GET /api/system`, no sign-in needed).
    /// Returns nil when the host isn't a UniFi OS console.
    static func probe(_ address: IPv4Address, timeout: TimeInterval = 3) async -> UniFiConsole? {
        guard let url = URL(string: "https://\(address)/api/system") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .ephemeral, delegate: SelfSignedTrust(host: address.description), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let system = try? JSONDecoder().decode(SystemInfo.self, from: data),
              system.hardware?.shortname != nil || system.mac != nil
        else { return nil }

        // Only ever follow a UniFi direct-connect name, and only when it really leads back to this
        // console (DNS rebinding protection on some networks blocks these private answers).
        var domain = system.directConnectDomain?.lowercased()
        if let name = domain, !(Self.isDirectConnectDomain(name) && Self.resolve(name).contains(address)) {
            domain = nil
        }
        return UniFiConsole(address: address, name: system.name, mac: system.mac.flatMap(Self.parseMAC), directConnectDomain: domain)
    }

    private struct SystemInfo: Decodable {
        struct Hardware: Decodable { let shortname: String? }
        let name: String?
        let mac: String?
        let directConnectDomain: String?
        let hardware: Hardware?
    }

    static func isDirectConnectDomain(_ name: String) -> Bool {
        name.hasSuffix(".id.ui.direct")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    /// "70A741EDC2F5" or "70:a7:41:ed:c2:f5".
    static func parseMAC(_ text: String) -> MACAddress? {
        if let mac = MACAddress(text) { return mac }
        guard text.count == 12, let value = UInt64(text, radix: 16) else { return nil }
        return MACAddress(value: value)
    }

    /// IPv4 addresses a name resolves to.
    static func resolve(_ name: String) -> [IPv4Address] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }
        var addresses: [IPv4Address] = []
        for info in sequence(first: first, next: { $0.pointee.ai_next }) {
            guard let sa = info.pointee.ai_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addresses.append(IPv4Address($0.pointee.sin_addr)) }
        }
        return addresses
    }
}

/// Consoles use self-signed certificates on their LAN address. The probe only reads public,
/// non-sensitive data, so it accepts the certificate for that one address and nothing else.
private final class SelfSignedTrust: NSObject, URLSessionDelegate {
    let host: String
    init(host: String) { self.host = host }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}
