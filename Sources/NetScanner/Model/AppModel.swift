//
//  AppModel.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Observation
import AppKit

/// Progress of a Wake-on-LAN request.
enum WakeState: Equatable {
    case waking
    case awake
    /// Sent, but the device didn't answer a ping in time.
    case noReply
    /// Nothing could be sent.
    case failed
}

enum DetailTab: String, CaseIterable, Identifiable {
    case scanner, overview, ports, wifi
    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanner: return String(localized: "Scanner")
        case .overview: return String(localized: "Overview")
        case .ports: return String(localized: "Port Scan")
        case .wifi: return String(localized: "Wi-Fi")
        }
    }

    var symbol: String {
        switch self {
        case .scanner: return "dot.radiowaves.left.and.right"
        case .overview: return "info.circle"
        case .ports: return "cable.connector"
        case .wifi: return "wifi"
        }
    }
}

enum DeviceFilter: String, CaseIterable, Identifiable {
    case all, apple, ubiquiti, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .apple: return String(localized: "Apple")
        case .ubiquiti: return String(localized: "UniFi")
        case .other: return String(localized: "Other")
        }
    }

    func includes(_ device: Device) -> Bool {
        switch self {
        case .all: return true
        case .apple: return device.kind.family == .apple
        case .ubiquiti: return device.kind.family == .ubiquiti
        case .other: return device.kind.family == .other
        }
    }
}

enum DeviceSort: String, CaseIterable, Identifiable {
    case address, name, vendor, kind
    var id: String { rawValue }

    var title: String {
        switch self {
        case .address: return String(localized: "IP Address")
        case .name: return String(localized: "Name")
        case .vendor: return String(localized: "Vendor")
        case .kind: return String(localized: "Device Type")
        }
    }
}

@MainActor
@Observable
final class AppModel {
    // Configuration
    var interfaces: [NetworkInterface] = []
    var selectedInterfaceName: String?
    var targetText = ""
    var options = ScanOptions.load()

    // Results
    private(set) var devices: [Device] = []
    var selectedDeviceID: Device.ID?
    var filter: DeviceFilter = .all
    var sort: DeviceSort = .address
    var searchText = ""
    var detailTab: DetailTab = .scanner

    // Scan state
    private(set) var isScanning = false
    private(set) var progress: Double = 0
    private(set) var phase = String(localized: "Ready")
    private(set) var lastScanDate: Date?
    private(set) var lastScanDuration: TimeInterval?
    private(set) var gateways: [IPAddress] = []
    var localNetworkDenied = false
    var errorMessage: String?

    // UniFi
    /// The UniFi OS console found on this network, once something asked for it.
    private(set) var unifiConsole: UniFiConsole?
    @ObservationIgnored private var consoleLookup: Task<UniFiConsole?, Never>?
    /// Bumped by every scan: a lookup that started before it belongs to what may be another network.
    @ObservationIgnored private var consoleGeneration = 0

    // Wi-Fi
    /// Nearby Wi-Fi networks, from the Mac's own Wi-Fi card.
    let wifi = WiFiSession()

    // Wake-on-LAN
    private(set) var wakeStates: [Device.ID: WakeState] = [:]
    @ObservationIgnored private var wakeTasks: [Device.ID: Task<Void, Never>] = [:]

    // Vendor database
    private(set) var vendorStatus = OUIDatabase.Status(entries: 0, source: "Loading…", modified: nil)
    private(set) var isUpdatingVendors = false
    var vendorUpdateMessage: String?

    @ObservationIgnored private var positions: [UUID: Int] = [:]
    @ObservationIgnored private var ipIndex: [IPAddress: UUID] = [:]
    @ObservationIgnored private var macIndex: [MACAddress: UUID] = [:]
    @ObservationIgnored private var hostIndex: [String: UUID] = [:]
    @ObservationIgnored private var engine: ScanEngine?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanStarted = Date()
    @ObservationIgnored private var lastScannedTarget = ""
    @ObservationIgnored private var portSessions: [UUID: PortScanSession] = [:]
    @ObservationIgnored private var bootstrapped = false
    @ObservationIgnored private var ipv6AttachOnly = false
    /// Showing `SampleNetwork` (`--demo`): the network isn't scanned, and nothing is woken or looked up on it.
    @ObservationIgnored private var isSample = false

    // MARK: Lifecycle

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        refreshInterfaces()
        if let first = interfaces.first(where: { $0.primaryIPv4 != nil }) ?? interfaces.first {
            selectInterface(first.name)
        }
        Task.detached(priority: .utility) {
            OUIDatabase.shared.loadPreferred()
            let status = OUIDatabase.shared.status
            await MainActor.run { self.vendorDatabaseDidLoad(status) }
        }
    }

    /// Fills the window with made-up devices for screenshots, in place of a scan.
    func showSample(_ sample: [Device], target: String, selecting selection: Device.ID?) {
        isSample = true
        bootstrapped = true
        targetText = target
        devices = sample
        positions = Dictionary(uniqueKeysWithValues: sample.enumerated().map { ($1.id, $0) })
        lastScanDate = Date().addingTimeInterval(-90)
        lastScanDuration = 7.4
        progress = 1
        selectedDeviceID = selection
        detailTab = selection == nil ? .scanner : .overview
    }

    func refreshInterfaces() {
        interfaces = InterfaceInventory.current()
        gateways = RouteTable.defaultGateways()
    }

    func selectInterface(_ name: String?) {
        selectedInterfaceName = name
        if let name, let iface = interfaces.first(where: { $0.name == name }), let suggested = iface.suggestedTarget {
            targetText = suggested
        }
    }

    var selectedInterface: NetworkInterface? { interfaces.first { $0.name == selectedInterfaceName } }

    var parsedTarget: Result<ScanTarget, Error> { Result { try ScanTarget.parse(targetText) } }

    // MARK: Derived lists

    var selectedDevice: Device? {
        guard let id = selectedDeviceID, let index = positions[id], devices.indices.contains(index) else { return nil }
        return devices[index]
    }

    var visibleDevices: [Device] {
        let filtered = devices.filter { filter.includes($0) && $0.matches(searchText) }
        switch sort {
        case .address:
            return filtered.sorted(by: Self.addressOrder)
        case .name:
            return filtered.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .vendor:
            return filtered.sorted { a, b in
                let va = a.vendor ?? "~", vb = b.vendor ?? "~"
                return va != vb ? va.localizedStandardCompare(vb) == .orderedAscending : Self.addressOrder(a, b)
            }
        case .kind:
            return filtered.sorted { a, b in
                a.kind.title != b.kind.title ? a.kind.title < b.kind.title : Self.addressOrder(a, b)
            }
        }
    }

    private static func addressOrder(_ a: Device, _ b: Device) -> Bool {
        switch (a.primaryAddress, b.primaryAddress) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }

    func count(for filter: DeviceFilter) -> Int { devices.filter(filter.includes).count }

    var onlineCount: Int { devices.filter(\.isOnline).count }

    var subtitle: String {
        if isScanning { return String(localized: "Scanning \(targetText)…") }
        guard !devices.isEmpty else { return String(localized: "No scan yet") }
        return "\(String(localized: "\(devices.count) devices")) · \(String(localized: "\(onlineCount) online"))"
    }

    // MARK: Scanning

    func startScan() {
        guard !isScanning, !isSample else { return }
        errorMessage = nil
        var target: ScanTarget
        do {
            target = try ScanTarget.parse(targetText)
        } catch {
            errorMessage = error.localizedDescription
            detailTab = .scanner
            return
        }

        refreshInterfaces()
        let facing = interfacesFacing(target)
        let userTypedIPv6 = !target.ipv6.isEmpty || !target.ipv6Prefixes.isEmpty
        let targetIsLocal = target.ipv4.isEmpty || interfaces.contains { iface in
            iface.ipv4.contains { a in target.ipv4.contains(where: a.contains) }
        }
        if options.ipv6Discovery, targetIsLocal {
            for iface in facing { for prefix in iface.ipv6DiscoveryPrefixes { target.addIPv6Prefix(prefix) } }
        }
        // Scanning only part of a subnet: link-wide IPv6 discovery may only enrich devices in range.
        let coversSubnet = facing.contains { iface in
            guard let a = iface.primaryIPv4 else { return true }
            return target.contains(.v4(IPv4Address(a.network.value &+ 1))) && target.contains(.v4(IPv4Address(a.broadcast.value &- 1)))
        }
        ipv6AttachOnly = !userTypedIPv6 && !target.ipv4.isEmpty && !coversSubnet

        // The same subnet can be another network (another site, another Wi-Fi): look the console up again.
        forgetUniFiConsole()
        let normalizedTarget = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedTarget != lastScannedTarget {
            clearDevices()
        } else {
            for i in devices.indices { devices[i].isOnline = false }
        }
        lastScannedTarget = normalizedTarget

        addThisMac(interfaces: facing, target: target)
        markGateways()

        let engine = ScanEngine()
        self.engine = engine
        isScanning = true
        localNetworkDenied = false
        progress = 0
        phase = String(localized: "Starting…")
        scanStarted = Date()

        let config = ScanConfiguration(target: target, options: options, interfaces: facing)
        let (stream, continuation) = AsyncStream<ScanEvent>.makeStream(bufferingPolicy: .unbounded)
        Task.detached(priority: .userInitiated) {
            await engine.run(config) { continuation.yield($0) }
            continuation.finish()
        }
        scanTask = Task { [weak self] in
            for await event in stream { self?.apply(event) }
            self?.finishScan()
        }
    }

    func stopScan() {
        engine?.stop()
        phase = String(localized: "Stopping…")
    }

    private func finishScan() {
        isScanning = false
        lastScanDate = Date()
        lastScanDuration = Date().timeIntervalSince(scanStarted)
        progress = 1
        if engine?.isCancelled == true { phase = String(localized: "Scan stopped") }
        engine = nil
        scanTask = nil
    }

    func clearDevices() {
        devices.removeAll()
        positions.removeAll()
        ipIndex.removeAll()
        macIndex.removeAll()
        hostIndex.removeAll()
        selectedDeviceID = nil
        for session in portSessions.values { session.stop() }
        portSessions.removeAll()
        for task in wakeTasks.values { task.cancel() }
        wakeTasks.removeAll()
        wakeStates.removeAll()
        forgetUniFiConsole()
        if detailTab != .scanner { detailTab = .scanner }
    }

    private func interfacesFacing(_ target: ScanTarget) -> [NetworkInterface] {
        let matching = interfaces.filter { iface in
            iface.ipv4.contains { assignment in target.contains(.v4(assignment.network)) || target.contains(.v4(assignment.address)) ||
                target.contains(.v4(IPv4Address(assignment.network.value + 1))) }
        }
        if !matching.isEmpty { return matching }
        if let selected = selectedInterface { return [selected] }
        return Array(interfaces.prefix(1))
    }

    private func addThisMac(interfaces: [NetworkInterface], target: ScanTarget) {
        let addresses = interfaces.flatMap { iface in
            iface.ipv4.map { IPAddress.v4($0.address) } + iface.ipv6.map { IPAddress.v6($0.address) }
        }.filter { target.contains($0) }
        guard let first = addresses.first else { return }

        let id = upsert(first, mac: nil)
        for address in addresses.dropFirst() { attach(address, to: id) }
        for mac in interfaces.compactMap(\.mac) where macIndex[mac] == nil {
            macIndex[mac] = id
        }
        mutate(id) { device in
            device.isSelf = true
            device.mac = device.mac ?? interfaces.compactMap(\.mac).first
            device.extraMACs.formUnion(interfaces.compactMap(\.mac))
            device.mdnsName = LocalHost.localHostName ?? device.mdnsName
            if let name = LocalHost.computerName {
                device.services.removeAll { $0.type == "_device-info._tcp" && $0.host.isEmpty }
                device.services.append(BonjourService(name: name, type: "_device-info._tcp", domain: "local.", interfaceIndex: 0))
            }
            device.sources.insert(.local)
            device.latency = 0
        }
    }

    private func markGateways() {
        for gateway in gateways {
            guard let id = ipIndex[gateway] else { continue }
            mutate(id) { $0.isGateway = true }
        }
    }

    // MARK: Event handling

    /// IPv6 findings from link-wide discovery are dropped unless they belong to a device already in range.
    private func accepts(_ ip: IPAddress, mac: MACAddress? = nil, host: String? = nil) -> Bool {
        guard ipv6AttachOnly, ip.isV6 else { return true }
        if ipIndex[ip] != nil { return true }
        if let mac, macIndex[mac] != nil { return true }
        if let host, hostIndex[host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))] != nil { return true }
        return false
    }

    private func apply(_ event: ScanEvent) {
        switch event {
        case let .alive(ip, _, _) where !accepts(ip),
             let .openPort(ip, _) where !accepts(ip):
            return
        case let .neighbor(ip, mac, _) where !accepts(ip, mac: mac):
            return
        case let .bonjour(service, ip) where !accepts(ip, host: service.host):
            return
        case let .alive(ip, source, latency):
            let id = upsert(ip, mac: nil)
            mutate(id) { device in
                device.sources.insert(source)
                if let latency { device.latency = min(device.latency ?? latency, latency) }
            }

        case let .neighbor(ip, mac, source):
            let id = upsert(ip, mac: mac)
            mutate(id) { $0.sources.insert(source) }

        case let .openPort(ip, port):
            let id = upsert(ip, mac: nil)
            mutate(id) { device in
                device.openPorts.insert(port)
                device.sources.insert(.tcp)
            }

        case let .hostname(ip, name, source):
            guard let id = ipIndex[ip] else { return }
            mutate(id) { device in
                switch source {
                case .dns: if device.dnsName == nil { device.dnsName = name }
                case .mdns: if device.mdnsName == nil { device.mdnsName = name }
                }
            }
            hostIndex[name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))] = id

        case let .netbios(info):
            let id = upsert(.v4(info.address), mac: nil)
            adoptWeakMAC(info.mac, for: id)
            mutate(id) { device in
                device.netbiosName = info.name ?? device.netbiosName
                device.workgroup = info.workgroup ?? device.workgroup
                if info.isFileServer { device.openPorts.insert(139) }
                device.sources.insert(.netbios)
            }

        case let .ubiquiti(info):
            let id = upsert(.v4(info.address), mac: nil)
            adoptWeakMAC(info.macForAddress, for: id)
            for mac in info.allMACs where macIndex[mac] == nil { macIndex[mac] = id }
            mutate(id) { device in
                device.ubiquiti = info
                device.extraMACs.formUnion(info.allMACs.filter { $0 != device.mac })
                device.sources.insert(.ubiquiti)
            }

        case let .bonjour(service, ip):
            let id = upsert(ip, mac: nil, host: service.host)
            mutate(id) { device in
                if let index = device.services.firstIndex(where: { $0.id == service.id }) {
                    device.services[index] = service
                } else {
                    device.services.append(service)
                    device.services.sort { $0.type < $1.type }
                }
                if device.mdnsName == nil, !service.host.isEmpty {
                    device.mdnsName = service.host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                }
                device.sources.insert(.mdns)
            }

        case let .progress(value, text):
            progress = max(progress, value)
            phase = text

        case .localNetworkDenied:
            localNetworkDenied = true
        }
    }

    // MARK: Device store

    /// Finds or creates the device record for an address, merging records when a MAC or
    /// hostname proves two addresses belong to the same hardware.
    @discardableResult
    private func upsert(_ ip: IPAddress, mac rawMAC: MACAddress?, host: String? = nil) -> UUID {
        let mac = (rawMAC?.isUsable ?? false) ? rawMAC : nil
        let hostKey = host.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.flatMap { $0.isEmpty ? nil : $0 }
        var id: UUID

        if let mac, let byMAC = macIndex[mac], positions[byMAC] != nil {
            id = byMAC
            if let byIP = ipIndex[ip], byIP != byMAC, let other = device(byIP) {
                if other.mac == nil || other.mac == mac { merge(byIP, into: byMAC) } else { detach(ip, from: byIP) }
            }
        } else if let byIP = ipIndex[ip], let existing = device(byIP) {
            id = byIP
            if let mac {
                if existing.mac == nil {
                    mutate(byIP) { $0.mac = mac }
                    macIndex[mac] = byIP
                } else if existing.mac != mac, !existing.extraMACs.contains(mac), !existing.isSelf {
                    // The address now belongs to different hardware (e.g. a DHCP lease moved).
                    detach(ip, from: byIP)
                    id = create(mac: mac)
                }
            }
        } else if let hostKey, let byHost = hostIndex[hostKey], positions[byHost] != nil {
            id = byHost
            if let mac, device(byHost)?.mac == nil {
                mutate(byHost) { $0.mac = mac }
                macIndex[mac] = byHost
            }
        } else {
            id = create(mac: mac)
        }

        attach(ip, to: id)
        if let hostKey { hostIndex[hostKey] = id }
        return id
    }

    private func device(_ id: UUID) -> Device? {
        positions[id].map { devices[$0] }
    }

    private func create(mac: MACAddress?) -> UUID {
        var device = Device()
        device.mac = mac
        devices.append(device)
        positions[device.id] = devices.count - 1
        if let mac { macIndex[mac] = device.id }
        return device.id
    }

    private func attach(_ ip: IPAddress, to id: UUID) {
        ipIndex[ip] = id
        mutate(id) { device in
            switch ip {
            case .v4(let a):
                if !device.ipv4.contains(a) {
                    device.ipv4.append(a)
                    device.ipv4.sort()
                }
            case .v6(let a):
                if !device.ipv6.contains(a) {
                    device.ipv6.append(a)
                    device.ipv6.sort { IPAddress.v6($0) < IPAddress.v6($1) }
                }
            }
            if gateways.contains(ip) { device.isGateway = true }
        }
    }

    private func detach(_ ip: IPAddress, from id: UUID) {
        if ipIndex[ip] == id { ipIndex[ip] = nil }
        mutate(id) { device in
            switch ip {
            case .v4(let a): device.ipv4.removeAll { $0 == a }
            case .v6(let a): device.ipv6.removeAll { $0 == a }
            }
        }
    }

    /// Weak MACs (NetBIOS, UniFi) never override an ARP/NDP-confirmed address.
    private func adoptWeakMAC(_ mac: MACAddress?, for id: UUID) {
        guard let mac, mac.isUsable, device(id)?.mac == nil else { return }
        if let owner = macIndex[mac], owner != id, positions[owner] != nil {
            merge(id, into: owner)
            return
        }
        mutate(id) { $0.mac = mac }
        macIndex[mac] = id
    }

    private func merge(_ sourceID: UUID, into targetID: UUID) {
        guard sourceID != targetID, let source = device(sourceID) else { return }
        mutate(targetID) { target in
            for a in source.ipv4 where !target.ipv4.contains(a) { target.ipv4.append(a) }
            for a in source.ipv6 where !target.ipv6.contains(a) { target.ipv6.append(a) }
            target.ipv4.sort()
            target.ipv6.sort { IPAddress.v6($0) < IPAddress.v6($1) }
            if target.mac == nil { target.mac = source.mac }
            target.extraMACs.formUnion(source.extraMACs)
            target.dnsName = target.dnsName ?? source.dnsName
            target.mdnsName = target.mdnsName ?? source.mdnsName
            target.netbiosName = target.netbiosName ?? source.netbiosName
            target.workgroup = target.workgroup ?? source.workgroup
            target.ubiquiti = target.ubiquiti ?? source.ubiquiti
            for service in source.services where !target.services.contains(where: { $0.id == service.id }) {
                target.services.append(service)
            }
            target.openPorts.formUnion(source.openPorts)
            target.sources.formUnion(source.sources)
            target.latency = [target.latency, source.latency].compactMap { $0 }.min()
            target.isGateway = target.isGateway || source.isGateway
            target.isSelf = target.isSelf || source.isSelf
            target.firstSeen = min(target.firstSeen, source.firstSeen)
        }

        for (key, value) in ipIndex where value == sourceID { ipIndex[key] = targetID }
        for (key, value) in macIndex where value == sourceID { macIndex[key] = targetID }
        for (key, value) in hostIndex where value == sourceID { hostIndex[key] = targetID }

        if let index = positions[sourceID] {
            devices.remove(at: index)
            positions = Dictionary(uniqueKeysWithValues: devices.enumerated().map { ($1.id, $0) })
        }
        if selectedDeviceID == sourceID { selectedDeviceID = targetID }
        if let session = portSessions.removeValue(forKey: sourceID) { session.stop() }
    }

    private func mutate(_ id: UUID, _ body: (inout Device) -> Void) {
        guard let index = positions[id] else { return }
        var device = devices[index]
        body(&device)
        if isScanning || device.isSelf {
            device.isOnline = true
            device.lastSeen = Date()
        }
        refreshDerived(&device)
        devices[index] = device
    }

    private func refreshDerived(_ device: inout Device) {
        if device.vendor == nil, let mac = device.mac {
            device.vendor = OUIDatabase.shared.vendor(for: mac)
        }
        let result = DeviceClassifier.classify(device)
        device.kind = result.kind
        device.modelName = result.modelName
        device.modelIdentifier = result.modelIdentifier
    }

    private func vendorDatabaseDidLoad(_ status: OUIDatabase.Status) {
        vendorStatus = status
        for i in devices.indices {
            var device = devices[i]
            device.vendor = nil
            refreshDerived(&device)
            devices[i] = device
        }
    }

    // MARK: Port scanning

    func portScanSession(for device: Device) -> PortScanSession {
        if let session = portSessions[device.id] { return session }
        // Sample devices have made-up addresses that may belong to something real: don't probe them.
        let session = PortScanSession(deviceID: device.id, address: isSample ? nil : device.primaryAddress)
        session.timeoutMilliseconds = max(400, options.timeoutMilliseconds)
        session.onOpenPort = { [weak self] id, port in
            self?.mutate(id) { $0.openPorts.insert(port) }
        }
        portSessions[device.id] = session
        return session
    }

    // MARK: Vendor database

    func updateVendorDatabase() {
        guard !isUpdatingVendors else { return }
        isUpdatingVendors = true
        vendorUpdateMessage = nil
        Task {
            do {
                let count = try await OUIDatabase.shared.updateFromIEEE()
                vendorUpdateMessage = String(localized: "Downloaded \(count) vendor prefixes.")
            } catch {
                vendorUpdateMessage = String(localized: "Update failed: \(error.localizedDescription)")
            }
            isUpdatingVendors = false
            vendorDatabaseDidLoad(OUIDatabase.shared.status)
        }
    }

    func resetVendorDatabase() {
        OUIDatabase.shared.resetToBuiltIn()
        vendorUpdateMessage = String(localized: "Using the built-in vendor database.")
        vendorDatabaseDidLoad(OUIDatabase.shared.status)
    }

    // MARK: Wake-on-LAN

    /// Sends a wake signal, then pings the device until it answers.
    func wake(_ device: Device) {
        guard device.canWake, !isSample, let mac = device.mac else { return }
        let id = device.id
        let broadcasts = interfaces.flatMap(\.ipv4).filter { !$0.address.isLinkLocal }.map(\.broadcast)
        let addresses = device.ipv4
        wakeTasks[id]?.cancel()
        wakeStates[id] = .waking
        wakeTasks[id] = Task {
            let sent = await Task.detached { WakeOnLAN.wake(mac, broadcasts: broadcasts, lastKnown: addresses) }.value
            guard !Task.isCancelled else { return }
            guard sent else {
                wakeStates[id] = .failed
                wakeTasks[id] = nil
                return
            }
            // A Mac wakes in seconds; a PC starting from off can take a minute or more.
            let latency = await Self.waitForReply(from: addresses, timeout: 120)
            guard !Task.isCancelled else { return }
            guard let latency else {
                wakeStates[id] = .noReply
                wakeTasks[id] = nil
                return
            }
            wakeStates[id] = .awake
            markAwake(id, latency: latency)
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            wakeStates[id] = nil
            wakeTasks[id] = nil
        }
    }

    /// Pings until one of the addresses answers. Returns the round-trip time, or nil after the timeout.
    nonisolated private static func waitForReply(from addresses: [IPv4Address], timeout: TimeInterval) async -> TimeInterval? {
        guard !addresses.isEmpty else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            let latency = await Task.detached { () -> TimeInterval? in
                let stop = CancelToken()
                var first: TimeInterval?
                ICMPPinger.sweepV4(addresses, timeout: 1.5, cancel: stop) { _, rtt in
                    first = first ?? rtt
                    stop.cancel()
                }
                return first
            }.value
            if let latency { return latency }
            try? await Task.sleep(for: .seconds(1))
        }
        return nil
    }

    private func markAwake(_ id: Device.ID, latency: TimeInterval) {
        guard let index = positions[id], devices.indices.contains(index) else { return }
        devices[index].isOnline = true
        devices[index].latency = latency
        devices[index].lastSeen = Date()
    }

    // MARK: UniFi Network

    /// Finds the UniFi OS console that hosts UniFi Network: UniFi consoles in the list first
    /// (the network's gateway before the others), then the Mac's default gateways.
    @discardableResult
    func findUniFiConsole() async -> UniFiConsole? {
        if let unifiConsole { return unifiConsole }
        if isSample { return nil }
        let generation = consoleGeneration
        if let consoleLookup {
            let console = await consoleLookup.value
            return generation == consoleGeneration ? console : nil
        }
        let consoles = devices.filter(\.kind.hostsUniFiOS).sorted { $0.isGateway && !$1.isGateway }
        var seen = Set<IPv4Address>()
        let candidates = (consoles.flatMap(\.ipv4) + gateways.compactMap { address -> IPv4Address? in
            if case let .v4(v4) = address { return v4 }
            return nil
        }).filter { seen.insert($0).inserted }
        let lookup = Task { () -> UniFiConsole? in
            for address in candidates where !Task.isCancelled {
                if let console = await UniFiConsole.probe(address) { return console }
            }
            return nil
        }
        consoleLookup = lookup
        let console = await lookup.value
        // A scan started meanwhile: this answer may be about the previous network.
        guard generation == consoleGeneration else { return nil }
        consoleLookup = nil
        unifiConsole = console
        return console
    }

    private func forgetUniFiConsole() {
        consoleGeneration += 1
        consoleLookup?.cancel()
        consoleLookup = nil
        unifiConsole = nil
    }

    /// Opens the device's panel in UniFi Network. Without a console on this network, opens
    /// unifi.ui.com, where the console can be picked.
    func openInUniFiNetwork(_ device: Device) {
        Task {
            if let console = await findUniFiConsole(),
               let url = console.networkURL(deviceMAC: unifiMAC(of: device, console: console)) {
                open(url)
            } else if let url = URL(string: "https://unifi.ui.com") {
                open(url)
            }
        }
    }

    /// The MAC UniFi Network lists the device under, or nil to open the device list instead.
    private func unifiMAC(of device: Device, console: UniFiConsole) -> MACAddress? {
        // Cloud Keys host UniFi Network but aren't devices in it.
        if device.kind == .unifiCloudKey { return nil }
        let isConsole = device.ipv4.contains(console.address)
            || console.mac.map { device.ubiquiti?.allMACs.contains($0) ?? false } == true
        if isConsole { return console.mac ?? device.ubiquiti?.baseMAC }
        if let mac = device.ubiquiti?.baseMAC { return mac }
        if let mac = device.mac, !mac.isLocallyAdministered { return mac }
        return nil
    }

    // MARK: Utilities

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func summaryText(for device: Device) -> String {
        var lines = ["\(device.displayName) — \(device.subtitle)"]
        lines += device.addresses.map { "IP: \($0.scopedDescription)" }
        if let mac = device.mac { lines.append("MAC: \(mac)") }
        lines.append(String(localized: "Vendor: \(device.vendorText)"))
        if let hostname = device.hostname { lines.append(String(localized: "Hostname: \(hostname)")) }
        if !device.openPorts.isEmpty {
            let ports = device.openPorts.sorted().map(String.init).joined(separator: ", ")
            lines.append(String(localized: "Open ports: \(ports)"))
        }
        return lines.joined(separator: "\n")
    }
}
