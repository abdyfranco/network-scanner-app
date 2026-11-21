//
//  ContentView.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showsSettings = false
    @State private var isFullScreen = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            DeviceSidebar()
        } detail: {
            DetailContainer()
        }
        // In full screen the toolbar hides and the content would touch the top of the screen;
        // give it the same breathing room as the sidebar has on the other edges.
        .padding(.top, isFullScreen ? 10 : 0)
        .animation(.smooth(duration: 0.3), value: isFullScreen)
        .background { FullScreenReader(isFullScreen: $isFullScreen) }
        // Behind the whole window, not just the detail column: in full screen macOS lays the detail
        // column out below the toolbar, and the strip above it would show the plain window color.
        .background { AmbientBackground() }
        .navigationTitle("Network Scanner")
        .navigationSubtitle(model.subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isScanning {
                    // One control, like the App Store's download button: the ring shows progress, a click stops.
                    Button { model.stopScan() } label: {
                        ScanProgressRing(progress: model.progress)
                    }
                    .help(Text("Stop scanning — \(model.phase)"))
                    .accessibilityLabel(Text("Stop Scan"))
                    .accessibilityValue(Text(model.progress, format: .percent.precision(.fractionLength(0))))
                } else {
                    Button("Scan", systemImage: "arrow.clockwise") { model.startScan() }
                        .help("Scan \(model.targetText)")
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet()
                .environment(model)
        }
        .focusedSceneValue(\.showSettings) { showsSettings = true }
        .task { model.bootstrap() }
        .onChange(of: model.options) { _, options in options.save() }
        .onChange(of: model.selectedDeviceID) { _, id in
            if id != nil, model.detailTab == .scanner {
                model.detailTab = .overview
            }
        }
    }
}

struct DetailContainer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.detailTab {
            case .scanner:
                ScannerPane()
            case .overview:
                if let device = model.selectedDevice {
                    DeviceOverviewPane(device: device)
                } else {
                    NoSelectionView()
                }
            case .ports:
                if let device = model.selectedDevice {
                    PortScanPane(device: device)
                } else {
                    NoSelectionView()
                }
            case .wifi:
                WiFiPane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // safeAreaBar (not safeAreaInset) extends the scroll edge effect under the floating tab bar.
        .safeAreaBar(edge: .top, spacing: 0) {
            GlassTabBar(selection: $model.detailTab)
                .padding(.top, 6)
                .padding(.bottom, 6)
        }
    }
}

private struct NoSelectionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No Device Selected", systemImage: "sidebar.left")
        } description: {
            Text(model.devices.isEmpty ? "Scan your network, then pick a device from the sidebar." : "Pick a device from the sidebar to see its details.")
        } actions: {
            if model.devices.isEmpty {
                Button("Go to Scanner") { model.detailTab = .scanner }
                    .buttonStyle(.glass)
            }
        }
    }
}

/// Tracks whether the window holding this view is in full screen. It flips on the "will" notifications
/// so layout changes ride along with the system's full-screen animation.
private struct FullScreenReader: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> Probe { Probe(isFullScreen: $isFullScreen) }
    func updateNSView(_ probe: Probe, context: Context) { probe.isFullScreen = $isFullScreen }

    final class Probe: NSView {
        var isFullScreen: Binding<Bool>
        private var observers: [NSObjectProtocol] = []

        init(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            guard let window else { return }
            set(window.styleMask.contains(.fullScreen))
            let changes: [(Notification.Name, Bool)] = [
                (NSWindow.willEnterFullScreenNotification, true), (NSWindow.didEnterFullScreenNotification, true),
                (NSWindow.willExitFullScreenNotification, false), (NSWindow.didExitFullScreenNotification, false),
            ]
            for (name, value) in changes {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.set(value)
                })
            }
        }

        private func set(_ value: Bool) {
            if isFullScreen.wrappedValue != value { isFullScreen.wrappedValue = value }
        }
    }
}
