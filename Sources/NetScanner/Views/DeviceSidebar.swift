//
//  DeviceSidebar.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI

struct DeviceSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let devices = model.visibleDevices

        List(selection: $model.selectedDeviceID) {
            ForEach(devices) { device in
                DeviceRow(device: device, isSelected: device.id == model.selectedDeviceID)
                    .tag(device.id)
                    .listRowSeparator(.hidden)
                    .contextMenu { DeviceContextMenu(device: device) }
            }
        }
        .listStyle(.sidebar)
        .scrollEdgeEffectStyle(.hard, for: .vertical)
        // Bars (not insets) so rows scrolling under the header and footer fade out instead of overlapping them.
        .safeAreaBar(edge: .top, spacing: 0) { header }
        .safeAreaBar(edge: .bottom, spacing: 0) { footer }
        .overlay {
            if model.devices.isEmpty {
                ContentUnavailableView {
                    Label(model.isScanning ? "Searching…" : "No Devices", systemImage: "network")
                } description: {
                    Text(model.isScanning ? "Devices appear here as they answer." : "Run a scan to discover devices on your network.")
                } actions: {
                    if !model.isScanning {
                        Button("Scan Network") { model.startScan() }
                            .buttonStyle(.glassProminent)
                    }
                }
            } else if devices.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "IP, name, vendor or MAC")
        .navigationSplitViewColumnWidth(min: 340, ideal: 390, max: 560)
    }

    private var header: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Devices")
                    .font(.title3.weight(.bold))
                Text("\(model.devices.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("Sort By", selection: $model.sort) {
                        ForEach(DeviceSort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .controlSize(.small)
                .fixedSize()
                .help("Sort devices")
            }

            FilterBar(selection: $model.filter) { model.count(for: $0) }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isScanning {
                ScanProgressRing(progress: model.progress, showsStop: false, diameter: 12)
                Text(model.phase)
                    .lineLimit(1)
            } else if let date = model.lastScanDate {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(model.onlineCount) online · scanned \(date, format: .relative(presentation: .named))")
                    .lineLimit(1)
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                Text("Ready to scan")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Full-width glass segmented control for the device filters.
/// A native segmented Picker keeps its intrinsic width on macOS, so this one is drawn by hand.
private struct FilterBar: View {
    @Binding var selection: DeviceFilter
    let count: (DeviceFilter) -> Int
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DeviceFilter.allCases) { filter in
                let selected = selection == filter
                Button {
                    withAnimation(.smooth(duration: 0.25)) { selection = filter }
                } label: {
                    Text(verbatim: "\(filter.title) (\(count(filter)))")
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "filter", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter")
    }
}

/// Sidebar row: icon, hostname and IP on the first line; vendor and MAC on the second.
struct DeviceRow: View {
    let device: Device
    /// A selected row sits on the accent color while the list has focus.
    var isSelected = false

    var body: some View {
        HStack(spacing: 11) {
            DeviceIconView(kind: device.kind, model: device.modelIdentifier, size: 38, isOnline: device.isOnline)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Until a name resolves, show what the device is rather than repeating its IP.
                    let named = device.displayName != device.primaryAddressText
                    Text(named ? device.displayName : device.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(named ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if device.isSelf {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("This Mac")
                    } else if device.isGateway {
                        Image(systemName: "arrow.up.forward.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Default gateway")
                    }
                    Spacer(minLength: 6)
                    Text(device.primaryAddressText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        // Accent-colored text would vanish on the accent-colored selection.
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(device.vendorText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(device.mac?.description ?? "—")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }

            Circle()
                .fill(device.isOnline ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
                .help(device.isOnline ? "Online" : "Not seen in the last scan")
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
    }
}

struct DeviceContextMenu: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        Button("Show Overview", systemImage: "info.circle") {
            model.selectedDeviceID = device.id
            model.detailTab = .overview
        }
        Button("Port Scan…", systemImage: "cable.connector") {
            model.selectedDeviceID = device.id
            model.detailTab = .ports
        }
        Divider()
        if let address = device.primaryAddress {
            Button("Copy IP Address", systemImage: "doc.on.doc") { model.copyToPasteboard(address.scopedDescription) }
        }
        if let mac = device.mac {
            Button("Copy MAC Address", systemImage: "doc.on.doc") { model.copyToPasteboard(mac.description) }
        }
        if let hostname = device.hostname {
            Button("Copy Hostname", systemImage: "doc.on.doc") { model.copyToPasteboard(hostname) }
        }
        Button("Copy Summary", systemImage: "doc.plaintext") { model.copyToPasteboard(model.summaryText(for: device)) }
        let webInterface = device.primaryAddress.flatMap { address in
            [443, 80, 8443, 8080].first { device.openPorts.contains(UInt16($0)) }.flatMap { PortCatalog.url(for: UInt16($0), address: address) }
        }
        if webInterface != nil || device.kind.isManagedByUniFiNetwork || device.canWake {
            Divider()
        }
        if device.canWake {
            Button("Wake", systemImage: "power") { model.wake(device) }
                .disabled(model.wakeStates[device.id] == .waking)
        }
        if device.kind.isManagedByUniFiNetwork {
            Button("Open in UniFi Network", systemImage: "arrow.up.forward.app") { model.openInUniFiNetwork(device) }
        }
        if let webInterface {
            Button("Open Web Interface", systemImage: "safari") { model.open(webInterface) }
        }
    }
}
