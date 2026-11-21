//
//  GenericGlyph.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI

/// Hand-drawn hardware for the generic device kinds that macOS has no picture of,
/// in the same photo-like style as the system icons beside them.
struct GenericGlyph: View {
    let kind: DeviceKind

    private static let drawings: [DeviceKind: (IconCanvas) -> Void] = [
        .smartPlug: { $0.smartPlug() },
        .phone: { $0.phone() },
        .mobileDevice: { $0.phone() },
        .accessPoint: { $0.wifiExtender() },
        .mediaPlayer: { $0.mediaPlayer() },
        .smartHome: { $0.smartDisplay() },
        .smartLight: { $0.lightBulb() },
        .router: { $0.router() },
        .networkSwitch: { $0.networkSwitch() },
        .laptop: { $0.laptop() },
        .tablet: { $0.tablet() },
        .camera: { $0.securityCamera() },
        .gameConsole: { $0.gameController() },
        .thermostat: { $0.thermostat() },
        .vacuum: { $0.robotVacuum() },
        .singleBoardComputer: { $0.circuitBoard() },
        .watch: { $0.smartwatch() },
        .car: { $0.car() },
        .virtualMachine: { $0.virtualMachine() },
        .unknown: { $0.unknownDevice() },
    ]

    static func supports(_ kind: DeviceKind) -> Bool { drawings[kind] != nil }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            Self.drawings[kind]?(IconCanvas(context: context, origin: origin, side: side))
        }
    }
}

private extension IconCanvas {
    static let blueLED = Color(red: 0.25, green: 0.65, blue: 1.0)
    static let greenLED = Color(red: 0.30, green: 0.90, blue: 0.45)

    // White wall plug with a round socket and a lit power button.
    func smartPlug() {
        let body = rect(0.16, 0.10, 0.68, 0.80)
        enclosure(roundedBox(body, 0.17))
        let socket = rect(0.27, 0.20, 0.46, 0.46)
        fill(Path(ellipseIn: socket), gradient([Color(white: 0.78), Color(white: 0.97)], over: socket))
        context.stroke(Path(ellipseIn: socket), with: .color(Color(white: 0.68)), lineWidth: side * 0.008)
        dot(0.41, 0.43, 0.075, Color(white: 0.22))
        dot(0.59, 0.43, 0.075, Color(white: 0.22))
        fill(rect(0.47, 0.205, 0.06, 0.04), Color(white: 0.72), radius: 0.01)
        fill(rect(0.47, 0.615, 0.06, 0.04), Color(white: 0.72), radius: 0.01)
        let button = rect(0.43, 0.73, 0.14, 0.14)
        fill(Path(ellipseIn: button), gradient([Color(white: 0.99), Color(white: 0.84)], over: button))
        context.stroke(Path(ellipseIn: button), with: .color(Self.blueLED), lineWidth: side * 0.02)
    }

    // Black slab phone with a punch-hole camera.
    func phone() {
        fill(rect(0.715, 0.24, 0.02, 0.11), Color(white: 0.45), radius: 0.006)
        let body = rect(0.28, 0.06, 0.44, 0.88)
        enclosure(roundedBox(body, 0.08), gradient(IconFinish.black, over: body))
        rim(roundedBox(body, 0.08))
        screen(rect(0.30, 0.08, 0.40, 0.84), radius: 0.065,
               colors: [Color(red: 0.32, green: 0.88, blue: 0.62), Color(red: 0.04, green: 0.42, blue: 0.52)])
        dot(0.50, 0.12, 0.03, Color(white: 0.04))
    }

    // Wall-plug Wi-Fi extender with two antennas.
    func wifiExtender() {
        for x in [0.29, 0.65] {
            let antenna = rect(x, 0.06, 0.06, 0.42)
            enclosure(roundedBox(antenna, 0.03), gradient(IconFinish.white, over: antenna))
        }
        let body = rect(0.20, 0.30, 0.60, 0.62)
        enclosure(roundedBox(body, 0.11))
        wifi(0.50, 0.78, radius: 0.26, Self.blueLED, width: 0.05)
    }

    // HDMI streaming stick and its remote.
    func mediaPlayer() {
        let stick = rect(0.06, 0.16, 0.64, 0.24)
        enclosure(roundedBox(stick, 0.08), gradient(IconFinish.black, over: stick))
        rim(roundedBox(stick, 0.08))
        let plug = rect(0.70, 0.215, 0.20, 0.13)
        fill(roundedBox(plug, 0.015), gradient(IconFinish.silver, over: plug))
        fill(rect(0.75, 0.25, 0.12, 0.06), Color(white: 0.25), radius: 0.008)
        dot(0.16, 0.28, 0.04, .white)
        let remote = rect(0.40, 0.46, 0.24, 0.48)
        enclosure(roundedBox(remote, 0.12))
        let pad = rect(0.445, 0.51, 0.15, 0.15)
        context.stroke(Path(ellipseIn: pad), with: .color(Color(white: 0.35)), lineWidth: side * 0.025)
        dot(0.52, 0.585, 0.05, Color(white: 0.55))
        dot(0.52, 0.74, 0.05, Color(white: 0.35))
        dot(0.52, 0.84, 0.05, Color(white: 0.35))
    }

    // Smart display: screen showing a home, on a fabric speaker base.
    func smartDisplay() {
        let base = rect(0.24, 0.56, 0.52, 0.32)
        enclosure(roundedBox(base, 0.12), gradient([Color(white: 0.86), Color(white: 0.64)], over: base))
        let panel = rect(0.08, 0.12, 0.84, 0.58)
        enclosure(roundedBox(panel, 0.06))
        screen(rect(0.125, 0.165, 0.75, 0.49), radius: 0.03,
               colors: [Color(red: 1.0, green: 0.74, blue: 0.38), Color(red: 0.93, green: 0.40, blue: 0.18)])
        let house = polygon([(0.50, 0.24), (0.66, 0.38), (0.61, 0.38), (0.61, 0.57), (0.39, 0.57), (0.39, 0.38), (0.34, 0.38)])
        context.fill(house, with: .color(.white.opacity(0.95)))
        fill(rect(0.465, 0.46, 0.07, 0.11), Color(red: 0.96, green: 0.56, blue: 0.26), radius: 0.012)
    }

    // Glowing A-shaped bulb on a screw base.
    func lightBulb() {
        let glass = rect(0.20, 0.05, 0.60, 0.60)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: Color(red: 1.0, green: 0.78, blue: 0.25).opacity(0.8), radius: side * 0.09))
            layer.fill(Path(ellipseIn: glass),
                       with: .radialGradient(Gradient(colors: [Color(red: 1.0, green: 0.99, blue: 0.88), Color(red: 1.0, green: 0.80, blue: 0.36)]),
                                             center: point(0.43, 0.28), startRadius: 0, endRadius: side * 0.38))
        }
        let neck = polygon([(0.31, 0.56), (0.69, 0.56), (0.62, 0.72), (0.38, 0.72)])
        fill(neck, gradient(IconFinish.white, over: rect(0.31, 0.56, 0.38, 0.16)))
        for i in 0..<4 {
            let thread = rect(0.385, 0.715 + CGFloat(i) * 0.042, 0.23, 0.038)
            fill(roundedBox(thread, 0.015), gradient(IconFinish.silver, over: thread))
        }
        fill(roundedBox(rect(0.44, 0.88, 0.12, 0.06), 0.025), .color(Color(white: 0.22)))
    }

    // Black router with three antennas and a row of status lights.
    func router() {
        for x in [0.16, 0.47, 0.78] {
            let antenna = rect(x, 0.10, 0.06, 0.50)
            enclosure(roundedBox(antenna, 0.03), gradient(IconFinish.black, over: antenna))
            rim(roundedBox(antenna, 0.03))
        }
        let body = rect(0.05, 0.50, 0.90, 0.28)
        enclosure(roundedBox(body, 0.07), gradient(IconFinish.black, over: body))
        rim(roundedBox(body, 0.07))
        for i in 0..<5 {
            dot(0.24 + CGFloat(i) * 0.13, 0.64, 0.045, i == 0 ? .white : Self.blueLED)
        }
    }

    // Brushed-metal switch with eight ports and link lights.
    func networkSwitch() {
        let body = rect(0.03, 0.32, 0.94, 0.36)
        enclosure(roundedBox(body, 0.045), gradient([Color(white: 0.86), Color(white: 0.56)], over: body))
        for i in 0..<8 {
            let x = 0.09 + CGFloat(i) * 0.105
            dot(x + 0.04, 0.41, 0.026, i % 3 == 2 ? .orange : Self.greenLED)
            fill(rect(x, 0.46, 0.08, 0.13), Color(white: 0.06), radius: 0.01)
            fill(rect(x + 0.015, 0.47, 0.05, 0.025), Color(red: 0.85, green: 0.72, blue: 0.35))
        }
    }

    // Black laptop with a violet wallpaper.
    func laptop() {
        let lid = rect(0.13, 0.13, 0.74, 0.52)
        enclosure(roundedBox(lid, 0.04), gradient(IconFinish.black, over: lid))
        rim(roundedBox(lid, 0.04))
        screen(rect(0.16, 0.16, 0.68, 0.46), radius: 0.012,
               colors: [Color(red: 0.55, green: 0.50, blue: 1.0), Color(red: 0.22, green: 0.16, blue: 0.62)])
        let base = polygon([(0.06, 0.66), (0.94, 0.66), (0.99, 0.76), (0.01, 0.76)])
        enclosure(base, gradient([Color(white: 0.66), Color(white: 0.36)], over: rect(0.01, 0.66, 0.98, 0.10)))
        fill(rect(0.42, 0.66, 0.16, 0.022), Color(white: 0.3), radius: 0.01)
    }

    // Landscape tablet with a teal wallpaper.
    func tablet() {
        let body = rect(0.05, 0.18, 0.90, 0.64)
        enclosure(roundedBox(body, 0.07), gradient(IconFinish.black, over: body))
        rim(roundedBox(body, 0.07))
        screen(rect(0.10, 0.23, 0.80, 0.54), radius: 0.03,
               colors: [Color(red: 0.36, green: 0.86, blue: 0.90), Color(red: 0.06, green: 0.45, blue: 0.62)])
        dot(0.075, 0.50, 0.02, Color(white: 0.3))
    }

    // White indoor camera on a stand.
    func securityCamera() {
        enclosure(Path(ellipseIn: rect(0.27, 0.79, 0.46, 0.13)))
        fill(Path(rect(0.45, 0.60, 0.10, 0.24)), gradient([Color(white: 0.92), Color(white: 0.74)], over: rect(0.45, 0.60, 0.10, 0.24)))
        let head = rect(0.15, 0.07, 0.70, 0.58)
        enclosure(roundedBox(head, 0.16))
        let face = rect(0.22, 0.14, 0.56, 0.44)
        fill(roundedBox(face, 0.11), gradient(IconFinish.black, over: face))
        let lens = rect(0.375, 0.225, 0.25, 0.25)
        fill(Path(ellipseIn: lens), gradient([Color(red: 0.22, green: 0.27, blue: 0.45), Color(red: 0.02, green: 0.03, blue: 0.08)], over: lens))
        context.stroke(Path(ellipseIn: lens), with: .color(Color(white: 0.38)), lineWidth: side * 0.014)
        dot(0.455, 0.305, 0.055, .white.opacity(0.75))
        dot(0.69, 0.22, 0.032, Self.greenLED)
    }

    // White gamepad with coloured face buttons.
    func gameController() {
        var shell = roundedBox(rect(0.07, 0.26, 0.86, 0.34), 0.15)
        shell.addPath(Path(ellipseIn: rect(0.07, 0.36, 0.30, 0.46)))
        shell.addPath(Path(ellipseIn: rect(0.63, 0.36, 0.30, 0.46)))
        enclosure(shell)
        fill(rect(0.17, 0.395, 0.14, 0.045), Color(white: 0.3), radius: 0.01)
        fill(rect(0.2175, 0.345, 0.045, 0.145), Color(white: 0.3), radius: 0.01)
        dot(0.76, 0.35, 0.055, Color(red: 0.25, green: 0.80, blue: 0.40))
        dot(0.82, 0.415, 0.055, Color(red: 0.95, green: 0.30, blue: 0.30))
        dot(0.70, 0.415, 0.055, Color(red: 0.25, green: 0.55, blue: 1.0))
        dot(0.76, 0.48, 0.055, Color(red: 1.0, green: 0.80, blue: 0.20))
        for x in [0.38, 0.62] {
            let stick = rect(x - 0.065, 0.47, 0.13, 0.13)
            fill(Path(ellipseIn: stick), gradient([Color(white: 0.38), Color(white: 0.10)], over: stick))
        }
    }

    // Round thermostat: steel ring, black glass, orange heating arc.
    func thermostat() {
        let ring = rect(0.10, 0.10, 0.80, 0.80)
        enclosure(Path(ellipseIn: ring), gradient(IconFinish.silver, over: ring))
        let glass = rect(0.19, 0.19, 0.62, 0.62)
        fill(Path(ellipseIn: glass), gradient([Color(white: 0.18), Color(white: 0.02)], over: glass))
        arc(0.5, 0.5, radius: 0.245, from: 135, to: 405, Color(white: 0.3), width: 0.03)
        arc(0.5, 0.5, radius: 0.245, from: 135, to: 300, Color(red: 1.0, green: 0.55, blue: 0.15), width: 0.04)
        context.draw(Text(verbatim: "21°").font(.system(size: side * 0.19, weight: .semibold, design: .rounded)).foregroundColor(.white),
                     at: point(0.515, 0.5))
    }

    // White robot vacuum seen from above at an angle, with a lidar turret.
    func robotVacuum() {
        let top = rect(0.06, 0.24, 0.88, 0.46)
        var body = Path(ellipseIn: rect(0.06, 0.34, 0.88, 0.46))
        body.addRect(rect(0.06, 0.47, 0.88, 0.10))
        body.addPath(Path(ellipseIn: top))
        enclosure(body, gradient([Color(white: 0.70), Color(white: 0.30)], over: rect(0.06, 0.24, 0.88, 0.56)))
        fill(Path(ellipseIn: top), gradient(IconFinish.white, over: top))
        let turret = rect(0.37, 0.27, 0.26, 0.15)
        fill(Path(ellipseIn: turret.offsetBy(dx: 0, dy: side * 0.04)), .color(Color(white: 0.08)))
        fill(Path(ellipseIn: turret), gradient([Color(white: 0.40), Color(white: 0.14)], over: turret))
        let button = rect(0.45, 0.53, 0.10, 0.06)
        fill(Path(ellipseIn: button), .color(Color(white: 0.86)))
        context.stroke(Path(ellipseIn: button), with: .color(Self.blueLED), lineWidth: side * 0.012)
    }

    // Green single-board computer with GPIO header, chips and ports.
    func circuitBoard() {
        let board = rect(0.05, 0.20, 0.86, 0.60)
        enclosure(roundedBox(board, 0.04), gradient([Color(red: 0.18, green: 0.64, blue: 0.32), Color(red: 0.05, green: 0.38, blue: 0.17)], over: board))
        let gold = Color(red: 0.90, green: 0.76, blue: 0.40)
        for (x, y) in [(0.10, 0.25), (0.10, 0.75), (0.62, 0.25), (0.62, 0.75)] {
            dot(x, y, 0.05, gold)
            dot(x, y, 0.024, Color(white: 0.12))
        }
        fill(rect(0.16, 0.225, 0.42, 0.06), Color(white: 0.10), radius: 0.006)
        for i in 0..<10 {
            dot(0.18 + CGFloat(i) * 0.04, 0.24, 0.016, gold)
            dot(0.18 + CGFloat(i) * 0.04, 0.268, 0.016, gold)
        }
        let chip = rect(0.20, 0.40, 0.22, 0.22)
        fill(roundedBox(chip, 0.015), gradient(IconFinish.silver, over: chip))
        fill(rect(0.47, 0.42, 0.12, 0.18), Color(white: 0.10), radius: 0.008)
        let ethernet = rect(0.70, 0.30, 0.26, 0.20)
        fill(roundedBox(ethernet, 0.01), gradient(IconFinish.silver, over: ethernet))
        fill(rect(0.75, 0.355, 0.16, 0.10), Color(white: 0.15), radius: 0.006)
        let usb = rect(0.72, 0.56, 0.24, 0.16)
        fill(roundedBox(usb, 0.01), gradient(IconFinish.silver, over: usb))
        fill(rect(0.76, 0.60, 0.16, 0.035), Color(red: 0.15, green: 0.35, blue: 0.85))
        fill(rect(0.76, 0.655, 0.16, 0.035), Color(red: 0.15, green: 0.35, blue: 0.85))
    }

    // Round smartwatch on a mint strap.
    func smartwatch() {
        let strap = rect(0.34, 0.03, 0.32, 0.94)
        enclosure(roundedBox(strap, 0.07), gradient([Color(red: 0.50, green: 0.84, blue: 0.74), Color(red: 0.24, green: 0.56, blue: 0.48)], over: strap))
        fill(rect(0.765, 0.44, 0.06, 0.12), Color(white: 0.62), radius: 0.02)
        let watchCase = rect(0.21, 0.21, 0.58, 0.58)
        enclosure(Path(ellipseIn: watchCase), gradient(IconFinish.silver, over: watchCase))
        let face = rect(0.26, 0.26, 0.48, 0.48)
        fill(Path(ellipseIn: face), gradient([Color(white: 0.16), Color(white: 0.02)], over: face))
        arc(0.5, 0.5, radius: 0.19, from: -90, to: 160, Color(red: 0.35, green: 0.90, blue: 0.75), width: 0.03)
        line((0.5, 0.5), (0.5, 0.37), .white, width: 0.028)
        line((0.5, 0.5), (0.6, 0.55), .white, width: 0.022)
        dot(0.5, 0.5, 0.04, .white)
    }

    // Red car seen from the front.
    func car() {
        fill(rect(0.13, 0.64, 0.17, 0.22), Color(white: 0.08), radius: 0.04)
        fill(rect(0.70, 0.64, 0.17, 0.22), Color(white: 0.08), radius: 0.04)
        let paint = [Color(red: 0.98, green: 0.36, blue: 0.32), Color(red: 0.62, green: 0.07, blue: 0.10)]
        var shell = polygon([(0.25, 0.16), (0.75, 0.16), (0.86, 0.46), (0.14, 0.46)])
        shell.addPath(roundedBox(rect(0.06, 0.42, 0.88, 0.30), 0.09))
        shell.addPath(roundedBox(rect(0.03, 0.39, 0.10, 0.06), 0.02))
        shell.addPath(roundedBox(rect(0.87, 0.39, 0.10, 0.06), 0.02))
        enclosure(shell, gradient(paint, over: rect(0.03, 0.16, 0.94, 0.56)))
        let windshield = polygon([(0.29, 0.21), (0.71, 0.21), (0.80, 0.44), (0.20, 0.44)])
        fill(windshield, gradient([Color(red: 0.62, green: 0.78, blue: 0.95), Color(red: 0.14, green: 0.22, blue: 0.36)], over: rect(0.20, 0.21, 0.60, 0.23)))
        fill(Path(ellipseIn: rect(0.11, 0.50, 0.18, 0.10)), .color(Color(white: 0.98)))
        fill(Path(ellipseIn: rect(0.71, 0.50, 0.18, 0.10)), .color(Color(white: 0.98)))
        fill(rect(0.35, 0.52, 0.30, 0.09), Color(white: 0.10), radius: 0.025)
        fill(rect(0.41, 0.645, 0.18, 0.05), Color(white: 0.94), radius: 0.008)
    }

    // Three stacked glass layers: machines running on one host.
    func virtualMachine() {
        let tops: [[Color]] = [
            [Color(red: 0.40, green: 0.36, blue: 0.86), Color(red: 0.26, green: 0.20, blue: 0.66)],
            [Color(red: 0.52, green: 0.50, blue: 0.96), Color(red: 0.34, green: 0.30, blue: 0.80)],
            [Color(red: 0.70, green: 0.70, blue: 1.00), Color(red: 0.46, green: 0.44, blue: 0.94)],
        ]
        for (i, y) in [0.66, 0.50, 0.34].enumerated() {
            let y = CGFloat(y)
            let edge = polygon([(0.08, y), (0.50, y + 0.17), (0.92, y), (0.92, y + 0.06), (0.50, y + 0.23), (0.08, y + 0.06)])
            enclosure(edge, .color(Color(red: 0.16, green: 0.12, blue: 0.42)))
            let top = polygon([(0.50, y - 0.17), (0.92, y), (0.50, y + 0.17), (0.08, y)])
            fill(top, gradient(tops[i], over: rect(0.08, y - 0.17, 0.84, 0.34)))
            context.stroke(top, with: .color(.white.opacity(0.35)), lineWidth: max(0.5, side * 0.01))
        }
    }

    // Plain grey box with a question mark.
    func unknownDevice() {
        let body = rect(0.12, 0.18, 0.76, 0.64)
        enclosure(roundedBox(body, 0.09), gradient([Color(white: 0.68), Color(white: 0.42)], over: body))
        rim(roundedBox(body, 0.09))
        context.draw(Text(verbatim: "?").font(.system(size: side * 0.42, weight: .bold, design: .rounded)).foregroundColor(.white),
                     at: point(0.5, 0.47))
        fill(rect(0.66, 0.68, 0.14, 0.08), Color(white: 0.15), radius: 0.008)
        dot(0.22, 0.72, 0.035, Self.greenLED)
    }
}
