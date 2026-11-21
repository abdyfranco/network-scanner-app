//
//  DeviceKind.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import SwiftUI

enum DeviceFamily: String, CaseIterable {
    case apple, ubiquiti, other
}

/// Visual style for the custom-drawn UniFi hardware glyphs.
enum UniFiGlyphStyle {
    case rackGateway, console, compactGateway, deskSwitch, rackSwitch, miniSwitch
    case accessPoint, wallAccessPoint, camera, doorbell, nvr, cloudKey, generic
}

enum DeviceKind: String, CaseIterable {
    // Apple
    case iPhone, iPad, macLaptop, iMac, macMini, macStudio, macPro, appleTV, homePod, homePodMini
    case appleWatch, visionPro, airPort, appleDevice
    // Ubiquiti
    case unifiRackGateway, unifiConsole, unifiCompactGateway, unifiSwitch, unifiRackSwitch, unifiMiniSwitch
    case unifiAccessPoint, unifiWallAccessPoint, unifiCamera, unifiDoorbell, unifiNVR, unifiCloudKey, unifiDevice
    // Everything else
    case router, networkSwitch, accessPoint, phone, mobileDevice, tablet, laptop, desktop, server, nas
    case printer, tv, mediaPlayer, speaker, gameConsole, camera, smartHome, smartPlug, smartLight
    case thermostat, vacuum, singleBoardComputer, watch, car, virtualMachine, unknown

    var family: DeviceFamily {
        switch self {
        case .iPhone, .iPad, .macLaptop, .iMac, .macMini, .macStudio, .macPro, .appleTV, .homePod, .homePodMini,
             .appleWatch, .visionPro, .airPort, .appleDevice:
            return .apple
        case .unifiRackGateway, .unifiConsole, .unifiCompactGateway, .unifiSwitch, .unifiRackSwitch, .unifiMiniSwitch,
             .unifiAccessPoint, .unifiWallAccessPoint, .unifiCamera, .unifiDoorbell, .unifiNVR, .unifiCloudKey, .unifiDevice:
            return .ubiquiti
        default:
            return .other
        }
    }

    var title: String {
        switch self {
        case .iPhone: return String(localized: "iPhone")
        case .iPad: return String(localized: "iPad")
        case .macLaptop: return String(localized: "MacBook")
        case .iMac: return String(localized: "iMac")
        case .macMini: return String(localized: "Mac mini")
        case .macStudio: return String(localized: "Mac Studio")
        case .macPro: return String(localized: "Mac Pro")
        case .appleTV: return String(localized: "Apple TV")
        case .homePod: return String(localized: "HomePod")
        case .homePodMini: return String(localized: "HomePod mini")
        case .appleWatch: return String(localized: "Apple Watch")
        case .visionPro: return String(localized: "Apple Vision Pro")
        case .airPort: return String(localized: "AirPort Base Station")
        case .appleDevice: return String(localized: "Apple Device")
        case .unifiRackGateway: return String(localized: "UniFi Gateway")
        case .unifiConsole: return String(localized: "UniFi Console")
        case .unifiCompactGateway: return String(localized: "UniFi Gateway")
        case .unifiSwitch: return String(localized: "UniFi Switch")
        case .unifiRackSwitch: return String(localized: "UniFi Rack Switch")
        case .unifiMiniSwitch: return String(localized: "UniFi Mini Switch")
        case .unifiAccessPoint: return String(localized: "UniFi Access Point")
        case .unifiWallAccessPoint: return String(localized: "UniFi In-Wall AP")
        case .unifiCamera: return String(localized: "UniFi Camera")
        case .unifiDoorbell: return String(localized: "UniFi Doorbell")
        case .unifiNVR: return String(localized: "UniFi NVR")
        case .unifiCloudKey: return String(localized: "UniFi Cloud Key")
        case .unifiDevice: return String(localized: "UniFi Device")
        case .router: return String(localized: "Router")
        case .networkSwitch: return String(localized: "Network Switch")
        case .accessPoint: return String(localized: "Access Point")
        case .phone: return String(localized: "Phone")
        case .mobileDevice: return String(localized: "Mobile Device")
        case .tablet: return String(localized: "Tablet")
        case .laptop: return String(localized: "Laptop")
        case .desktop: return String(localized: "Computer")
        case .server: return String(localized: "Server")
        case .nas: return String(localized: "Network Storage")
        case .printer: return String(localized: "Printer")
        case .tv: return String(localized: "TV")
        case .mediaPlayer: return String(localized: "Media Player")
        case .speaker: return String(localized: "Speaker")
        case .gameConsole: return String(localized: "Game Console")
        case .camera: return String(localized: "Camera")
        case .smartHome: return String(localized: "Smart Home")
        case .smartPlug: return String(localized: "Smart Plug")
        case .smartLight: return String(localized: "Smart Light")
        case .thermostat: return String(localized: "Thermostat")
        case .vacuum: return String(localized: "Robot Vacuum")
        case .singleBoardComputer: return String(localized: "Single-Board Computer")
        case .watch: return String(localized: "Smartwatch")
        case .car: return String(localized: "Vehicle")
        case .virtualMachine: return String(localized: "Virtual Machine")
        case .unknown: return String(localized: "Unknown Device")
        }
    }

    /// SF Symbol for Apple and generic devices. UniFi devices use custom glyphs instead.
    var symbol: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .macLaptop: return "macbook"
        case .iMac: return "desktopcomputer"
        case .macMini: return "macmini"
        case .macStudio: return "macstudio"
        case .macPro: return "macpro.gen3"
        case .appleTV: return "appletv"
        case .homePod: return "homepod"
        case .homePodMini: return "homepodmini"
        case .appleWatch: return "applewatch"
        case .visionPro: return "visionpro"
        case .airPort: return "airport.extreme"
        case .appleDevice: return "macbook.and.iphone"
        case .unifiRackGateway, .unifiConsole, .unifiCompactGateway: return "wifi.router"
        case .unifiSwitch, .unifiRackSwitch, .unifiMiniSwitch: return "rectangle.connected.to.line.below"
        case .unifiAccessPoint, .unifiWallAccessPoint: return "antenna.radiowaves.left.and.right"
        case .unifiCamera, .unifiDoorbell: return "web.camera"
        case .unifiNVR: return "externaldrive.connected.to.line.below"
        case .unifiCloudKey, .unifiDevice: return "server.rack"
        case .router: return "wifi.router"
        case .networkSwitch: return "rectangle.connected.to.line.below"
        case .accessPoint: return "antenna.radiowaves.left.and.right"
        case .phone, .mobileDevice: return "smartphone"
        case .tablet: return "ipad.landscape"
        case .laptop: return "laptopcomputer"
        case .desktop: return "pc"
        case .server: return "server.rack"
        case .nas: return "externaldrive.connected.to.line.below"
        case .printer: return "printer"
        case .tv: return "tv"
        case .mediaPlayer: return "mediastick"
        case .speaker: return "hifispeaker"
        case .gameConsole: return "gamecontroller"
        case .camera: return "web.camera"
        case .smartHome: return "homekit"
        case .smartPlug: return "powerplug"
        case .smartLight: return "lightbulb"
        case .thermostat: return "thermometer.medium"
        case .vacuum: return "robotic.vacuum"
        case .singleBoardComputer: return "cpu"
        case .watch: return "watch.analog"
        case .car: return "car"
        case .virtualMachine: return "square.stack.3d.up"
        case .unknown: return "questionmark.square.dashed"
        }
    }

    /// UniFi gear that UniFi Network manages. Cameras, doorbells and NVRs belong to UniFi Protect.
    var isManagedByUniFiNetwork: Bool {
        switch self {
        case .unifiRackGateway, .unifiConsole, .unifiCompactGateway, .unifiSwitch, .unifiRackSwitch, .unifiMiniSwitch,
             .unifiAccessPoint, .unifiWallAccessPoint, .unifiCloudKey, .unifiDevice:
            return true
        default:
            return false
        }
    }

    /// Computers, servers and network storage, whose network cards commonly wake on a magic packet.
    var supportsWakeOnLAN: Bool {
        switch self {
        case .macLaptop, .iMac, .macMini, .macStudio, .macPro, .laptop, .desktop, .server, .nas:
            return true
        default:
            return false
        }
    }

    /// UniFi OS consoles, which can host the UniFi Network app.
    var hostsUniFiOS: Bool {
        [.unifiRackGateway, .unifiConsole, .unifiCompactGateway, .unifiCloudKey].contains(self)
    }

    var unifiStyle: UniFiGlyphStyle? {
        switch self {
        case .unifiRackGateway: return .rackGateway
        case .unifiConsole: return .console
        case .unifiCompactGateway: return .compactGateway
        case .unifiSwitch: return .deskSwitch
        case .unifiRackSwitch: return .rackSwitch
        case .unifiMiniSwitch: return .miniSwitch
        case .unifiAccessPoint: return .accessPoint
        case .unifiWallAccessPoint: return .wallAccessPoint
        case .unifiCamera: return .camera
        case .unifiDoorbell: return .doorbell
        case .unifiNVR: return .nvr
        case .unifiCloudKey: return .cloudKey
        case .unifiDevice: return .generic
        default: return nil
        }
    }

    var tint: Color {
        switch family {
        case .apple: return Color(white: 0.55)
        case .ubiquiti: return Color(red: 0.0, green: 0.44, blue: 1.0)
        case .other: break
        }
        switch self {
        case .router, .networkSwitch, .accessPoint: return .cyan
        case .phone, .mobileDevice: return .green
        case .tablet: return .teal
        case .laptop, .desktop: return .indigo
        case .server, .virtualMachine: return .gray
        case .nas: return .blue
        case .printer: return .orange
        case .tv, .mediaPlayer: return .purple
        case .speaker: return .pink
        case .gameConsole: return .red
        case .camera: return .yellow
        case .smartHome, .smartPlug, .smartLight, .thermostat, .vacuum: return .orange
        case .singleBoardComputer: return .red
        case .watch: return .mint
        case .car: return .red
        default: return .gray
        }
    }
}
