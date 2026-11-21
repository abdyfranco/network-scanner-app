//
//  icon-layers.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

// Generates the vector layers of Resources/AppIcon.icon (Icon Composer).
//   swift Scripts/icon-layers.swift Resources/AppIcon.icon/Assets
//
// Shapes are drawn on Icon Composer's 1024×1024 canvas (SVG space: origin top left, y down).
// Strokes are converted to filled outlines so the glass renderer gets clean, solid shapes.
// Everything is drawn by hand: SF Symbols may not be used in app icons.
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// MARK: Geometry

/// The radar screen: a disc in the middle of the canvas, with two range rings on it.
let center = CGPoint(x: 512, y: 512)
let screenRadius: CGFloat = 356
let ringRadii: [CGFloat] = [244, 128]
let ringWidth: CGFloat = 20

/// The sweep: a wedge from the centre, swept clockwise, with softly rounded corners.
let sweepRadius: CGFloat = 306
let sweepFrom: CGFloat = -8, sweepTo: CGFloat = 62   // degrees clockwise from 12 o'clock
let sweepCorner: CGFloat = 26

/// The scanner at the centre, and the devices it has found on the rings.
let hubRadius: CGFloat = 54
let nodes: [(angle: CGFloat, ring: CGFloat, radius: CGFloat)] = [
    (36, 244, 44),    // inside the sweep: just found
    (148, 244, 36),
    (238, 244, 40),
    (300, 128, 31),
]

/// A point `distance` from the centre, `degrees` clockwise from 12 o'clock.
func polar(_ degrees: CGFloat, _ distance: CGFloat) -> CGPoint {
    let a = degrees * .pi / 180
    return CGPoint(x: center.x + distance * sin(a), y: center.y - distance * cos(a))
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
}

func screenPath() -> CGPath { circle(center, screenRadius) }

func ringsPath() -> CGPath {
    let p = CGMutablePath()
    for r in ringRadii {
        p.addPath(circle(center, r).copy(strokingWithWidth: ringWidth, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }
    return p
}

/// The wedge, built inset by `sweepCorner` and then grown back by the same amount with round joins,
/// so every corner is rounded and the outline still meets the intended radius and angles.
func sweepPath() -> CGPath {
    let r = sweepCorner
    let half = (sweepTo - sweepFrom) / 2 * .pi / 180
    let bisector = (sweepFrom + sweepTo) / 2
    let d = r / sin(half)                       // how far the inset wedge's apex moves out
    let apex = polar(bisector, d)
    let inner = sweepRadius - r
    // Where each inset edge (parallel to the original) meets the inset arc.
    let t = -d * cos(half) + sqrt(d * d * cos(half) * cos(half) - d * d + inner * inner)
    func edgeEnd(_ degrees: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: apex.x + t * sin(a), y: apex.y - t * cos(a))
    }
    let start = edgeEnd(sweepFrom), end = edgeEnd(sweepTo)
    let inset = CGMutablePath()
    inset.move(to: apex)
    inset.addLine(to: start)
    inset.addArc(center: center, radius: inner,
                 startAngle: atan2(start.y - center.y, start.x - center.x),
                 endAngle: atan2(end.y - center.y, end.x - center.x),
                 clockwise: false)               // increasing angle: clockwise on a y-down canvas
    inset.closeSubpath()
    return inset.copy(strokingWithWidth: 2 * r, lineCap: .round, lineJoin: .round, miterLimit: 10)
        .union(inset)
}

func hubPath() -> CGPath { circle(center, hubRadius) }

func nodesPath() -> CGPath {
    let p = CGMutablePath()
    for node in nodes { p.addPath(circle(polar(node.angle, node.ring), node.radius)) }
    return p
}

// MARK: SVG output

func svgPathData(_ path: CGPath) -> String {
    var d = ""
    func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    path.applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: d += "M\(f(p[0].x)) \(f(p[0].y))"
        case .addLineToPoint: d += "L\(f(p[0].x)) \(f(p[0].y))"
        case .addQuadCurveToPoint: d += "Q\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y))"
        case .addCurveToPoint: d += "C\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

func writeSVG(_ name: String, _ path: CGPath, color: String) throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <path fill="\(color)" fill-rule="nonzero" d="\(svgPathData(path))"/>
    </svg>
    """
    try svg.write(to: outputDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    print("wrote \(name)")
}

// Default (light) colors; Dark, Clear and Tinted are set in icon.json.
try writeSVG("screen.svg", screenPath(), color: "#FFFFFF")
try writeSVG("rings.svg", ringsPath(), color: "#C9D7F4")
try writeSVG("sweep.svg", sweepPath(), color: "#7AA5FA")
try writeSVG("hub.svg", hubPath(), color: "#1F55E0")
try writeSVG("nodes.svg", nodesPath(), color: "#1F55E0")
