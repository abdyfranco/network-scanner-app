//
//  OUIDatabase.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation

/// MAC prefix → vendor lookup with longest-prefix matching across MA-L (24-bit),
/// MA-M (28-bit) and MA-S (36-bit) assignments.
final class OUIDatabase: @unchecked Sendable {
    static let shared = OUIDatabase()

    struct Status: Sendable, Equatable {
        var entries: Int
        var source: String
        var modified: Date?
    }

    private let lock = NSLock()
    private var ma24: [UInt32: String] = [:]
    private var ma28: [UInt32: String] = [:]
    private var ma36: [UInt64: String] = [:]
    private var _status = Status(entries: 0, source: String(localized: "Not loaded"), modified: nil)

    var status: Status { lock.withLock { _status } }

    static var userDatabaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("NetScanner", isDirectory: true).appendingPathComponent("oui.txt")
    }

    static var bundledDatabaseURL: URL? {
        var candidates: [URL] = []
        if let url = Bundle.main.url(forResource: "oui", withExtension: "txt") { candidates.append(url) }
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exe.appendingPathComponent("oui.txt"))
            candidates.append(exe.appendingPathComponent("../Resources/oui.txt").standardizedFileURL)
        }
        // Development fallback when launched with `swift run`.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(sourceRoot.appendingPathComponent("Resources/oui.txt"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Loads the user-downloaded database if present, otherwise the bundled one.
    func loadPreferred() {
        if FileManager.default.fileExists(atPath: Self.userDatabaseURL.path), load(from: Self.userDatabaseURL, source: String(localized: "IEEE (downloaded)")) {
            return
        }
        if let url = Self.bundledDatabaseURL { _ = load(from: url, source: String(localized: "Built-in")) }
    }

    @discardableResult
    func load(from url: URL, source: String) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let text = String(decoding: data, as: UTF8.self)
        var new24: [UInt32: String] = [:], new28: [UInt32: String] = [:], new36: [UInt64: String] = [:]
        new24.reserveCapacity(40_000)

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let first = line.first, first != "#", let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let prefix = line[..<space]
            let vendor = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
            guard !vendor.isEmpty, let value = UInt64(prefix, radix: 16) else { continue }
            switch prefix.count {
            case 6: new24[UInt32(value)] = vendor
            case 7: new28[UInt32(value)] = vendor
            case 9: new36[value] = vendor
            default: continue
            }
        }
        guard !new24.isEmpty else { return false }

        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        lock.withLock {
            ma24 = new24
            ma28 = new28
            ma36 = new36
            _status = Status(entries: new24.count + new28.count + new36.count, source: source, modified: modified)
        }
        return true
    }

    func vendor(for mac: MACAddress) -> String? {
        lock.withLock {
            ma36[mac.value >> 12] ?? ma28[UInt32(truncatingIfNeeded: mac.value >> 20)] ?? ma24[UInt32(truncatingIfNeeded: mac.value >> 24)]
        }
    }

    // MARK: IEEE refresh

    private static let registries = [
        URL(string: "https://standards-oui.ieee.org/oui/oui.csv")!,
        URL(string: "https://standards-oui.ieee.org/oui28/mam.csv")!,
        URL(string: "https://standards-oui.ieee.org/oui36/oui36.csv")!,
    ]

    /// Downloads the current IEEE registries, stores them in Application Support and reloads.
    func updateFromIEEE() async throws -> Int {
        var request = URLRequest(url: Self.registries[0])
        request.setValue("Mozilla/5.0 (Macintosh) NetScanner", forHTTPHeaderField: "User-Agent")
        var lines: [String] = ["# Downloaded from the IEEE Registration Authority on \(Date().formatted(date: .abbreviated, time: .shortened))"]

        for url in Self.registries {
            request.url = url
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            for row in Self.parseCSV(String(decoding: data, as: UTF8.self)).dropFirst() where row.count >= 3 {
                let assignment = row[1].trimmingCharacters(in: .whitespaces)
                guard [6, 7, 9].contains(assignment.count), UInt64(assignment, radix: 16) != nil else { continue }
                lines.append("\(assignment.uppercased()) \(Self.shorten(row[2]))")
            }
        }
        guard lines.count > 10_000 else { throw URLError(.cannotParseResponse) }

        let url = Self.userDatabaseURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        guard load(from: url, source: String(localized: "IEEE (downloaded)")) else { throw URLError(.cannotParseResponse) }
        return lines.count - 1
    }

    func resetToBuiltIn() {
        try? FileManager.default.removeItem(at: Self.userDatabaseURL)
        if let url = Self.bundledDatabaseURL { load(from: url, source: String(localized: "Built-in")) }
    }

    private static func shorten(_ organization: String) -> String {
        var name = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [", Inc.", ", Inc", " Inc.", " Inc", " Co.,Ltd.", " Co., Ltd.", " Co.,Ltd", " Co., Ltd", " Co. Ltd.",
                        " Corporation", " Corp.", " Corp", " GmbH", " LLC", " Ltd.", " Ltd", " Limited", " S.A.", " AG", " B.V.", " AB", ","]
        var changed = true
        while changed {
            changed = false
            for suffix in suffixes where name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return name.isEmpty ? organization : name
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        while let c = iterator.next() {
            if inQuotes {
                if c == "\"" {
                    inQuotes = false
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n":
                    row.append(field); field = ""
                    rows.append(row); row = []
                case "\r": continue
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
