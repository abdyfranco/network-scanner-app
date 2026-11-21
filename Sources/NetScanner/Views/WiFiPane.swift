//
//  WiFiPane.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI
import Charts

/// Nearby Wi-Fi networks, heard by the Mac's own Wi-Fi card.
struct WiFiPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        WiFiContent(session: model.wifi)
    }
}

private struct WiFiContent: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: WiFiSession

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                switch session.status {
                case .noInterface:
                    unavailable("No Wi-Fi", systemImage: "wifi.slash", "This Mac doesn't have a Wi-Fi card.")
                case .poweredOff:
                    unavailable("Wi-Fi Is Off", systemImage: "wifi.slash", "Turn on Wi-Fi in Control Center or System Settings, then scan again.")
                case .ready, .failed:
                    if case .failed(let message) = session.status {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if session.detailsHidden, let location = session.location { locationNotice(location.state) }
                    if let connection = session.connection { ConnectionCard(connection: connection, namesHidden: session.detailsHidden) }
                    if !session.networks.isEmpty {
                        channelsCard
                        networksCard
                    } else if session.lastScanDate != nil, !session.isScanning {
                        unavailable("No Networks Found", systemImage: "wifi.exclamationmark", "No Wi-Fi networks answered the scan.")
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .readableColumn(940)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task {
            if session.lastScanDate == nil { await session.scan() }
        }
        // Runs only while this tab shows: each scan briefly takes the radio off its channel.
        .task(id: session.keepsScanning) {
            guard session.keepsScanning else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: session.rescanInterval)
                guard !Task.isCancelled else { return }
                await session.scan()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "wifi")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 60, height: 60)
                .glassEffect(.regular.tint(.accentColor.opacity(0.18)), in: .rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text("Wi-Fi Networks")
                    .font(.title2.weight(.bold))
                Group {
                    if session.isScanning {
                        Text("Scanning…")
                    } else if let date = session.lastScanDate {
                        Text("\(session.networks.count) networks · scanned \(date, format: .relative(presentation: .named))")
                    } else {
                        Text("Not scanned yet")
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Keep Scanning", isOn: $session.keepsScanning)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Scans again every 20 seconds while this tab is open.")
            Button {
                Task { await session.scan() }
            } label: {
                if session.isScanning {
                    ProgressView().controlSize(.small).frame(minWidth: 70)
                } else {
                    Label("Scan", systemImage: "arrow.clockwise").frame(minWidth: 70)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(session.isScanning)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func unavailable(_ title: LocalizedStringKey, systemImage: String, _ description: LocalizedStringKey) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        }
        .padding(.vertical, 30)
    }

    // MARK: Location

    @ViewBuilder
    private func locationNotice(_ state: LocationAccess.State) -> some View {
        GlassCard("Location Access", systemImage: "location.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text(state == .servicesOff
                     ? "Location Services is off on this Mac. macOS shows network addresses (BSSIDs) and the name of the network you're on only to apps with Location access."
                     : "macOS shows network addresses (BSSIDs) and the name of the network you're on only to apps with Location access. Network Scanner doesn't use or keep your location.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if state == .notDetermined {
                    Button("Allow Location Access") { session.requestLocationAccess() }
                        .buttonStyle(.glassProminent)
                } else {
                    Button("Open Location Services Settings") { model.open(LocationAccess.settingsURL) }
                        .buttonStyle(.glass)
                }
            }
        }
    }

    // MARK: Channels

    private var channelsCard: some View {
        GlassCard("Channels", systemImage: "chart.bar.xaxis", trailing: AnyView(
            Picker("Band", selection: $session.chartBand) {
                ForEach(session.bandsHeard) { band in
                    Text(verbatim: band.title).tag(band)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        )) {
            ChannelChart(networks: session.networks(on: session.chartBand), band: session.chartBand)
                .frame(height: 210)
        }
    }

    // MARK: Networks

    private var networksCard: some View {
        let networks = session.visibleNetworks
        return GlassCard("Nearby Networks", systemImage: "wifi", trailing: AnyView(
            HStack(spacing: 8) {
                Picker("Band", selection: $session.band) {
                    Text("All Bands").tag(WiFiBand?.none)
                    ForEach(WiFiBand.allCases) { band in
                        Text(verbatim: band.title).tag(Optional(band))
                    }
                }
                Picker("Sort By", selection: $session.sort) {
                    ForEach(WiFiSort.allCases) { Text($0.title).tag($0) }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        )) {
            if networks.isEmpty {
                Text("No networks on this band.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(networks.enumerated()), id: \.element.id) { index, network in
                        if index > 0 { Divider().opacity(0.5) }
                        WiFiNetworkRow(network: network)
                    }
                }
            }
        }
    }
}

// MARK: - Connection

private struct ConnectionCard: View {
    let connection: WiFiConnection
    let namesHidden: Bool

    var body: some View {
        GlassCard("Current Connection", systemImage: "checkmark.circle.fill") {
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 4) {
                    InfoRow(label: "Network", value: connection.ssid ?? (namesHidden ? String(localized: "Needs Location access") : nil))
                    InfoRow(label: "BSSID", value: connection.bssid?.description, monospaced: true)
                    InfoRow(label: "Channel", value: connection.channel?.summary)
                    InfoRow(label: "Standard", value: connection.standard?.title)
                    InfoRow(label: "Security", value: connection.security?.title)
                }
                VStack(spacing: 4) {
                    InfoRow(label: "Signal", value: "\(connection.rssi) dBm")
                    InfoRow(label: "Noise", value: connection.noise < 0 ? "\(connection.noise) dBm" : nil)
                    InfoRow(label: "Signal-to-noise", value: connection.snr.map { "\($0) dB" })
                    InfoRow(label: "Transmit rate", value: connection.transmitRate > 0 ? "\(Int(connection.transmitRate)) Mbps" : nil)
                    InfoRow(label: "Interface", value: connection.interfaceName)
                }
            }
        }
    }
}

// MARK: - Network row

private struct WiFiNetworkRow: View {
    let network: WiFiNetwork

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi", variableValue: network.signalLevel)
                .font(.title3)
                .foregroundStyle(network.isConnected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: 30)
                .help(Text(verbatim: "\(network.rssi) dBm"))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(network.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(network.isHidden ? .secondary : .primary)
                        .lineLimit(1)
                    if network.security.isSecured {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if network.isConnected {
                        Pill(text: "Connected", systemImage: "checkmark", tint: .green)
                    }
                }
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(verbatim: "\(network.rssi) dBm")
                    .font(.callout.monospacedDigit().weight(.medium))
                if let channel = network.channel {
                    Text(verbatim: channel.summary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .textSelection(.enabled)
    }

    /// BSSID, maker, security and Wi-Fi generation, whichever are known.
    private var details: String {
        [network.bssid?.description, network.vendor, network.security.title, network.standard?.title]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - Channel chart

/// Each network as a trapezoid over the channels it occupies, as tall as its signal.
private struct ChannelChart: View {
    let networks: [WiFiNetwork]
    let band: WiFiBand

    /// Signal is drawn up from -100 dBm.
    private static let floor = -100

    private struct Point: Identifiable {
        let id: Int
        let channel: Double
        let height: Double
    }

    var body: some View {
        let labels = self.labels
        Chart {
            ForEach(networks) { network in
                let points = outline(of: network)
                ForEach(points) { point in
                    AreaMark(x: .value("Channel", point.channel), y: .value("Signal", point.height),
                             series: .value("Network", network.id), stacking: .unstacked)
                        .foregroundStyle(by: .value("Network", network.id))
                        .opacity(network.isConnected ? 0.35 : 0.16)
                    LineMark(x: .value("Channel", point.channel), y: .value("Signal", point.height),
                             series: .value("Network", network.id))
                        .foregroundStyle(by: .value("Network", network.id))
                        .lineStyle(StrokeStyle(lineWidth: network.isConnected ? 2.5 : 1.25))
                }
                if let channel = network.channel, let label = labels[network.id] {
                    PointMark(x: .value("Channel", channel.span.center), y: .value("Signal", Double(network.rssi - Self.floor)))
                        .opacity(0)
                        .annotation(position: .top, spacing: 2) {
                            Text(verbatim: label)
                                .font(.caption2.weight(network.isConnected ? .bold : .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: band.chartDomain)
        .chartYScale(domain: 0...80)
        .chartXAxis {
            AxisMarks(values: band.chartTicks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Int.self) { Text(verbatim: "\(number)") }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 20, 40, 60, 80]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let height = value.as(Int.self) { Text(verbatim: "\(height + Self.floor)") }
                }
            }
        }
        .chartYAxisLabel(position: .leading) { Text(verbatim: "dBm") }
        .accessibilityLabel(Text("Channels"))
    }

    /// One name per channel position, so labels don't pile up: the strongest network's, with
    /// "+2" when two more share that spot.
    private var labels: [WiFiNetwork.ID: String] {
        let placed = networks.filter { $0.channel != nil }
        var labels: [WiFiNetwork.ID: String] = [:]
        for group in Dictionary(grouping: placed, by: { $0.channel!.span.center }).values {
            let strongest = group.max { $0.rssi < $1.rssi }!
            labels[strongest.id] = group.count > 1 ? "\(strongest.displayName) +\(group.count - 1)" : strongest.displayName
        }
        return labels
    }

    private func outline(of network: WiFiNetwork) -> [Point] {
        guard let channel = network.channel else { return [] }
        let (center, half) = channel.span
        let top = Double(max(0, network.rssi - Self.floor))
        let slope = min(1, half / 3)
        return [
            Point(id: 0, channel: center - half, height: 0),
            Point(id: 1, channel: center - half + slope, height: top),
            Point(id: 2, channel: center + half - slope, height: top),
            Point(id: 3, channel: center + half, height: 0),
        ]
    }
}
