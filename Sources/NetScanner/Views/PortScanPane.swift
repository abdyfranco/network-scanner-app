//
//  PortScanPane.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI

struct PortScanPane: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        PortScanContent(device: device, session: model.portScanSession(for: device))
            .id(device.id)
    }
}

private struct PortScanContent: View {
    @Environment(AppModel.self) private var model
    let device: Device
    @Bindable var session: PortScanSession

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                configuration
                results
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .readableColumn(900)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onAppear {
            if session.address == nil || !device.addresses.contains(session.address!) {
                session.address = device.primaryAddress
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            DeviceIconView(kind: device.kind, model: device.modelIdentifier, size: 60, isOnline: device.isOnline)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.title2.weight(.bold))
                Text(device.subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var configuration: some View {
        GlassCard("Port Scan", systemImage: "cable.connector") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Address", selection: $session.address) {
                    ForEach(device.addresses, id: \.self) { address in
                        Text(address.scopedDescription).tag(Optional(address))
                    }
                }
                .font(.body.monospaced())

                Picker("Ports", selection: $session.preset) {
                    ForEach(PortPreset.allCases) { preset in
                        Text(preset == .common ? String(localized: "Common (\(PortCatalog.common.count))") : preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                if session.preset == .custom {
                    TextField("22, 80, 443, 8000-8100", text: $session.customPorts)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .onSubmit { session.start() }
                }

                HStack(spacing: 18) {
                    HStack {
                        Text("Timeout")
                        Slider(value: $session.timeoutMilliseconds, in: 200...3000, step: 100)
                            .frame(minWidth: 120)
                        Text("\(Int(session.timeoutMilliseconds)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                    Picker("Parallel", selection: $session.parallelProbes) {
                        ForEach([64, 128, 192, 384], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .fixedSize()
                }
                .font(.callout)

                HStack(spacing: 12) {
                    if session.isRunning {
                        Button(role: .cancel) { session.stop() } label: {
                            Label("Stop", systemImage: "stop.fill").frame(minWidth: 80)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                    } else {
                        Button { session.start() } label: {
                            Label("Scan Ports", systemImage: "play.fill").frame(minWidth: 100)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(session.address == nil)
                    }
                    if session.total > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: session.progress)
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .controlSize(.large)

                if let error = session.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var statusText: String {
        let elapsed = session.elapsed.map { "\($0.formatted(.number.precision(.fractionLength(1)))) s" } ?? ""
        let state = session.isRunning ? String(localized: "Scanning") : String(localized: "Finished")
        let parts = [
            state,
            String(localized: "\(session.scanned) of \(session.total) ports"),
            String(localized: "\(session.results.count) open"),
            String(localized: "\(session.closedCount) closed"),
            elapsed,
        ]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var results: some View {
        if session.total > 0 {
            GlassCard("Open Ports", systemImage: "checkmark.shield") {
                if session.results.isEmpty {
                    HStack {
                        if session.isRunning { ProgressView().controlSize(.small) }
                        Text(session.isRunning ? "Waiting for answers…" : "No open ports found in this range.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(session.results.enumerated()), id: \.element.id) { index, result in
                            if index > 0 { Divider().opacity(0.5) }
                            PortResultRow(result: result, address: session.scannedAddress)
                        }
                    }
                }
            }
        } else if !device.openPorts.isEmpty {
            GlassCard("Seen During Discovery", systemImage: "eye") {
                FlowLayout(spacing: 8) {
                    ForEach(device.openPorts.sorted(), id: \.self) { PortChip(port: $0, address: device.primaryAddress) }
                }
            }
        }
    }
}

private struct PortResultRow: View {
    @Environment(AppModel.self) private var model
    let result: PortResult
    let address: IPAddress?

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: String(result.port))
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.service)
                    .font(.callout.weight(.medium))
                if let detail = result.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("tcp")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Text(String(format: "%.0f ms", result.latency * 1000))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            Pill(text: "open", tint: .green)
            if let address, let url = PortCatalog.url(for: result.port, address: address) {
                Button {
                    model.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open \(url.absoluteString)")
            } else {
                Color.clear.frame(width: 16)
            }
        }
        .padding(.vertical, 8)
    }
}
