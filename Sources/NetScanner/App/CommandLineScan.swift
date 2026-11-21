//
//  CommandLineScan.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation

/// Headless mode: `NetScanner --scan [target]` prints the discovered devices as a table.
@MainActor
enum CommandLineScan {
    static func run(target: String?) {
        let verbose = CommandLine.arguments.contains("--verbose")
        SystemLimits.raiseFileDescriptorLimit()
        OUIDatabase.shared.loadPreferred()
        let model = AppModel()
        model.refreshInterfaces()
        if let first = model.interfaces.first(where: { $0.primaryIPv4 != nil }) { model.selectInterface(first.name) }
        if let target { model.targetText = target }
        print("Scanning \(model.targetText) …")

        model.startScan()
        var lastPhase = ""
        while model.isScanning {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            if model.phase != lastPhase {
                lastPhase = model.phase
                FileHandle.standardError.write("  [\(Int(model.progress * 100))%] \(model.phase)\n".data(using: .utf8)!)
            }
        }
        if let error = model.errorMessage { print("Error: \(error)"); exit(1) }

        func pad(_ s: String, _ n: Int) -> String { s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count) }
        print(pad("IP", 16), pad("HOSTNAME", 26), pad("TYPE", 22), pad("MODEL", 22), pad("VENDOR", 22), pad("MAC", 18), "SOURCES / PORTS")
        for d in model.visibleDevices {
            let extras = d.sources.map(\.rawValue).sorted().joined(separator: ",") + (d.openPorts.isEmpty ? "" : " | " + d.openPorts.sorted().map(String.init).joined(separator: ","))
            print(pad(d.primaryAddressText, 16), pad(d.hostname.map(HostnameResolver.shortName) ?? "—", 26), pad(d.kind.title, 22),
                  pad(d.modelName ?? "", 22), pad(d.vendorText, 22), pad(d.mac?.description ?? "—", 18), extras)
            if d.ipv6.count > 0 { print(String(repeating: " ", count: 17) + "IPv6: " + d.ipv6.map(\.description).joined(separator: ", ")) }
            if verbose, !d.services.isEmpty {
                print(String(repeating: " ", count: 17) + "Bonjour: " + d.services.map { "\($0.type) \"\($0.name)\" \($0.txt.filter { ["model", "md", "rpmd", "am", "ty", "fn"].contains($0.key) })" }.joined(separator: "; "))
            }
        }
        print("\n\(model.devices.count) devices in \(String(format: "%.1f", model.lastScanDuration ?? 0)) s" + (model.localNetworkDenied ? " — LOCAL NETWORK ACCESS DENIED" : ""))
        exit(0)
    }
}

/// Headless port scan through the same `PortScanSession` the UI uses:
/// `NetScanner --ports <address> [common|wellKnown|extended|all|"22,80,8000-8100"]`
@MainActor
enum CommandLinePortScan {
    static func run(address text: String, spec: String?) {
        SystemLimits.raiseFileDescriptorLimit()
        guard let address = IPAddress(text) else { print("Invalid address \(text)"); exit(1) }
        let deviceID = UUID()
        let session = PortScanSession(deviceID: deviceID, address: address)
        if let spec {
            if let preset = PortPreset(rawValue: spec) { session.preset = preset } else { session.preset = .custom; session.customPorts = spec }
        }
        var reported: [UInt16] = []
        session.onOpenPort = { id, port in if id == deviceID { reported.append(port) } }
        session.start()
        if let error = session.errorMessage { print(error); exit(1) }
        print("Scanning \(session.total) TCP ports on \(address.scopedDescription)…")
        while session.isRunning { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        for result in session.results {
            print(String(format: "%5d/tcp  open  %-16@ %6.1f ms  %@", result.port, result.service as NSString, result.latency * 1000, (result.detail ?? "") as NSString))
        }
        print("\(session.results.count) open, \(session.closedCount) closed, \(session.scanned) scanned in \(String(format: "%.1f", session.elapsed ?? 0)) s; write-back reported \(reported.count) ports")
        exit(0)
    }
}

/// Headless mode: `NetScanner --wifi` lists nearby Wi-Fi networks heard by the Mac's Wi-Fi card.
/// From a terminal, macOS withholds BSSIDs unless the terminal app has Location access.
@MainActor
enum CommandLineWiFi {
    static func run() {
        OUIDatabase.shared.loadPreferred()
        print("Scanning for Wi-Fi networks…")
        switch WiFiScanner.scan() {
        case .failure(.noInterface):
            print("This Mac doesn't have a Wi-Fi card."); exit(1)
        case .failure(.poweredOff):
            print("Wi-Fi is off."); exit(1)
        case .failure(.failed(let message)):
            print("Scan failed: \(message)"); exit(1)
        case .success(let scan):
            func pad(_ s: String, _ n: Int) -> String { s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count) }
            if let c = scan.connection {
                print("Connected on \(c.interfaceName ?? "?"): \(c.ssid ?? "(name hidden)") · \(c.bssid?.description ?? "BSSID hidden") · channel \(c.channel?.summary ?? "?") · \(c.rssi) dBm · \(Int(c.transmitRate)) Mbps")
            }
            print(pad("NETWORK", 28), pad("BSSID", 18), pad("CHANNEL", 22), pad("SIGNAL", 8), pad("SECURITY", 22), pad("STANDARD", 10), "VENDOR")
            for n in scan.networks {
                print(pad((n.isConnected ? "* " : "") + n.displayName, 28), pad(n.bssid?.description ?? "—", 18), pad(n.channel?.summary ?? "—", 22),
                      pad("\(n.rssi)", 8), pad(n.security.title, 22), pad(n.standard?.title ?? "—", 10), n.vendor ?? "")
            }
            print("\(scan.networks.count) networks on \(scan.interfaceName ?? "Wi-Fi")")
            exit(0)
        }
    }
}
