//
//  DeviceOverviewPane.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI

struct DeviceOverviewPane: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                quickStats
                // fixedSize + fillsHeight gives both cards in a row the height of the taller one.
                HStack(alignment: .top, spacing: 18) {
                    networkCard
                    identityCard
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 18) {
                    hardwareCard
                    discoveryCard
                }
                .fixedSize(horizontal: false, vertical: true)
                if !device.services.isEmpty { servicesCard }
                portsCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .readableColumn(940)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            DeviceIconView(kind: device.kind, model: device.modelIdentifier, size: 112, isOnline: device.isOnline)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            Text(device.displayName)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Text(device.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                Pill(text: device.isOnline ? "Online" : "Offline", systemImage: "circle.fill", tint: device.isOnline ? .green : .secondary)
                if device.isSelf { Pill(text: "This Mac", systemImage: "person.crop.circle", tint: .blue) }
                if device.isGateway { Pill(text: "Gateway", systemImage: "arrow.up.forward.circle", tint: .teal) }
                if device.hasPrivateMAC { Pill(text: "Private MAC", systemImage: "lock.shield", tint: .orange) }
                if !device.ipv6.isEmpty { Pill(text: "IPv6", systemImage: "6.circle", tint: .purple) }
            }
            .fixedSize()
            if device.canWake || device.kind.isManagedByUniFiNetwork {
                HStack(spacing: 10) {
                    if device.canWake { WakeButton(device: device) }
                    if device.kind.isManagedByUniFiNetwork { UniFiNetworkButton(device: device) }
                }
                .padding(.top, 6)
            }
            if let note = wakeNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
        }
        .padding(.top, 8)
    }

    /// Explains a wake signal that got no answer.
    private var wakeNote: LocalizedStringKey? {
        switch model.wakeStates[device.id] {
        case .noReply:
            return "The wake signal was sent, but the device hasn't answered yet. If it stays asleep, turn on Wake for network access (Mac) or Wake-on-LAN (PC) on it."
        case .failed:
            return "Couldn't send the wake signal. Check that Network Scanner has Local Network access."
        default:
            return nil
        }
    }

    private var quickStats: some View {
        HStack(spacing: 0) {
            stat(device.latency.map { $0 < 0.001 ? "<1 ms" : String(format: "%.0f ms", $0 * 1000) } ?? "—", "Latency", "timer")
            Divider().frame(height: 34)
            stat("\(device.openPorts.count)", "Open ports", "cable.connector")
            Divider().frame(height: 34)
            stat("\(Set(device.services.map(\.type)).count)", "Services", "bonjour")
            Divider().frame(height: 34)
            stat("\(device.addresses.count)", "Addresses", "number")
        }
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func stat(_ value: String, _ label: LocalizedStringKey, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Cards

    private var networkCard: some View {
        GlassCard("Network", systemImage: "network", fillsHeight: true) {
            VStack(spacing: 4) {
                ForEach(device.ipv4, id: \.self) { InfoRow(label: "IPv4", value: $0.description, monospaced: true) }
                ForEach(device.ipv6, id: \.self) { InfoRow(label: $0.isLinkLocal ? "IPv6 link-local" : "IPv6", value: $0.scopedDescription, monospaced: true) }
                InfoRow(label: "MAC", value: device.mac?.description, monospaced: true)
                InfoRow(label: "Vendor", value: device.vendorText)
                ForEach(device.extraMACs.sorted().filter { $0 != device.mac }, id: \.self) {
                    InfoRow(label: "Other MAC", value: $0.description, monospaced: true)
                }
            }
        }
    }

    private var identityCard: some View {
        GlassCard("Names", systemImage: "person.text.rectangle", fillsHeight: true) {
            VStack(spacing: 4) {
                InfoRow(label: "Hostname", value: device.hostname)
                InfoRow(label: "mDNS", value: device.mdnsName)
                InfoRow(label: "DNS", value: device.dnsName)
                InfoRow(label: "NetBIOS", value: device.netbiosName)
                if let workgroup = device.workgroup { InfoRow(label: "Workgroup", value: workgroup) }
                InfoRow(label: "Bonjour name", value: device.bonjourName)
            }
        }
    }

    private var hardwareCard: some View {
        GlassCard("Hardware", systemImage: "cpu", fillsHeight: true) {
            VStack(spacing: 4) {
                InfoRow(label: "Type", value: device.kind.title)
                InfoRow(label: "Model", value: device.modelName)
                InfoRow(label: "Model ID", value: device.modelIdentifier, monospaced: true)
                if let info = device.ubiquiti {
                    InfoRow(label: "Firmware", value: info.firmware, monospaced: true)
                    if let os = info.osVersion { InfoRow(label: "UniFi OS", value: os, monospaced: true) }
                    if let uptime = info.uptime { InfoRow(label: "Uptime", value: Self.format(uptime: uptime)) }
                }
            }
        }
    }

    private var discoveryCard: some View {
        GlassCard("Discovery", systemImage: "dot.radiowaves.left.and.right", fillsHeight: true) {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 6) {
                    ForEach(DiscoverySource.allCases.filter(device.sources.contains), id: \.self) { source in
                        Pill(verbatim: source.title, tint: .accentColor)
                    }
                }
                InfoRow(label: "First seen", value: device.firstSeen.formatted(date: .abbreviated, time: .standard))
                InfoRow(label: "Last seen", value: device.lastSeen.formatted(date: .abbreviated, time: .standard))
            }
        }
    }

    private var servicesCard: some View {
        GlassCard("Bonjour Services", systemImage: "bonjour") {
            VStack(spacing: 0) {
                ForEach(Array(device.services.enumerated()), id: \.element.id) { index, service in
                    if index > 0 { Divider().opacity(0.5) }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BonjourCatalog.title(for: service.type))
                                .font(.callout.weight(.medium))
                            Text(service.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(service.type)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                        if service.port > 0 {
                            Text(verbatim: ":\(service.port)")
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 56, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 6)
                    .help(service.txt.isEmpty ? service.host : service.txt.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
                }
            }
        }
    }

    private var portsCard: some View {
        GlassCard("Open Ports", systemImage: "cable.connector", trailing: AnyView(
            Button {
                model.detailTab = .ports
            } label: {
                Label("Port Scan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
        )) {
            if device.openPorts.isEmpty {
                Text("No open ports found yet. Run a port scan to probe this device in depth.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(device.openPorts.sorted(), id: \.self) { port in
                        PortChip(port: port, address: device.primaryAddress)
                    }
                }
            }
        }
    }

    private static func format(uptime: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: uptime) ?? "—"
    }
}

/// Sends a Wake-on-LAN signal, then shows when the device answers.
struct WakeButton: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        let state = model.wakeStates[device.id]
        Button {
            model.wake(device)
        } label: {
            switch state {
            case .waking:
                Label {
                    Text("Waking…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
            case .awake:
                Label("Awake", systemImage: "checkmark.circle.fill")
            default:
                Label("Wake", systemImage: "power")
            }
        }
        .buttonStyle(.glassProminent)
        .tint(state == .awake ? .green : nil)
        .disabled(state == .waking)
        .help(Text("Sends a Wake-on-LAN signal to \(device.mac?.description ?? "—")."))
    }
}

/// Opens the device in the UniFi Network app on the network's UniFi console.
struct UniFiNetworkButton: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        Button {
            model.openInUniFiNetwork(device)
        } label: {
            Label("Open in UniFi Network", systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(.glassProminent)
        .help(help)
        // Looks the console up ahead of the click, so the button opens the page at once.
        .task(id: device.id) { await model.findUniFiConsole() }
    }

    private var help: Text {
        if let name = model.unifiConsole?.name {
            return Text("Opens this device in UniFi Network on \(name).")
        }
        return Text("Opens this device in UniFi Network.")
    }
}

struct PortChip: View {
    @Environment(AppModel.self) private var model
    let port: UInt16
    let address: IPAddress?

    var body: some View {
        let url = address.flatMap { PortCatalog.url(for: port, address: $0) }
        Group {
            if let url {
                Button { model.open(url) } label: { chip(isLink: true) }
                    .buttonStyle(.plain)
            } else {
                chip(isLink: false)
            }
        }
        .help(PortCatalog.serviceDescription(for: port) ?? PortCatalog.serviceName(for: port))
    }

    private func chip(isLink: Bool) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: String(port))
                .font(.callout.monospacedDigit().weight(.semibold))
            Text(PortCatalog.serviceName(for: port))
                .font(.caption)
                .foregroundStyle(.secondary)
            if isLink {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: .capsule)
    }
}
