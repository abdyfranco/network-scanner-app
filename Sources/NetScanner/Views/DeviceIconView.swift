//
//  DeviceIconView.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI

/// Device artwork, always on a rounded square: macOS's own pictures where the system has one,
/// hand-drawn hardware for UniFi gear and the other generic kinds, and an SF Symbol as the last resort.
struct DeviceIconView: View {
    let kind: DeviceKind
    /// Apple model code ("Macmini9,1"), when known, for the exact product picture.
    var model: String? = nil
    var size: CGFloat = 36
    var isOnline = true

    var body: some View {
        Group {
            if let image = SystemDeviceIcon.image(for: kind, model: model) {
                // System artwork sits on the graphite square too, so every row has the same shape.
                tile {
                    systemImage(image)
                        .padding(size * 0.1)
                }
            } else if kind == .appleDevice,
                      let laptop = SystemDeviceIcon.image(for: .macLaptop),
                      let phone = SystemDeviceIcon.image(for: .iPhone) {
                // No single product to show for an unidentified Apple device, so a Mac and an iPhone together.
                tile {
                    ZStack {
                        systemImage(laptop)
                            .frame(width: size * 0.7, height: size * 0.7)
                            .offset(x: -size * 0.06, y: -size * 0.04)
                        systemImage(phone)
                            .frame(width: size * 0.4, height: size * 0.4)
                            .offset(x: size * 0.22, y: size * 0.14)
                    }
                }
            } else {
                tile { glyph }
            }
        }
        .frame(width: size, height: size)
        .saturation(isOnline ? 1 : 0.15)
        .opacity(isOnline ? 1 : 0.6)
        .accessibilityLabel(kind.title)
    }

    private func systemImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }

    private func tile(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(background)
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: max(0.5, size / 80))
            content()
        }
    }

    @ViewBuilder
    private var glyph: some View {
        Group {
            if let style = kind.unifiStyle {
                UniFiGlyph(style: style)
                    .padding(size * 0.1)
            } else if GenericGlyph.supports(kind) {
                GenericGlyph(kind: kind)
                    .padding(size * 0.1)
            } else if kind.family == .other {
                // Neutral graphite tile like the Apple ones, category colour in the glyph.
                Image(systemName: kind.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(kind.tint.gradient)
                    .shadow(color: .black.opacity(0.35), radius: size * 0.025, y: size * 0.015)
            } else {
                Image(systemName: kind.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: size * 0.46, weight: .regular))
                    .foregroundStyle(Color(white: 0.96))
            }
        }
    }

    private var background: LinearGradient {
        switch kind.family {
        case .apple:
            return LinearGradient(colors: [Color(white: 0.34), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
        case .ubiquiti:
            return LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.33), Color(red: 0.06, green: 0.09, blue: 0.16)],
                                  startPoint: .top, endPoint: .bottom)
        case .other:
            return LinearGradient(colors: [Color(white: 0.30), Color(white: 0.13)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Vector drawings of generic UniFi-style hardware silhouettes (white enclosures, dark ports, blue status LEDs).
struct UniFiGlyph: View {
    let style: UniFiGlyphStyle

    static let led = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let port = Color(white: 0.2)

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let draw = IconCanvas(context: context, origin: origin, side: side)
            switch style {
            case .rackGateway: draw.rackGateway()
            case .console: draw.console()
            case .compactGateway: draw.compactGateway()
            case .deskSwitch: draw.deskSwitch()
            case .rackSwitch: draw.rackSwitch()
            case .miniSwitch: draw.miniSwitch()
            case .accessPoint: draw.accessPoint()
            case .wallAccessPoint: draw.wallAccessPoint()
            case .camera: draw.camera()
            case .doorbell: draw.doorbell()
            case .nvr: draw.nvr()
            case .cloudKey: draw.cloudKey()
            case .generic: draw.generic()
            }
        }
    }
}

/// UniFi hardware silhouettes, drawn with the shared icon helpers.
extension IconCanvas {
    // 1U rack gateway: display, two rows of ports, SFP cages.
    func rackGateway() {
        enclosure(roundedBox(rect(0.03, 0.35, 0.94, 0.30), 0.035))
        fill(rect(0.08, 0.41, 0.17, 0.18), Color(white: 0.1), radius: 0.02)
        dot(0.165, 0.50, 0.05, UniFiGlyph.led)
        ports(x: 0.30, y: 0.415, columns: 6, rows: 2, w: 0.055, h: 0.07, gap: 0.018)
        fill(rect(0.78, 0.42, 0.07, 0.16), Color(white: 0.35))
        fill(rect(0.87, 0.42, 0.07, 0.16), Color(white: 0.35))
    }

    // Tall cylindrical console with a light ring.
    func console() {
        enclosure(roundedBox(rect(0.30, 0.08, 0.40, 0.84), 0.16))
        context.fill(Path(ellipseIn: rect(0.33, 0.10, 0.34, 0.12)), with: .color(Color(white: 0.88)))
        fill(rect(0.42, 0.30, 0.16, 0.05), Color(white: 0.15), radius: 0.02)
        fill(rect(0.36, 0.80, 0.28, 0.03), UniFiGlyph.led, radius: 0.015)
    }

    // Small desktop gateway with a front display.
    func compactGateway() {
        enclosure(roundedBox(rect(0.16, 0.30, 0.68, 0.40), 0.07))
        fill(rect(0.22, 0.38, 0.22, 0.20), Color(white: 0.1), radius: 0.025)
        dot(0.33, 0.48, 0.05, UniFiGlyph.led)
        ports(x: 0.50, y: 0.44, columns: 3, rows: 1, w: 0.07, h: 0.10, gap: 0.02)
    }

    // Desktop switch: one row of ports and a status LED.
    func deskSwitch() {
        enclosure(roundedBox(rect(0.05, 0.36, 0.90, 0.28), 0.045))
        dot(0.12, 0.50, 0.05, UniFiGlyph.led)
        ports(x: 0.20, y: 0.445, columns: 7, rows: 1, w: 0.07, h: 0.11, gap: 0.03)
    }

    // Rack switch: dense port grid.
    func rackSwitch() {
        enclosure(roundedBox(rect(0.03, 0.34, 0.94, 0.32), 0.035))
        dot(0.08, 0.50, 0.045, UniFiGlyph.led)
        ports(x: 0.13, y: 0.405, columns: 10, rows: 2, w: 0.052, h: 0.075, gap: 0.016)
        fill(rect(0.83, 0.415, 0.05, 0.17), Color(white: 0.35))
        fill(rect(0.89, 0.415, 0.05, 0.17), Color(white: 0.35))
    }

    // Palm-sized switch.
    func miniSwitch() {
        enclosure(roundedBox(rect(0.20, 0.28, 0.60, 0.44), 0.07))
        dot(0.28, 0.37, 0.05, UniFiGlyph.led)
        ports(x: 0.27, y: 0.52, columns: 4, rows: 1, w: 0.085, h: 0.11, gap: 0.03)
    }

    // Ceiling access point: white disc with a light ring.
    func accessPoint() {
        enclosure(Path(ellipseIn: rect(0.10, 0.10, 0.80, 0.80)))
        context.stroke(Path(ellipseIn: rect(0.22, 0.22, 0.56, 0.56)), with: .color(Color(white: 0.84)), lineWidth: side * 0.012)
        context.stroke(Path(ellipseIn: rect(0.38, 0.38, 0.24, 0.24)), with: .color(UniFiGlyph.led), lineWidth: side * 0.045)
    }

    // In-wall access point.
    func wallAccessPoint() {
        enclosure(roundedBox(rect(0.30, 0.10, 0.40, 0.80), 0.06))
        fill(rect(0.40, 0.18, 0.20, 0.025), UniFiGlyph.led, radius: 0.012)
        ports(x: 0.40, y: 0.70, columns: 2, rows: 1, w: 0.08, h: 0.09, gap: 0.04)
    }

    // Dome camera.
    func camera() {
        enclosure(Path(ellipseIn: rect(0.14, 0.14, 0.72, 0.72)))
        context.fill(Path(ellipseIn: rect(0.30, 0.30, 0.40, 0.40)), with: .color(Color(white: 0.08)))
        context.fill(Path(ellipseIn: rect(0.40, 0.40, 0.20, 0.20)), with: .color(Color(red: 0.12, green: 0.16, blue: 0.28)))
        dot(0.455, 0.455, 0.06, .white.opacity(0.75))
        dot(0.70, 0.30, 0.04, UniFiGlyph.led)
    }

    // Video doorbell.
    func doorbell() {
        enclosure(roundedBox(rect(0.33, 0.06, 0.34, 0.88), 0.12))
        fill(rect(0.37, 0.12, 0.26, 0.32), Color(white: 0.1), radius: 0.08)
        dot(0.50, 0.28, 0.12, Color(red: 0.12, green: 0.16, blue: 0.28))
        context.stroke(Path(ellipseIn: rect(0.41, 0.62, 0.18, 0.18)), with: .color(UniFiGlyph.led), lineWidth: side * 0.03)
    }

    // Network video recorder: drive bays.
    func nvr() {
        enclosure(roundedBox(rect(0.03, 0.33, 0.94, 0.34), 0.035))
        fill(rect(0.08, 0.40, 0.15, 0.20), Color(white: 0.1), radius: 0.02)
        dot(0.155, 0.50, 0.045, UniFiGlyph.led)
        for i in 0..<4 {
            fill(rect(0.30 + CGFloat(i) * 0.165, 0.39, 0.14, 0.22), Color(white: 0.72), radius: 0.015)
            fill(rect(0.32 + CGFloat(i) * 0.165, 0.555, 0.10, 0.02), Color(white: 0.45))
        }
    }

    // Cloud Key.
    func cloudKey() {
        enclosure(roundedBox(rect(0.18, 0.36, 0.64, 0.28), 0.06))
        fill(rect(0.24, 0.42, 0.20, 0.12), Color(white: 0.1), radius: 0.02)
        fill(rect(0.52, 0.585, 0.24, 0.025), UniFiGlyph.led, radius: 0.012)
    }

    func generic() {
        enclosure(roundedBox(rect(0.20, 0.20, 0.60, 0.60), 0.12))
        context.stroke(Path(ellipseIn: rect(0.37, 0.37, 0.26, 0.26)), with: .color(UniFiGlyph.led), lineWidth: side * 0.045)
    }
}
