//
//  PortCatalog.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin

enum PortPreset: String, CaseIterable, Identifiable, Codable {
    case common, wellKnown, extended, all, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .common: return String(localized: "Common")
        case .wellKnown: return "1–1024"
        case .extended: return "1–10000"
        case .all: return String(localized: "All")
        case .custom: return String(localized: "Custom")
        }
    }

    var ports: [UInt16]? {
        switch self {
        case .common: return PortCatalog.common
        case .wellKnown: return Array(1...1024)
        case .extended: return Array(1...10_000)
        case .all: return Array(1...65_535)
        case .custom: return nil
        }
    }
}

enum PortCatalog {
    /// Probed on every address during discovery. A SYN/ACK or RST proves the host is alive;
    /// 62078 (lockdownd) is open on iPhones and iPads even when they ignore ping.
    static let discovery: [UInt16] = [80, 443, 22, 445, 62078]

    /// Probed only on live hosts to help identify device types.
    static let fingerprint: [UInt16] = [7000, 8080, 8443, 9100, 631, 515, 554, 3389, 5000, 5001, 1400, 8009, 548, 139,
                                        3689, 5900, 8008, 32400, 8123, 1883, 21, 23, 8000, 8888, 9000, 5357, 6789, 8880, 49152]

    /// Nmap's most frequent TCP ports plus home-network services.
    static let common: [UInt16] = Array(Set<UInt16>([
        7, 9, 13, 21, 22, 23, 25, 26, 37, 53, 79, 80, 81, 88, 106, 110, 111, 113, 119, 135, 139, 143, 144, 179, 199,
        389, 427, 443, 444, 445, 465, 513, 514, 515, 543, 544, 548, 554, 587, 631, 646, 873, 990, 993, 995, 1025,
        1026, 1027, 1028, 1029, 1110, 1400, 1433, 1720, 1723, 1755, 1883, 1900, 2000, 2001, 2049, 2121, 2717, 3000,
        3128, 3306, 3389, 3689, 3986, 4899, 5000, 5001, 5009, 5051, 5060, 5101, 5190, 5357, 5432, 5631, 5666, 5800,
        5900, 6000, 6001, 6646, 6789, 7000, 7070, 7100, 8000, 8008, 8009, 8080, 8081, 8123, 8443, 8843, 8880, 8883,
        8888, 9000, 9100, 9443, 9999, 10000, 32400, 32768, 49152, 49153, 49154, 49155, 49156, 49157, 62078,
    ])).sorted()

    private static let names: [UInt16: (String, LocalizedStringResource)] = [
        21: ("ftp", "File Transfer"), 22: ("ssh", "Secure Shell"), 23: ("telnet", "Telnet"), 25: ("smtp", "Mail (SMTP)"),
        53: ("domain", "DNS"), 80: ("http", "Web"), 88: ("kerberos", "Kerberos"), 110: ("pop3", "Mail (POP3)"),
        111: ("rpcbind", "RPC"), 135: ("msrpc", "Microsoft RPC"), 139: ("netbios-ssn", "NetBIOS Session"),
        143: ("imap", "Mail (IMAP)"), 389: ("ldap", "LDAP"), 427: ("svrloc", "Service Location"), 443: ("https", "Secure Web"),
        445: ("microsoft-ds", "SMB File Sharing"), 465: ("smtps", "Mail (SMTPS)"), 515: ("printer", "LPD Printing"),
        548: ("afp", "Apple File Sharing"), 554: ("rtsp", "RTSP Video Stream"), 587: ("submission", "Mail Submission"),
        631: ("ipp", "Internet Printing"), 873: ("rsync", "rsync"), 993: ("imaps", "Mail (IMAPS)"), 995: ("pop3s", "Mail (POP3S)"),
        1400: ("sonos", "Sonos Control"), 1433: ("ms-sql", "SQL Server"), 1723: ("pptp", "PPTP VPN"), 1883: ("mqtt", "MQTT"),
        1900: ("upnp", "UPnP"), 2049: ("nfs", "NFS"), 3000: ("http-alt", "Web (dev)"), 3306: ("mysql", "MySQL"),
        3389: ("rdp", "Remote Desktop"), 3689: ("daap", "Music Sharing"), 5000: ("upnp/airplay", "AirPlay / Synology"),
        5001: ("synology-https", "Synology DSM"), 5060: ("sip", "VoIP (SIP)"), 5357: ("wsdapi", "Web Services Discovery"),
        5432: ("postgresql", "PostgreSQL"), 5900: ("vnc", "Screen Sharing"), 6789: ("unifi-speedtest", "UniFi Speed Test"),
        7000: ("airplay", "AirPlay"), 7100: ("airplay-fonts", "AirPlay"), 8000: ("http-alt", "Web (alt)"),
        8008: ("http-alt", "Google Cast / Web"), 8009: ("googlecast", "Google Cast"), 8080: ("http-proxy", "Web (alt)"),
        8081: ("http-alt", "Web (alt)"), 8123: ("home-assistant", "Home Assistant"), 8443: ("https-alt", "Secure Web (alt)"),
        8843: ("unifi-portal", "UniFi Guest Portal"), 8880: ("unifi-portal-http", "UniFi Guest Portal"), 8883: ("mqtts", "MQTT (TLS)"),
        8888: ("http-alt", "Web (alt)"), 9000: ("http-alt", "Web (alt)"), 9100: ("jetdirect", "RAW Printing"),
        9443: ("https-alt", "Secure Web (alt)"), 10000: ("webmin", "Webmin / NDMP"), 32400: ("plex", "Plex Media Server"),
        49152: ("upnp", "UPnP / dynamic"), 62078: ("iphone-sync", "Apple Device Sync"),
    ]

    private static let servicesLock = NSLock()

    static func serviceName(for port: UInt16) -> String {
        if let known = names[port] { return known.0 }
        return servicesLock.withLock {
            guard let entry = getservbyport(Int32(port.bigEndian), "tcp"), let name = entry.pointee.s_name else { return "unknown" }
            return String(cString: name)
        }
    }

    static func serviceDescription(for port: UInt16) -> String? { names[port].map { String(localized: $0.1) } }

    /// "22, 80, 443, 8000-8100" → sorted unique ports.
    static func parse(_ spec: String) throws -> [UInt16] {
        var ports = Set<UInt16>()
        for token in spec.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            let parts = token.split(separator: "-", maxSplits: 1)
            if parts.count == 2, let a = UInt16(parts[0]), let b = UInt16(parts[1]), a >= 1, a <= b {
                for p in a...b { ports.insert(p) }
            } else if parts.count == 1, let p = UInt16(parts[0]), p >= 1 {
                ports.insert(p)
            } else {
                throw TargetError.invalid(String(token))
            }
        }
        guard !ports.isEmpty else { throw TargetError.empty }
        return ports.sorted()
    }

    /// A URL that opens the service in the right app, when one exists.
    static func url(for port: UInt16, address: IPAddress) -> URL? {
        let host = address.urlHost
        switch port {
        case 80, 3000, 5000, 7080, 8000, 8008, 8080, 8081, 8123, 8880, 8888, 9000, 32400:
            return URL(string: "http://\(host):\(port)")
        case 443, 5001, 8443, 8843, 9443, 10000:
            return URL(string: "https://\(host):\(port)")
        case 22: return URL(string: "ssh://\(host)")
        case 445, 139: return URL(string: "smb://\(host)")
        case 548: return URL(string: "afp://\(host)")
        case 5900: return URL(string: "vnc://\(host)")
        case 21: return URL(string: "ftp://\(host)")
        default: return nil
        }
    }
}
