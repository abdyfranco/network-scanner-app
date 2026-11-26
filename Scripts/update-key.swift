//
//  update-key.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

// Signs release disk images so the app's updater can tell a real release from a forged one.
//   swift Scripts/update-key.swift keygen            creates the private key (once) and prints its public key
//   swift Scripts/update-key.swift public-key        prints the public key
//   swift Scripts/update-key.swift sign <file.dmg>   writes <file.dmg>.sig
//
// The Ed25519 private key lives in a file outside the repository: NETWORK_SCANNER_SIGNING_KEY, by default
// ~/.network-scanner-signing/update-signing.key. Its public key is compiled into the app
// (`Updater.signingKey`). Back the file up and never commit it: without it, installed copies won't
// accept any future update.
import CryptoKit
import Foundation

let keyPath = ProcessInfo.processInfo.environment["NETWORK_SCANNER_SIGNING_KEY"]
    ?? NSHomeDirectory() + "/.network-scanner-signing/update-signing.key"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: keyPath, encoding: .utf8) else {
        fail("no signing key at \(keyPath). Run `swift Scripts/update-key.swift keygen`, or restore the file from your backup.")
    }
    guard let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("\(keyPath) doesn't hold an Ed25519 private key.")
    }
    return key
}

/// The public key compiled into the app, read from Updater.swift.
func appPublicKey() -> String? {
    let script = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let source = script.appendingPathComponent("../Sources/NetScanner/App/Updater.swift").standardizedFileURL
    guard let text = try? String(contentsOf: source, encoding: .utf8),
          let match = text.firstMatch(of: #/static let signingKey = "([A-Za-z0-9+/=]*)"/#) else { return nil }
    return String(match.1)
}

let args = CommandLine.arguments
switch args.dropFirst().first {
case "keygen":
    if FileManager.default.fileExists(atPath: keyPath) {
        fail("\(keyPath) already exists. Installed copies trust only that key, so keep using it.")
    }
    let directory = (keyPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let key = Curve25519.Signing.PrivateKey()
    guard FileManager.default.createFile(atPath: keyPath, contents: Data((key.rawRepresentation.base64EncodedString() + "\n").utf8),
                                         attributes: [.posixPermissions: 0o600]) else {
        fail("couldn't write \(keyPath).")
    }
    print("Created \(keyPath). Back it up and keep it secret.")
    print("Public key for Updater.signingKey: \(key.publicKey.rawRepresentation.base64EncodedString())")

case "public-key":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())

case "sign":
    guard args.count == 3 else { fail("usage: update-key.swift sign <file.dmg>") }
    let key = loadKey()
    let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    guard appPublicKey() == publicKey else {
        fail("the key in \(keyPath) (public key \(publicKey)) isn't the one in Updater.swift, so the app would reject this signature.")
    }
    let file = URL(fileURLWithPath: args[2])
    guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { fail("can't read \(file.path)") }
    let signature = try key.signature(for: data)
    let output = file.appendingPathExtension("sig")
    try Data((signature.base64EncodedString() + "\n").utf8).write(to: output)
    print("✓ Signed \(output.path)")

default:
    fail("usage: update-key.swift keygen | public-key | sign <file.dmg>")
}
