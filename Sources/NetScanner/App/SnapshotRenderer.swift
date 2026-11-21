//
//  SnapshotRenderer.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import AppKit
import SwiftUI

/// Developer aid: `NetScanner --snapshot <dir> [target]` scans, then renders the device icon set and
/// sidebar rows to PNG files with ImageRenderer (pure SwiftUI, no window needed).
@MainActor
enum SnapshotRenderer {
    static func run(directory: String, target: String?) {
        _ = NSApplication.shared
        SystemLimits.raiseFileDescriptorLimit()
        OUIDatabase.shared.loadPreferred()

        let model = AppModel()
        model.refreshInterfaces()
        if let first = model.interfaces.first(where: { $0.primaryIPv4 != nil }) { model.selectInterface(first.name) }
        if let target { model.targetText = target }
        model.startScan()
        while model.isScanning { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }

        let dark = !CommandLine.arguments.contains("--light")
        let background = dark ? Color(red: 0.11, green: 0.11, blue: 0.13) : Color(white: 0.96)

        let icons = VStack(alignment: .leading, spacing: 18) {
            ForEach(DeviceFamily.allCases, id: \.self) { family in
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 10), count: 9), alignment: .leading, spacing: 14) {
                    ForEach(DeviceKind.allCases.filter { $0.family == family }, id: \.self) { kind in
                        VStack(spacing: 6) {
                            HStack(alignment: .bottom, spacing: 6) {
                                DeviceIconView(kind: kind, size: 64)
                                DeviceIconView(kind: kind, size: 24)
                            }
                            Text(kind.title).font(.caption2).multilineTextAlignment(.center).lineLimit(2)
                        }
                        .frame(width: 96)
                    }
                }
            }
        }
        .padding(24)
        .background(background)
        .environment(\.colorScheme, dark ? .dark : .light)
        write(icons, name: "icons", directory: directory)

        let rows = VStack(alignment: .leading, spacing: 4) {
            ForEach(model.visibleDevices) { device in
                DeviceRow(device: device).padding(.horizontal, 12)
            }
        }
        .frame(width: 390)
        .padding(.vertical, 10)
        .background(background)
        .tint(.blue)
        .environment(\.colorScheme, dark ? .dark : .light)
        write(rows, name: "rows", directory: directory)
        exit(0)
    }

    private static func write(_ view: some View, name: String, directory: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}
