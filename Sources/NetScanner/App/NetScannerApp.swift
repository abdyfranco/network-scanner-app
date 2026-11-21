//
//  NetScannerApp.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI
import AppKit

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
            let target = args.indices.contains(index + 2) && !args[index + 2].hasPrefix("--") ? args[index + 2] : nil
            MainActor.assumeIsolated { SnapshotRenderer.run(directory: args[index + 1], target: target) }
        } else if let index = args.firstIndex(of: "--ports"), args.indices.contains(index + 1) {
            let spec = args.indices.contains(index + 2) ? args[index + 2] : nil
            MainActor.assumeIsolated { CommandLinePortScan.run(address: args[index + 1], spec: spec) }
        } else if args.contains("--wifi") {
            MainActor.assumeIsolated { CommandLineWiFi.run() }
        } else if let index = args.firstIndex(of: "--scan") {
            let target = args.indices.contains(index + 1) ? args[index + 1] : nil
            MainActor.assumeIsolated { CommandLineScan.run(target: target) }
        } else {
            NetScannerApp.main()
        }
    }
}

struct NetScannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel = {
        let model = AppModel()
        if SampleNetwork.isRequested { SampleNetwork.load(into: model) }
        return model
    }()

    var body: some Scene {
        WindowGroup("Network Scanner", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                // In full screen macOS draws the toolbar on a solid grey bar of its own, which no SwiftUI
                // toolbar-background setting reaches. Let it slide in with the menu bar instead, so the app
                // fills the screen. Scanning stays in the Scanner pane, the sidebar and ⌘R.
                .windowToolbarFullScreenVisibility(.onHover)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            ScanCommands(model: model)
            SettingsCommands()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SystemLimits.raiseFileDescriptorLimit()
        if SampleNetwork.isRequested { SampleNetwork.prepareWindow() }
        // Checks GitHub for a newer version. Not for demo runs or `swift run`, which can't update in place.
        if !SampleNetwork.isRequested, Bundle.main.bundleIdentifier != nil { Updater.shared.start() }
        // When launched as a bare executable (`swift run`), become a regular foreground app.
        if Bundle.main.bundleIdentifier == nil {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Network Scanner › Check for Updates…, and Settings… (⌘,), which opens Settings as a sheet on the front window.
struct SettingsCommands: Commands {
    @FocusedValue(\.showSettings) private var showSettings

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updater.shared.check(userInitiated: true) }
                .disabled(Bundle.main.bundleIdentifier == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { showSettings?() }
                .keyboardShortcut(",")
                .disabled(showSettings == nil)
        }
    }
}

extension FocusedValues {
    /// Presents Settings on the focused window.
    @Entry var showSettings: (() -> Void)?
}

struct ScanCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Scan") {
            Button("Scan Network") { model.startScan() }
                .keyboardShortcut("r")
                .disabled(model.isScanning)
            Button("Stop Scan") { model.stopScan() }
                .keyboardShortcut(".")
                .disabled(!model.isScanning)
            Divider()
            Button("Show Scanner") { model.detailTab = .scanner }
                .keyboardShortcut("1")
            Button("Show Device Overview") { model.detailTab = .overview }
                .keyboardShortcut("2")
                .disabled(model.selectedDevice == nil)
            Button("Port Scan Selected Device") { model.detailTab = .ports }
                .keyboardShortcut("3")
                .disabled(model.selectedDevice == nil)
            Button("Show Wi-Fi Networks") { model.detailTab = .wifi }
                .keyboardShortcut("4")
            Divider()
            Button("Clear Device List") { model.clearDevices() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.isScanning || model.devices.isEmpty)
        }
    }
}
