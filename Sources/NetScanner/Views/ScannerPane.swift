//
//  ScannerPane.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI

struct ScannerPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScanHeroCard()
                if model.localNetworkDenied { LocalNetworkWarning() }
                TargetCard()
                DiscoveryOptionsCard()
                if !model.devices.isEmpty { NetworkSummary() }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .readableColumn()
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

// MARK: - Hero

private struct ScanHeroCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 24) {
            RadarView(isScanning: model.isScanning, progress: model.progress)
                .frame(width: 132, height: 132)

            VStack(alignment: .leading, spacing: 8) {
                Text("Network Scanner")
                    .font(.largeTitle.weight(.bold))
                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if model.isScanning {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 360)
                }

                HStack(spacing: 10) {
                    if model.isScanning {
                        Button(role: .cancel) { model.stopScan() } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(minWidth: 90)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                    } else {
                        Button { model.startScan() } label: {
                            Label("Start Scan", systemImage: "play.fill")
                                .frame(minWidth: 110)
                        }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled((try? model.parsedTarget.get()) == nil)

                        if !model.devices.isEmpty {
                            Button { model.clearDevices() } label: {
                                Label("Clear", systemImage: "trash")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private var statusLine: String {
        if model.isScanning { return model.phase }
        if let date = model.lastScanDate {
            let duration = model.lastScanDuration.map { "\($0.formatted(.number.precision(.fractionLength(1)))) s" } ?? ""
            let devices = String(localized: "\(model.devices.count) devices")
            let found = String(localized: "Found \(devices) in \(duration)")
            return "\(found) · \(date.formatted(date: .omitted, time: .shortened))"
        }
        return String(localized: "Discover every device on a subnet or IP range over IPv4 and IPv6, then dig into any of them.")
    }
}

/// Concentric rings with a rotating sweep while scanning and a progress ring.
struct RadarView: View {
    var isScanning: Bool
    var progress: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !isScanning)) { timeline in
            let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360)
            ZStack {
                ForEach(1..<4) { ring in
                    Circle()
                        .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                        .scaleEffect(CGFloat(ring) / 3)
                }
                if isScanning {
                    Circle()
                        .fill(AngularGradient(stops: [
                            .init(color: Color.accentColor.opacity(0.0), location: 0.0),
                            .init(color: Color.accentColor.opacity(0.0), location: 0.70),
                            .init(color: Color.accentColor.opacity(0.55), location: 1.0),
                        ], center: .center))
                        .rotationEffect(angle)
                        .padding(6)
                }
                Circle()
                    .trim(from: 0, to: isScanning ? max(0.02, progress) : 0)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: progress)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: isScanning)
            }
        }
    }
}

private struct LocalNetworkWarning: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Local Network access is blocked")
                    .font(.headline)
                Text("macOS is preventing Network Scanner from reaching devices on your network. Allow it in System Settings › Privacy & Security › Local Network, then scan again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .rect(cornerRadius: 22))
    }
}

// MARK: - Target

private struct TargetCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        GlassCard("Target", systemImage: "scope", trailing: AnyView(refreshButton)) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Interface", selection: Binding(get: { model.selectedInterfaceName }, set: { model.selectInterface($0) })) {
                    ForEach(model.interfaces) { iface in
                        Label {
                            Text(interfaceTitle(iface))
                        } icon: {
                            Image(systemName: iface.symbol)
                        }
                        .tag(Optional(iface.name))
                    }
                    if model.interfaces.isEmpty {
                        Text("No active interfaces").tag(String?.none)
                    }
                }
                .disabled(model.isScanning)

                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                    TextField("192.168.1.0/24, 10.0.0.1-50, fe80::/64 …", text: $model.targetText)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { model.startScan() }
                        .disabled(model.isScanning)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.background.opacity(0.35), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))

                validation

                if let iface = model.selectedInterface {
                    FlowLayout(spacing: 6) {
                        if let v4 = iface.primaryIPv4 {
                            Pill(verbatim: "\(v4.address)/\(v4.prefixLength)", systemImage: "number", tint: .blue)
                        }
                        if let gateway = model.gateways.first(where: { $0.isV4 }) {
                            Pill(text: "Gateway \(gateway.description)", systemImage: "arrow.up.forward.circle", tint: .teal)
                        }
                        if let mac = iface.mac {
                            Pill(verbatim: mac.description, systemImage: "barcode", tint: .secondary)
                        }
                        let v6 = iface.ipv6.filter { !$0.address.isLinkLocal }.count
                        Pill(text: v6 > 0 ? "IPv6 · \(v6) global" : "IPv6 link-local", systemImage: "6.circle", tint: .purple)
                    }
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var refreshButton: some View {
        Button {
            model.refreshInterfaces()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help("Refresh network interfaces")
        .disabled(model.isScanning)
    }

    @ViewBuilder
    private var validation: some View {
        switch model.parsedTarget {
        case .success(let target):
            Label(target.summary.isEmpty ? "Nothing to scan" : target.summary, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func interfaceTitle(_ iface: NetworkInterface) -> String {
        if let v4 = iface.primaryIPv4 { return "\(iface.displayName) (\(iface.name)) — \(v4.cidr)" }
        return "\(iface.displayName) (\(iface.name)) — \(String(localized: "IPv6 only"))"
    }
}

// MARK: - Options

private struct DiscoveryOptionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        GlassCard("Discovery", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .leading)], alignment: .leading, spacing: 12) {
                    OptionToggle(title: "IPv4 sweep", detail: "ICMP echo, TCP probes and ARP", symbol: "network", isOn: $model.options.ipv4Sweep)
                    OptionToggle(title: "IPv6 discovery", detail: "Multicast ping and neighbor cache", symbol: "6.circle", isOn: $model.options.ipv6Discovery)
                    OptionToggle(title: "Bonjour / mDNS", detail: "Services, names and Apple models", symbol: "bonjour", isOn: $model.options.bonjour)
                    OptionToggle(title: "Multicast DNS names", detail: "Ask devices for their .local name", symbol: "at", isOn: $model.options.multicastDNS)
                    OptionToggle(title: "Reverse DNS", detail: "PTR lookups via your DNS server", symbol: "globe", isOn: $model.options.reverseDNS)
                    OptionToggle(title: "NetBIOS / SMB", detail: "Windows and Samba machine names", symbol: "externaldrive.connected.to.line.below", isOn: $model.options.netbios)
                    OptionToggle(title: "UniFi discovery", detail: "Ubiquiti model, name and firmware", symbol: "antenna.radiowaves.left.and.right", isOn: $model.options.ubiquiti)
                    OptionToggle(title: "Service fingerprint", detail: "Probe common ports on live hosts", symbol: "checklist", isOn: $model.options.fingerprint)
                }

                Divider()

                HStack(spacing: 18) {
                    HStack {
                        Text("Probe timeout")
                        Slider(value: $model.options.timeoutMilliseconds, in: 200...3000, step: 100)
                            .frame(minWidth: 120)
                        Text("\(Int(model.options.timeoutMilliseconds)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                    Picker("Parallel probes", selection: $model.options.parallelProbes) {
                        ForEach([64, 128, 256, 512], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .fixedSize()
                }
                .font(.callout)
            }
            .disabled(model.isScanning)
        }
    }
}

private struct OptionToggle: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

// MARK: - Summary

private struct NetworkSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let devices = model.devices
        let kinds = Dictionary(grouping: devices, by: \.kind).sorted { $0.value.count > $1.value.count }

        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                StatTile(value: "\(model.onlineCount)", label: "Online", systemImage: "dot.radiowaves.left.and.right", tint: .green)
                StatTile(value: "\(model.count(for: .apple))", label: "Apple", systemImage: "apple.logo", tint: .primary)
                StatTile(value: "\(model.count(for: .ubiquiti))", label: "UniFi", systemImage: "antenna.radiowaves.left.and.right", tint: .blue)
                StatTile(value: "\(devices.filter { !$0.ipv6.isEmpty }.count)", label: "With IPv6", systemImage: "6.circle", tint: .purple)
            }

            GlassCard("Device Types", systemImage: "square.grid.2x2") {
                FlowLayout(spacing: 8) {
                    ForEach(kinds, id: \.key) { kind, members in
                        Button {
                            model.searchText = kind.title
                        } label: {
                            HStack(spacing: 8) {
                                DeviceIconView(kind: kind, size: 24)
                                Text(kind.title)
                                Text("\(members.count)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 10)
                            .padding(.vertical, 4)
                            .background(.quaternary.opacity(0.6), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .help("Show \(kind.title) devices")
                    }
                }
            }
        }
    }
}
