//
//  IconCanvas.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI

/// Shared helpers for the hand-drawn hardware icons (UniFi gear and generic devices).
/// Coordinates are fractions of a square canvas, light comes from above, and every enclosure
/// casts the same soft shadow.
struct IconCanvas {
    let context: GraphicsContext
    let origin: CGPoint
    let side: CGFloat

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * side, y: origin.y + y * side)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: origin.x + x * side, y: origin.y + y * side, width: w * side, height: h * side)
    }

    func roundedBox(_ r: CGRect, _ radius: CGFloat) -> Path {
        Path(roundedRect: r, cornerRadius: radius * side, style: .continuous)
    }

    func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        path.addLines(points.map { point($0.0, $0.1) })
        path.closeSubpath()
        return path
    }

    /// Vertical gradient across `r`, first colour at the top.
    func gradient(_ colors: [Color], over r: CGRect) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY))
    }

    /// A solid body with the common drop shadow. White plastic unless another finish is given.
    func enclosure(_ path: Path, _ shading: GraphicsContext.Shading? = nil) {
        let finish = shading ?? gradient(IconFinish.white, over: rect(0, 0, 1, 1))
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: side * 0.035, x: 0, y: side * 0.02))
            layer.fill(path, with: finish)
        }
    }

    /// Thin light edge that keeps dark hardware readable on the graphite tile.
    func rim(_ path: Path) {
        let bounds = path.boundingRect
        context.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0.06)]),
                                                   startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                                                   endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)),
                       lineWidth: max(0.5, side * 0.012))
    }

    func fill(_ r: CGRect, _ color: Color, radius: CGFloat = 0.008) {
        context.fill(Path(roundedRect: r, cornerRadius: radius * side), with: .color(color))
    }

    func fill(_ path: Path, _ shading: GraphicsContext.Shading) {
        context.fill(path, with: shading)
    }

    func dot(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat, _ color: Color) {
        context.fill(Path(ellipseIn: rect(x - d / 2, y - d / 2, d, d)), with: .color(color))
    }

    func line(_ from: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat), _ color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: point(from.0, from.1))
        path.addLine(to: point(to.0, to.1))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * side, lineCap: .round))
    }

    /// Arc around (x, y); angles in degrees, 0 pointing right and 90 pointing down.
    func arc(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, from start: Double, to end: Double, _ color: Color, width: CGFloat) {
        var path = Path()
        path.addArc(center: point(x, y), radius: radius * side, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * side, lineCap: .round))
    }

    func ports(x: CGFloat, y: CGFloat, columns: Int, rows: Int, w: CGFloat, h: CGFloat, gap: CGFloat, color: Color = Color(white: 0.2)) {
        for row in 0..<rows {
            for column in 0..<columns {
                fill(rect(x + CGFloat(column) * (w + gap), y + CGFloat(row) * (h + gap * 1.2), w, h), color)
            }
        }
    }

    /// Glossy display with a soft diagonal glare.
    func screen(_ r: CGRect, radius: CGFloat, colors: [Color] = IconFinish.screen) {
        let shape = Path(roundedRect: r, cornerRadius: radius * side, style: .continuous)
        context.fill(shape, with: gradient(colors, over: r))
        var glare = Path()
        glare.move(to: CGPoint(x: r.minX, y: r.minY))
        glare.addLine(to: CGPoint(x: r.minX + r.width * 0.62, y: r.minY))
        glare.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.6))
        glare.closeSubpath()
        context.drawLayer { layer in
            layer.clip(to: shape)
            layer.fill(glare, with: .color(.white.opacity(0.14)))
        }
    }

    /// Wi-Fi symbol: three arcs opening upwards from a dot at (x, y).
    func wifi(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, _ color: Color, width: CGFloat) {
        for i in 1...3 {
            arc(x, y, radius: radius * CGFloat(i) / 3, from: 225, to: 315, color, width: width)
        }
        dot(x, y, width * 1.6, color)
    }
}

/// Surface finishes for the hand-drawn hardware, light at the top.
enum IconFinish {
    static let white: [Color] = [Color(white: 1.0), Color(white: 0.80)]
    static let black: [Color] = [Color(white: 0.30), Color(white: 0.05)]
    static let charcoal: [Color] = [Color(white: 0.46), Color(white: 0.22)]
    static let silver: [Color] = [Color(white: 0.95), Color(white: 0.66)]
    static let screen: [Color] = [Color(red: 0.38, green: 0.66, blue: 0.99), Color(red: 0.10, green: 0.34, blue: 0.80)]
}
