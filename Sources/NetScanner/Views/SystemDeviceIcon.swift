//
//  SystemDeviceIcon.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import AppKit
import UniformTypeIdentifiers

/// macOS's own device artwork, the pictures Finder shows: exact Apple products from their model codes,
/// and computers, servers, printers and so on for the generic kinds the system has one for.
/// Every other kind falls back to an SF Symbol tile.
@MainActor
enum SystemDeviceIcon {
    private enum Source: Hashable {
        /// An Apple model code such as "Macmini9,1". macOS maps each one to that product's picture.
        case model(String)
        /// A system-declared type that carries a device icon.
        case type(String)
        /// An icon file inside a system framework.
        case file(String)
    }

    private static let modelCode = UTTagClass(rawValue: "com.apple.device-model-code")
    private static let printCore = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/PrintCore.framework/Resources"

    private static func source(for kind: DeviceKind) -> Source? {
        switch kind {
        // Apple devices that report no model show a current model of the same kind.
        case .iPhone: return .model("iPhone17,1")
        case .iPad: return .model("iPad16,3")
        case .macLaptop: return .model("Mac14,2")
        case .iMac: return .model("iMac21,1")
        case .macMini: return .model("Mac16,10")
        case .macStudio: return .model("Mac13,1")
        case .macPro: return .model("MacPro7,1")
        case .appleTV: return .model("AppleTV14,1")
        case .homePod: return .model("AudioAccessory6,1")
        case .homePodMini: return .model("AudioAccessory5,1")
        case .appleWatch: return .model("Watch7,1")
        case .visionPro: return .model("RealityDevice14,1")
        case .airPort: return .model("AirPort7,120")
        case .desktop: return .type("public.generic-pc")
        case .tv: return .type("public.display")
        case .speaker: return .type("public.speaker")
        case .nas: return .type("com.apple.generic-airdisk")
        case .server: return .type("com.apple.xserve")
        case .printer: return .file("\(printCore)/GenericInkjetPrinter.icns")
        default: return nil
        }
    }

    private static var cache: [Source: NSImage?] = [:]

    /// `model` is the device's Apple model code from Bonjour. When macOS knows it, the icon shows that exact product.
    static func image(for kind: DeviceKind, model: String? = nil) -> NSImage? {
        if kind.family == .apple, let model, let image = load(.model(model)) { return image }
        return source(for: kind).flatMap(load)
    }

    private static func load(_ source: Source) -> NSImage? {
        if let cached = cache[source] { return cached }
        let image: NSImage?
        switch source {
        case .model(let code):
            // Bare names such as "Watch" resolve to a type with no picture, so only full codes count.
            if code.contains(","), let type = UTType(tag: code, tagClass: modelCode, conformingTo: nil), type.isDeclared {
                image = NSWorkspace.shared.icon(for: type)
            } else {
                image = nil
            }
        case .type(let identifier):
            // Only declared types: an unknown identifier would come back as a blank document icon.
            if let type = UTType(identifier), type.isDeclared {
                image = NSWorkspace.shared.icon(for: type)
            } else {
                image = nil
            }
        case .file(let path):
            image = NSImage(contentsOfFile: path)
        }
        cache[source] = image
        return image
    }
}
