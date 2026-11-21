//
//  SettingsView.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI

/// Settings as a sheet on the window (Network Scanner › Settings…, ⌘,).
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
            SettingsView()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onExitCommand { dismiss() }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Vendor Database") {
                LabeledContent("Prefixes", value: model.vendorStatus.entries.formatted())
                LabeledContent("Source", value: model.vendorStatus.source)
                if let modified = model.vendorStatus.modified {
                    LabeledContent("Updated", value: modified.formatted(date: .abbreviated, time: .omitted))
                }
                HStack {
                    Button {
                        model.updateVendorDatabase()
                    } label: {
                        Label("Download Latest from IEEE", systemImage: "arrow.down.circle")
                    }
                    .disabled(model.isUpdatingVendors)
                    if model.isUpdatingVendors { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Use Built-in") { model.resetVendorDatabase() }
                        .disabled(model.isUpdatingVendors)
                }
                if let message = model.vendorUpdateMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Scanning Defaults") {
                LabeledContent("Probe timeout") {
                    HStack {
                        Slider(value: $model.options.timeoutMilliseconds, in: 200...3000, step: 100)
                        Text("\(Int(model.options.timeoutMilliseconds)) ms")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                Picker("Parallel probes", selection: $model.options.parallelProbes) {
                    ForEach([64, 128, 256, 512], id: \.self) { Text($0, format: .number).tag($0) }
                }
                Button("Restore Default Options") { model.options = ScanOptions() }
            }

            Section {
                Text("Network Scanner sends ICMP, TCP, UDP and multicast DNS probes only to the addresses you choose. Scan networks you own or are authorized to test.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
