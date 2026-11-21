//
//  DeviceClassifier.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation

/// Infers what a device is from every clue gathered during the scan, strongest evidence first:
/// local hardware → UniFi discovery → Apple model identifiers (Bonjour TXT) → Apple-only services
/// → hostnames → service types and open ports → MAC vendor → network role.
enum DeviceClassifier {
    struct Result {
        var kind: DeviceKind
        var modelName: String?
        var modelIdentifier: String?
    }

    static func classify(_ d: Device) -> Result {
        let vendor = (d.vendor ?? "").lowercased()
        let names = [d.mdnsName, d.dnsName, d.netbiosName, d.ubiquiti?.hostname, d.bonjourName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let types = Set(d.services.map(\.type))
        let ports = d.openPorts

        // 1. This Mac.
        if d.isSelf {
            let identifier = LocalHost.hardwareModel
            let kind = identifier.flatMap(AppleModelCatalog.kind(for:)) ?? .macLaptop
            return Result(kind: kind, modelName: identifier.flatMap(AppleModelCatalog.marketingName(for:)), modelIdentifier: identifier)
        }

        // 2. Ubiquiti — by discovery, by vendor, or (across a router, where there is no MAC) by a
        //    default UniFi hostname or the UniFi console's distinctive port set.
        let unifiByName = d.mac == nil && UniFiCatalog.looksLikeUniFiHostname(names)
        let unifiByPorts = d.mac == nil && ports.isSuperset(of: [6789, 8443]) && ports.contains(8880)
        if d.ubiquiti != nil || vendor.contains("ubiquiti") || unifiByName || unifiByPorts {
            let info = d.ubiquiti
            let clues = [info?.model, info?.platform, info?.hostname, info?.productName, info?.firmware.map(firmwarePrefix),
                         d.dnsName, d.mdnsName].compactMap { $0 }
            let kind = UniFiCatalog.kind(for: clues, isGateway: d.isGateway || unifiByPorts)
            let code = info?.modelCode
            let name = info?.productName ?? code.flatMap(UniFiCatalog.productName(for:)) ?? code
            return Result(kind: kind, modelName: name, modelIdentifier: code)
        }

        // 3. Apple model identifiers advertised over Bonjour.
        if let identifier = appleModelIdentifier(d), let kind = AppleModelCatalog.kind(for: identifier) {
            return Result(kind: kind, modelName: AppleModelCatalog.marketingName(for: identifier), modelIdentifier: identifier)
        }

        // 4. Apple-only signals.
        let isApple = vendor.hasPrefix("apple")
        if types.contains("_apple-mobdev2._tcp") || ports.contains(62078) {
            return Result(kind: names.contains("ipad") ? .iPad : .iPhone)
        }
        if let kind = appleKindFromName(names) {
            return Result(kind: kind)
        }
        if isApple || types.contains("_companion-link._tcp") || types.contains("_device-info._tcp") {
            if types.contains("_touch-able._tcp") || types.contains("_mediaremotetv._tcp") { return Result(kind: .appleTV) }
            if types.contains("_airport._tcp") { return Result(kind: .airPort) }
            return Result(kind: .appleDevice)
        }

        // 5. Service types and open ports.
        if let kind = kindFromServices(d, types: types, ports: ports, names: names, vendor: vendor) {
            return Result(kind: kind, modelName: genericModel(d))
        }

        // 6. Hostname keywords.
        if let kind = kindFromName(names) {
            return Result(kind: kind, modelName: genericModel(d))
        }

        // 7. Vendor.
        if let kind = kindFromVendor(vendor, names: names) {
            return Result(kind: kind, modelName: genericModel(d))
        }

        // 8. Network role and weaker port hints.
        if d.isGateway { return Result(kind: .router) }
        if d.netbiosName != nil || ports.contains(3389) || ports.contains(135) { return Result(kind: .desktop) }
        if ports.contains(22) && (ports.contains(80) || ports.contains(443)) { return Result(kind: .server) }
        if d.hasPrivateMAC, d.services.isEmpty, ports.isEmpty { return Result(kind: .mobileDevice) }
        return Result(kind: .unknown, modelName: genericModel(d))
    }

    // MARK: Helpers

    private static func firmwarePrefix(_ firmware: String) -> String {
        firmware.split(separator: ".").first.map(String.init) ?? firmware
    }

    private static func appleModelIdentifier(_ d: Device) -> String? {
        let keys = ["model", "rpmd", "am", "md"]
        let preferredTypes = ["_device-info._tcp", "_companion-link._tcp", "_airplay._tcp", "_raop._tcp"]
        for type in preferredTypes {
            for service in d.services where service.type == type {
                for key in keys {
                    if let value = service.txt[key], AppleModelCatalog.kind(for: value) != nil { return value }
                }
            }
        }
        return nil
    }

    private static func genericModel(_ d: Device) -> String? {
        for service in d.services {
            if service.type == "_googlecast._tcp", let md = service.txt["md"], !md.isEmpty { return md }
            if service.type.hasPrefix("_ipp"), let ty = service.txt["ty"], !ty.isEmpty { return ty }
            if service.type == "_hap._tcp", let md = service.txt["md"], !md.isEmpty { return md }
            if service.type == "_device-info._tcp", let model = service.txt["model"], !model.isEmpty { return model }
        }
        return nil
    }

    private static func appleKindFromName(_ names: String) -> DeviceKind? {
        guard !names.isEmpty else { return nil }
        if names.contains("iphone") { return .iPhone }
        if names.contains("ipad") { return .iPad }
        if names.contains("macbook") { return .macLaptop }
        if names.contains("imac") { return .iMac }
        if names.contains("mac-mini") || names.contains("macmini") || names.contains("mac mini") { return .macMini }
        if names.contains("mac-studio") || names.contains("macstudio") || names.contains("mac studio") { return .macStudio }
        if names.contains("mac-pro") || names.contains("mac pro") { return .macPro }
        if names.contains("apple-tv") || names.contains("appletv") || names.contains("apple tv") { return .appleTV }
        if names.contains("homepod") { return .homePod }
        if names.contains("apple-watch") || names.contains("apple watch") { return .appleWatch }
        if names.contains("vision-pro") || names.contains("vision pro") { return .visionPro }
        return nil
    }

    private static func kindFromServices(_ d: Device, types: Set<String>, ports: Set<UInt16>, names: String, vendor: String) -> DeviceKind? {
        let printerTypes: Set<String> = ["_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp", "_uscan._tcp", "_scanner._tcp"]
        if !types.isDisjoint(with: printerTypes) || ports.contains(9100) || (ports.contains(515) && ports.contains(631)) {
            return .printer
        }
        if types.contains("_googlecast._tcp") || ports.contains(8009) {
            let model = (d.services.first { $0.type == "_googlecast._tcp" }?.txt["md"] ?? "").lowercased()
            if ["speaker", "audio", "nest mini", "home mini", "nest audio", "google home"].contains(where: model.contains) { return .speaker }
            if ["tv", "bravia", "shield"].contains(where: model.contains) { return .tv }
            return .mediaPlayer
        }
        if types.contains("_amzn-wplay._tcp") { return .mediaPlayer }
        if types.contains("_androidtvremote2._tcp") { return .tv }
        if types.contains("_sonos._tcp") || ports.contains(1400) { return .speaker }
        if types.contains("_adisk._tcp") { return .nas }
        if types.contains("_spotify-connect._tcp") || types.contains("_raop._tcp") { return .speaker }
        if types.contains("_home-assistant._tcp") || ports.contains(8123) { return .server }
        if types.contains("_esphomelib._tcp") || types.contains("_ewelink._tcp") { return .smartPlug }
        if !types.isDisjoint(with: ["_hap._tcp", "_hap._udp", "_homekit._tcp", "_matter._tcp", "_matterc._udp"]) {
            return kindFromVendor(vendor, names: names).flatMap { [.smartPlug, .smartLight, .thermostat, .vacuum, .camera, .speaker].contains($0) ? $0 : nil } ?? .smartHome
        }
        if ports.contains(554) { return .camera }
        if ports.contains(32400) { return .server }
        if types.contains("_smb._tcp") || types.contains("_afpovertcp._tcp") || ports.contains(5001) {
            if ["synology", "qnap", "western digital", "buffalo", "asustor", "terramaster", "netgear"].contains(where: vendor.contains) { return .nas }
        }
        if types.contains("_workstation._tcp") || types.contains("_rfb._tcp") { return .desktop }
        return nil
    }

    private static func kindFromName(_ names: String) -> DeviceKind? {
        guard !names.isEmpty else { return nil }
        func has(_ words: String...) -> Bool { words.contains { names.contains($0) } }
        if has("android", "galaxy", "pixel", "oneplus", "redmi", "xiaomi", "huawei", "moto-", "motorola", "phone") { return .phone }
        if has("kindle", "tablet", "-tab", "galaxy-tab") { return .tablet }
        if has("playstation", "ps4", "ps5", "xbox", "nintendo", "switch-console") { return .gameConsole }
        if has("printer", "laserjet", "officejet", "deskjet", "envy", "brother", "epson", "canon", "brw", "brn", "npi") { return .printer }
        if has("roku", "chromecast", "firetv", "fire-tv", "shield", "appletv") { return .mediaPlayer }
        if has("bravia", "-tv", "tv-", "smarttv", "webos", "tizen", "vizio") { return .tv }
        if has("sonos", "echo", "speaker", "homepod", "nest-mini", "google-home", "nest-audio") { return .speaker }
        if has("diskstation", "synology", "qnap", "truenas", "nas", "mycloud", "unraid") { return .nas }
        if has("raspberrypi", "raspberry", "rpi-", "pihole", "pi-hole") { return .singleBoardComputer }
        if has("camera", "cam-", "-cam", "doorbell", "reolink", "hikvision", "wyze") { return .camera }
        if has("vacuum", "roomba", "roborock", "deebot") { return .vacuum }
        if has("thermostat", "ecobee", "nest-") { return .thermostat }
        if has("bulb", "lamp", "light", "hue-", "lifx", "nanoleaf", "govee", "wiz_", "wiz-", "yeelight") { return .smartLight }
        if has("plug", "outlet", "shelly", "tasmota", "sonoff", "kasa", "tapo", "esp-", "esp_", "esp32", "esp8266", "wemo", "ewelink") { return .smartPlug }
        if has("laptop", "thinkpad", "notebook", "xps", "surface", "zenbook", "chromebook") { return .laptop }
        if has("desktop-", "workstation", "-pc", "pc-") { return .desktop }
        if has("server", "proxmox", "esxi", "docker", "homeassistant") { return .server }
        if has("extender", "repeater", "access point", "mesh point") { return .accessPoint }
        if has("router", "gateway", "openwrt", "pfsense", "opnsense", "mikrotik", "linksys", "netgear", "eero") { return .router }
        if has("switch") { return .networkSwitch }
        if has("watch") { return .watch }
        if has("tesla") { return .car }
        return nil
    }

    static func kindFromVendor(_ vendor: String, names: String) -> DeviceKind? {
        guard !vendor.isEmpty else { return nil }
        func has(_ words: String...) -> Bool { words.contains { vendor.contains($0) } }
        if has("apple") { return .appleDevice }
        if has("raspberry") { return .singleBoardComputer }
        if has("sonos", "bose", "harman", "bang & olufsen", "denon", "marantz", "sound united", "devialet", "jbl") { return .speaker }
        if has("roku") { return .mediaPlayer }
        if has("vizio", "tcl", "hisense", "lg electronics", "tp vision", "sharp", "panasonic", "skyworth", "funai") { return .tv }
        if has("nintendo", "sony interactive") { return .gameConsole }
        if has("brother", "canon", "seiko epson", "epson", "xerox", "lexmark", "kyocera", "ricoh", "konica", "hp inc", "hewlett packard", "hewlett-packard") {
            return has("hewlett packard enterprise") ? .server : .printer
        }
        if has("synology", "qnap", "western digital", "buffalo", "asustor", "terramaster", "drobo", "netapp") { return .nas }
        if has("hikvision", "dahua", "axis comm", "reolink", "amcrest", "wyze", "arlo", "ring", "foscam", "hanwha", "vivotek", "lorex", "swann", "ezviz", "eufy") { return .camera }
        if has("signify", "philips lighting", "lifx", "nanoleaf", "lutron", "govee", "wiz connected", "intellirocks") { return .smartLight }
        if has("ecobee", "nest labs", "honeywell", "resideo", "tado") { return .thermostat }
        if has("irobot", "roborock", "ecovacs", "dreame") { return .vacuum }
        if has("espressif", "tuya", "shelly", "allterco", "itead", "sonoff", "meross", "belkin", "tp-link", "tp link", "wemo", "broadlink") { return .smartPlug }
        if has("lumi united", "aqara", "chamberlain", "august", "yale", "level home", "silicon labs", "texas instruments", "nordic semi", "ezurio") { return .smartHome }
        if has("samsung", "xiaomi", "oneplus", "oppo", "vivo mobile", "huawei", "honor device", "motorola", "hmd global", "realme", "nothing tech", "zte", "fairphone", "sony mobile") {
            return names.contains("tv") ? .tv : .phone
        }
        if has("google") {
            if names.contains("pixel") || names.contains("android") { return .phone }
            return .speaker
        }
        if has("amazon") {
            if names.contains("kindle") { return .tablet }
            if names.contains("fire") { return .mediaPlayer }
            return .speaker
        }
        if has("microsoft") { return names.contains("xbox") ? .gameConsole : .laptop }
        if has("tesla") { return .car }
        if has("vmware", "parallels", "qemu", "xensource", "proxmox", "red hat", "nutanix") { return .virtualMachine }
        if has("super micro", "supermicro", "hewlett packard enterprise", "inspur") { return .server }
        if has("intel", "liteon", "lite-on", "azurewave", "hon hai", "foxconn", "universal global", "rivet networks", "framework") { return .laptop }
        if has("dell", "lenovo") { return .laptop }
        if has("asustek", "micro-star", "gigabyte", "giga-byte", "asrock", "realtek", "elitegroup", "shuttle") { return .desktop }
        if has("netgear", "linksys", "cisco", "juniper", "mikrotik", "routerboard", "aruba", "ruckus", "eero", "arris", "technicolor",
               "sagemcom", "zyxel", "draytek", "fortinet", "palo alto", "meraki", "d-link", "tenda", "commscope", "calix", "nokia shanghai") {
            return .router
        }
        return nil
    }
}

// MARK: - Apple models

enum AppleModelCatalog {
    static func kind(for identifier: String) -> DeviceKind? {
        let id = identifier.trimmingCharacters(in: .whitespaces)
        if id.hasPrefix("iPhone") || id.hasPrefix("iPod") { return .iPhone }
        if id.hasPrefix("iPad") { return .iPad }
        if id.hasPrefix("Watch") { return .appleWatch }
        if id.hasPrefix("AppleTV") { return .appleTV }
        if id.hasPrefix("AudioAccessory5") { return .homePodMini }
        if id.hasPrefix("AudioAccessory") { return .homePod }
        if id.hasPrefix("RealityDevice") { return .visionPro }
        if id.hasPrefix("AirPort") { return .airPort }
        if id.hasPrefix("MacBook") { return .macLaptop }
        if id.hasPrefix("iMac") { return .iMac }
        if id.hasPrefix("Macmini") { return .macMini }
        if id.hasPrefix("MacPro") { return .macPro }
        if id.hasPrefix("Mac"), id.dropFirst(3).first?.isNumber == true {
            return modernMacs[id]?.0 ?? .macLaptop
        }
        return nil
    }

    static func marketingName(for identifier: String) -> String? {
        if let entry = modernMacs[identifier] { return entry.1 }
        return otherDevices[identifier]
    }

    /// Apple silicon Macs use opaque "MacNN,N" identifiers.
    private static let modernMacs: [String: (DeviceKind, String)] = [
        "Mac13,1": (.macStudio, "Mac Studio (2022)"), "Mac13,2": (.macStudio, "Mac Studio (2022)"),
        "Mac14,2": (.macLaptop, "MacBook Air (M2)"), "Mac14,15": (.macLaptop, "MacBook Air 15\" (M2)"),
        "Mac14,3": (.macMini, "Mac mini (M2)"), "Mac14,12": (.macMini, "Mac mini (M2 Pro)"),
        "Mac14,5": (.macLaptop, "MacBook Pro 14\" (M2)"), "Mac14,9": (.macLaptop, "MacBook Pro 14\" (M2)"),
        "Mac14,6": (.macLaptop, "MacBook Pro 16\" (M2)"), "Mac14,10": (.macLaptop, "MacBook Pro 16\" (M2)"),
        "Mac14,7": (.macLaptop, "MacBook Pro 13\" (M2)"), "Mac14,8": (.macPro, "Mac Pro (2023)"),
        "Mac14,13": (.macStudio, "Mac Studio (2023)"), "Mac14,14": (.macStudio, "Mac Studio (2023)"),
        "Mac15,3": (.macLaptop, "MacBook Pro 14\" (M3)"), "Mac15,4": (.iMac, "iMac (M3)"), "Mac15,5": (.iMac, "iMac (M3)"),
        "Mac15,6": (.macLaptop, "MacBook Pro 14\" (M3 Pro)"), "Mac15,8": (.macLaptop, "MacBook Pro 14\" (M3 Max)"),
        "Mac15,10": (.macLaptop, "MacBook Pro 14\" (M3 Max)"), "Mac15,7": (.macLaptop, "MacBook Pro 16\" (M3 Pro)"),
        "Mac15,9": (.macLaptop, "MacBook Pro 16\" (M3 Max)"), "Mac15,11": (.macLaptop, "MacBook Pro 16\" (M3 Max)"),
        "Mac15,12": (.macLaptop, "MacBook Air 13\" (M3)"), "Mac15,13": (.macLaptop, "MacBook Air 15\" (M3)"),
        "Mac15,14": (.macStudio, "Mac Studio (M3 Ultra)"),
        "Mac16,1": (.macLaptop, "MacBook Pro 14\" (M4)"), "Mac16,2": (.iMac, "iMac (M4)"), "Mac16,3": (.iMac, "iMac (M4)"),
        "Mac16,5": (.macLaptop, "MacBook Pro 16\" (M4)"), "Mac16,7": (.macLaptop, "MacBook Pro 16\" (M4)"),
        "Mac16,6": (.macLaptop, "MacBook Pro 14\" (M4)"), "Mac16,8": (.macLaptop, "MacBook Pro 14\" (M4)"),
        "Mac16,9": (.macStudio, "Mac Studio (M4 Max)"), "Mac16,10": (.macMini, "Mac mini (M4)"),
        "Mac16,11": (.macMini, "Mac mini (M4 Pro)"), "Mac16,12": (.macLaptop, "MacBook Air 13\" (M4)"),
        "Mac16,13": (.macLaptop, "MacBook Air 15\" (M4)"), "Mac17,2": (.macLaptop, "MacBook Pro 14\" (M5)"),
    ]

    private static let otherDevices: [String: String] = [
        "AppleTV5,3": "Apple TV HD", "AppleTV6,2": "Apple TV 4K", "AppleTV11,1": "Apple TV 4K (2nd gen)",
        "AppleTV14,1": "Apple TV 4K (3rd gen)", "AudioAccessory1,1": "HomePod", "AudioAccessory1,2": "HomePod",
        "AudioAccessory5,1": "HomePod mini", "AudioAccessory6,1": "HomePod (2nd gen)", "RealityDevice14,1": "Apple Vision Pro",
    ]
}

// MARK: - UniFi models

enum UniFiCatalog {
    /// Strong UniFi hostname prefixes only; looser codes (UX, UK, G4) collide with ordinary names.
    static func looksLikeUniFiHostname(_ names: String) -> Bool {
        let prefixes = ["usw", "uap", "u6-", "u7-", "udm", "ucg", "udr", "uxg", "unvr", "uck", "unifi"]
        return names.split(separator: " ").contains { word in prefixes.contains { word.hasPrefix($0) } }
    }

    static func kind(for clues: [String], isGateway: Bool) -> DeviceKind {
        for clue in clues {
            if let kind = kind(forCode: clue) { return kind }
        }
        // Admin-assigned names such as "office-switch" or "Garage AP".
        let words = clues.joined(separator: " ").lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { words.contains($0) } }
        if has("doorbell") { return .unifiDoorbell }
        if has("camera", "cam-", "-cam", "dome", "bullet") { return .unifiCamera }
        if has("nvr", "protect") { return .unifiNVR }
        if has("aggregation", "rack", "core-switch", "coreswitch") { return .unifiRackSwitch }
        if has("flexmini", "flex-mini", "flex mini") { return .unifiMiniSwitch }
        if has("switch", "sw-", "-sw") { return .unifiSwitch }
        if has("in-wall", "inwall") { return .unifiWallAccessPoint }
        if has("ap-", "-ap", " ap", "access point", "accesspoint", "wifi", "wi-fi", "mesh") { return .unifiAccessPoint }
        if has("gateway", "router", "dream", "console") || isGateway { return .unifiConsole }
        return .unifiDevice
    }

    /// Matches model codes ("UDMPRO", "USL16LP", "U7PG2"), model names ("USW-Flex-XG") and default hostnames.
    static func kind(forCode raw: String) -> DeviceKind? {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !code.isEmpty else { return nil }
        func starts(_ prefixes: String...) -> Bool { prefixes.contains { code.hasPrefix($0) } }

        if starts("UVCG4DB", "G4DB", "G4DOORBELL", "UVCG6DB", "G6DB") || code.contains("DOORBELL") { return .unifiDoorbell }
        if starts("UVC", "G3", "G4", "G5", "G6", "AI360", "AIPRO", "AIBULLET", "AITHETA") { return .unifiCamera }
        if starts("UNVR", "UNAS", "ENVR", "UNVRPRO") { return .unifiNVR }
        if starts("UCK", "UCKG2", "CLOUDKEY") { return .unifiCloudKey }
        if starts("UDMPRO", "UDMSE", "UDMENT", "UXGPRO", "UXGENT", "UXGMAX", "EFG", "UCGFIBER") || code.contains("DREAMMACHINEPRO") {
            return .unifiRackGateway
        }
        if starts("UCG", "UX", "UXG", "UDRULT", "UCGULTRA", "UCGMAX") { return .unifiCompactGateway }
        if starts("UDM", "UDR", "UDW") || code.contains("DREAMMACHINE") || code.contains("DREAMROUTER") { return .unifiConsole }
        if starts("USMINI", "USWFLEXMINI", "USF5M", "USWFLEX2") || (code.hasPrefix("USW") && code.contains("MINI")) { return .unifiMiniSwitch }
        if starts("USW", "USL", "USF", "USM", "USXG", "USPRO", "USAGG", "USENT", "USC8", "USWED") ||
            (code.hasPrefix("US") && code.dropFirst(2).first?.isNumber == true) {
            let rack = code.contains("24") || code.contains("48") || code.contains("AGG") || code.contains("PRO") && !code.contains("PROMAX8")
            return rack && !code.contains("FLEX") && !code.contains("LITE") && !code.contains("USL") ? .unifiRackSwitch : .unifiSwitch
        }
        if starts("UAPIW", "UAPIWHD", "U6IW", "U7IW", "UK") || code.contains("INWALL") || (starts("U6", "U7", "UAP") && code.contains("IW")) {
            return .unifiWallAccessPoint
        }
        if starts("UAP", "U6", "U7", "U8", "UAL", "UAE", "UALR", "U2", "BZ2", "UMA", "UWB", "E7") { return .unifiAccessPoint }
        return nil
    }

    static func productName(for code: String) -> String? {
        let names: [String: String] = [
            "UDMPRO": "Dream Machine Pro", "UDMPROSE": "Dream Machine SE", "UDMSE": "Dream Machine SE",
            "UDMPROMAX": "Dream Machine Pro Max", "UDM": "Dream Machine", "UDR": "Dream Router",
            "UDR7": "Dream Router 7", "UCGULTRA": "Cloud Gateway Ultra", "UCGMAX": "Cloud Gateway Max",
            "UCGFIBER": "Cloud Gateway Fiber", "UXG": "Gateway Lite", "UXGPRO": "Gateway Pro", "UXGMAX": "Gateway Max",
            "UCKG2PLUS": "Cloud Key Gen2 Plus", "UCKG2": "Cloud Key Gen2", "UNVR": "Network Video Recorder",
            "USMINI": "USW Flex Mini", "USL8LP": "USW Lite 8 PoE", "USL16LP": "USW Lite 16 PoE", "USF5P": "USW Flex",
            "USFXG": "USW Flex XG", "UAL6": "U6 Lite", "UALR6": "U6 LR", "U7PG2": "UAP AC Pro", "U7NHD": "UAP nanoHD",
            "U7LT": "UAP AC Lite", "U7LR": "UAP AC LR",
        ]
        return names[code.uppercased()]
    }
}
