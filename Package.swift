// swift-tools-version: 6.2

//
//  Package.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import PackageDescription

let package = Package(
    name: "NetScanner",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "NetScanner", targets: ["NetScanner"])
    ],
    targets: [
        .executableTarget(
            name: "NetScanner",
            path: "Sources/NetScanner",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
