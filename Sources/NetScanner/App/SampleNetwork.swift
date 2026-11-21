//
//  SampleNetwork.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import AppKit

/// A made-up home network for screenshots. `NetScanner --demo [--light | --dark]` opens the window with
/// these devices instead of scanning, so nothing from the real network shows. Every name, address and
/// MAC here is invented; the MACs only borrow each maker's prefix.
@MainActor
enum SampleNetwork {
    static var isRequested: Bool { CommandLine.arguments.contains("--demo") }

    static func load(into model: AppModel) {
        let devices = makeDevices()
        model.showSample(devices, target: "192.168.1.0/24", selecting: devices.first { $0.kind == .macMini }?.id)
        let networks = makeWiFiNetworks()
        let current = networks.first(where: \.isConnected)
        model.wifi.showSample(networks, connection: WiFiConnection(
            interfaceName: "en1", hardwareAddress: MACAddress("3C:A6:F6:91:5E:73"), ssid: current?.ssid, bssid: current?.bssid,
            channel: current?.channel, rssi: current?.rssi ?? -48, noise: -92, transmitRate: 1201, standard: current?.standard,
            security: current?.security, countryCode: "US"), interfaceName: "en1")
    }

    /// Applies `--light` or `--dark`, and gives the window a size that reads well in a README.
    static func prepareWindow() {
        if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            window.setContentSize(NSSize(width: 1100, height: 780))
            window.center()
            // Focus the device list, so its selection shows in the accent color and no other control
            // wears a focus ring.
            if let list = window.contentView.flatMap(firstTable) { window.makeFirstResponder(list) }
        }
    }

    private static func firstTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews {
            if let table = firstTable(in: subview) { return table }
        }
        return nil
    }

    // MARK: Devices

    private static func makeDevices() -> [Device] {
        [
            device("192.168.1.1", "24:5A:4C:3E:91:07", vendor: "Ubiquiti Inc.", kind: .unifiRackGateway, latency: 0.6) {
                $0.isGateway = true
                $0.modelName = "Dream Machine Pro"
                $0.ubiquiti = UbiquitiInfo(address: $0.ipv4[0], hostname: "UDM-Pro", productName: "UDM-Pro", model: "UDMPRO",
                                           firmware: "4.3.6", osVersion: "4.3.6", uptime: 1_987_200)
                $0.openPorts = [22, 80, 443]
                $0.sources.formUnion([.tcp, .ubiquiti])
            },
            device("192.168.1.2", "24:5A:4C:3E:A2:18", vendor: "Ubiquiti Inc.", kind: .unifiRackSwitch, latency: 0.9) {
                $0.modelName = "Switch Pro 24 PoE"
                $0.ubiquiti = UbiquitiInfo(address: $0.ipv4[0], hostname: "Rack-Switch", productName: "USW-Pro-24-PoE", model: "US24PRO",
                                           firmware: "7.1.26", uptime: 1_986_400)
                $0.openPorts = [22]
                $0.sources.insert(.ubiquiti)
            },
            device("192.168.1.3", "24:5A:4C:3E:B6:2C", vendor: "Ubiquiti Inc.", kind: .unifiAccessPoint, latency: 1.4) {
                $0.modelName = "U7 Pro"
                $0.ubiquiti = UbiquitiInfo(address: $0.ipv4[0], hostname: "Office-AP", productName: "U7-Pro", model: "U7PRO",
                                           firmware: "8.0.19", uptime: 1_120_000)
                $0.openPorts = [22]
                $0.sources.insert(.ubiquiti)
            },
            device("192.168.1.4", "24:5A:4C:3E:C4:5D", vendor: "Ubiquiti Inc.", kind: .unifiWallAccessPoint, latency: 1.7) {
                $0.modelName = "U6 In-Wall"
                $0.ubiquiti = UbiquitiInfo(address: $0.ipv4[0], hostname: "Bedroom-AP", productName: "U6-IW", model: "U6IW",
                                           firmware: "6.7.17", uptime: 1_119_800)
                $0.openPorts = [22]
                $0.sources.insert(.ubiquiti)
            },
            device("192.168.1.10", "A4:FC:14:62:0B:3E", vendor: "Apple, Inc.", kind: .macMini, latency: 1.8) {
                $0.modelName = "Mac mini (M4 Pro)"
                $0.modelIdentifier = "Mac16,11"
                $0.mdnsName = "Studio-Mac-mini.local"
                $0.ipv6 = [IPv6Address("fe80::1c4f:9a2e:7b31:d0a5"), IPv6Address("fd4e:8a21:6c0f:1::10")].compactMap { $0 }
                $0.services = [
                    service("Studio Mac mini", "_device-info._tcp", host: "Studio-Mac-mini.local.", txt: ["model": "Mac16,11"]),
                    service("Studio Mac mini", "_companion-link._tcp", host: "Studio-Mac-mini.local.", port: 49153),
                    service("Studio Mac mini", "_smb._tcp", host: "Studio-Mac-mini.local.", port: 445),
                    service("Studio Mac mini", "_ssh._tcp", host: "Studio-Mac-mini.local.", port: 22),
                    service("Studio Mac mini", "_rfb._tcp", host: "Studio-Mac-mini.local.", port: 5900),
                ]
                $0.openPorts = [22, 445, 5000, 5900, 7000]
                $0.sources.formUnion([.mdns, .ndp, .tcp])
            },
            device("192.168.1.11", "3C:A6:F6:91:5E:72", vendor: "Apple, Inc.", kind: .macLaptop, latency: 0) {
                $0.isSelf = true
                $0.modelName = "MacBook Pro 14\" (M4)"
                $0.modelIdentifier = "Mac16,6"
                $0.mdnsName = "MacBook-Pro.local"
                $0.sources = [.local]
            },
            device("192.168.1.12", "D2:4B:7E:19:A0:C3", vendor: nil, kind: .iPhone, latency: 6.2) {
                $0.mdnsName = "Ava-iPhone.local"
                $0.services = [service("Ava’s iPhone", "_companion-link._tcp", host: "Ava-iPhone.local.", port: 49152)]
                $0.sources.insert(.mdns)
            },
            device("192.168.1.13", "8E:31:C5:6A:F2:04", vendor: nil, kind: .iPad, latency: 7.5) {
                $0.mdnsName = "Kitchen-iPad.local"
                $0.sources.insert(.mdns)
            },
            device("192.168.1.20", "C8:D0:83:47:1B:9A", vendor: "Apple, Inc.", kind: .appleTV, latency: 2.4) {
                $0.modelName = "Apple TV 4K (3rd generation)"
                $0.modelIdentifier = "AppleTV14,1"
                $0.mdnsName = "Living-Room.local"
                $0.services = [service("Living Room", "_airplay._tcp", host: "Living-Room.local.", port: 7000)]
                $0.openPorts = [7000]
                $0.sources.formUnion([.mdns, .tcp])
            },
            device("192.168.1.21", "F4:34:F0:2D:8C:61", vendor: "Apple, Inc.", kind: .homePodMini, latency: 3.1) {
                $0.modelIdentifier = "AudioAccessory5,1"
                $0.mdnsName = "Bedroom.local"
                $0.services = [service("Bedroom", "_airplay._tcp", host: "Bedroom.local.", port: 7000)]
                $0.sources.insert(.mdns)
            },
            device("192.168.1.30", "A0:D3:C1:5B:72:E8", vendor: "HP Inc.", kind: .printer, latency: 4.8) {
                $0.modelName = "OfficeJet Pro 9015e"
                $0.mdnsName = "HP-OfficeJet.local"
                $0.services = [service("HP OfficeJet Pro 9015e", "_ipp._tcp", host: "HP-OfficeJet.local.", port: 631)]
                $0.openPorts = [80, 443, 631, 9100]
                $0.sources.formUnion([.mdns, .tcp])
            },
            device("192.168.1.31", "00:11:32:A8:4F:16", vendor: "Synology Incorporated", kind: .nas, latency: 1.2) {
                $0.modelName = "DS923+"
                $0.dnsName = "nas.home.arpa"
                $0.netbiosName = "NAS"
                $0.workgroup = "WORKGROUP"
                $0.openPorts = [22, 80, 443, 445, 5000, 5001]
                $0.sources.formUnion([.netbios, .tcp])
            },
            device("192.168.1.40", "DC:A6:32:0E:57:B9", vendor: "Raspberry Pi Trading Ltd", kind: .singleBoardComputer, latency: 2.9) {
                $0.dnsName = "homeassistant.home.arpa"
                $0.openPorts = [22, 8123]
                $0.sources.insert(.tcp)
            },
            device("192.168.1.41", "48:A6:B8:72:C1:3D", vendor: "Sonos, Inc.", kind: .speaker, latency: 5.6) {
                $0.mdnsName = "Sonos-Kitchen.local"
                $0.services = [service("Kitchen", "_sonos._tcp", host: "Sonos-Kitchen.local.", port: 1443)]
                $0.sources.insert(.mdns)
            },
            device("192.168.1.42", "84:F3:EB:3B:90:4A", vendor: "Espressif Inc.", kind: .smartPlug, latency: 18.3) {
                $0.dnsName = "desk-lamp.home.arpa"
            },
        ]
    }

    // MARK: Wi-Fi

    private static func makeWiFiNetworks() -> [WiFiNetwork] {
        [
            wifi("Hillside", "24:5A:4C:3E:B6:2C", vendor: "Ubiquiti Inc.", 36, .ghz5, 80, rssi: -48, .personal("WPA2/WPA3"), .wifi6, connected: true),
            wifi("Hillside", "24:5A:4C:3E:B6:2B", vendor: "Ubiquiti Inc.", 6, .ghz2, 20, rssi: -55, .personal("WPA2/WPA3"), .wifi6),
            wifi("Hillside", "24:5A:4C:3E:C4:5E", vendor: "Ubiquiti Inc.", 149, .ghz5, 80, rssi: -67, .personal("WPA2/WPA3"), .wifi6),
            wifi("Hillside Guest", "26:5A:4C:3E:B6:2C", vendor: nil, 36, .ghz5, 80, rssi: -49, .personal("WPA2"), .wifi6),
            wifi("Hillside IoT", "26:5A:4C:3E:B6:2B", vendor: nil, 6, .ghz2, 20, rssi: -56, .personal("WPA2"), .wifi4),
            wifi("DIRECT-OfficeJet", "A2:D3:C1:5B:72:E9", vendor: nil, 11, .ghz2, 20, rssi: -61, .personal("WPA2"), .wifi4),
            wifi("Studio 6E", "F8:BB:BF:21:7C:40", vendor: "eero inc.", 37, .ghz6, 160, rssi: -63, .personal("WPA3"), .wifi6E),
            wifi("Maple Street", "A0:40:A0:8E:15:D2", vendor: "NETGEAR", 100, .ghz5, 80, rssi: -71, .personal("WPA2"), .wifi5),
            wifi("Maple Street", "A0:40:A0:8E:15:D1", vendor: "NETGEAR", 1, .ghz2, 20, rssi: -74, .personal("WPA2"), .wifi4),
            wifi("Linden", "04:D9:F5:6B:30:A8", vendor: "ASUSTek Computer Inc.", 52, .ghz5, 40, rssi: -78, .personal("WPA3"), .wifi6),
            wifi("Corner Café", "50:C7:BF:4D:09:E3", vendor: "TP-Link Systems Inc.", 11, .ghz2, 20, rssi: -80, .open, .wifi4),
            wifi(nil, "06:D9:F5:6B:30:A9", vendor: nil, 44, .ghz5, 40, rssi: -83, .enterprise("WPA2"), .wifi5),
        ]
    }

    private static func wifi(_ ssid: String?, _ bssid: String, vendor: String?, _ channel: Int, _ band: WiFiBand, _ width: Int, rssi: Int,
                             _ security: WiFiSecurity, _ standard: WiFiStandard, connected: Bool = false) -> WiFiNetwork {
        WiFiNetwork(id: bssid, ssid: ssid, bssid: MACAddress(bssid), vendor: vendor,
                    channel: WiFiChannel(number: channel, band: band, width: width),
                    rssi: rssi, noise: band == .ghz2 ? -90 : -92, security: security, standard: standard,
                    countryCode: "US", isConnected: connected)
    }

    private static func device(_ address: String, _ mac: String, vendor: String?, kind: DeviceKind, latency milliseconds: Double,
                               _ configure: (inout Device) -> Void) -> Device {
        var device = Device()
        device.ipv4 = IPv4Address(address).map { [$0] } ?? []
        device.mac = MACAddress(mac)
        device.vendor = vendor
        device.kind = kind
        device.latency = milliseconds / 1000
        device.sources = [.icmp, .arp]
        device.firstSeen = Date().addingTimeInterval(-6 * 86_400)
        device.lastSeen = Date().addingTimeInterval(-90)
        configure(&device)
        return device
    }

    private static func service(_ name: String, _ type: String, host: String, port: UInt16 = 0, txt: [String: String] = [:]) -> BonjourService {
        BonjourService(name: name, type: type, domain: "local.", host: host, port: port, txt: txt, interfaceIndex: 0)
    }
}
