//
//  update-key.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

// Signs release disk images so the app's updater can tell they come from you. The Ed25519 private
// key lives in your login Keychain, as the password of the item "Network Scanner update signing";
// the public key is compiled into the app (`Updater.signingKey`). Keep a copy of the private key
// somewhere safe: without it, installed copies won't accept any future update.
//   swift Scripts/update-key.swift generate          creates the key and prints its public key
//   swift Scripts/update-key.swift public-key        prints the public key
//   swift Scripts/update-key.swift sign <file.dmg>   writes <file.dmg>.sig
// The Keychain is read and written through /usr/bin/security, so it asks for access only once.
import CryptoKit
import Foundation

let service = "Network Scanner update signing"
let account = "ed25519"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

/// Runs /usr/bin/security; returns its standard output, or nil when it fails.
@discardableResult
func security(_ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func storedKey() -> Curve25519.Signing.PrivateKey {
    guard let text = security(["find-generic-password", "-s", service, "-a", account, "-w"]) else {
        fail("no “\(service)” item in the Keychain. Run `swift Scripts/update-key.swift generate` first.")
    }
    guard let raw = Data(base64Encoded: text), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("the “\(service)” Keychain item doesn't hold an Ed25519 key.")
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
case "generate":
    if security(["find-generic-password", "-s", service, "-a", account]) != nil {
        fail("the Keychain already holds a “\(service)” key. Delete it in Keychain Access first if you really want a new one; installed copies will then refuse updates signed with the new key.")
    }
    let key = Curve25519.Signing.PrivateKey()
    guard security(["add-generic-password", "-s", service, "-a", account, "-l", service,
                    "-D", "Ed25519 private key", "-w", key.rawRepresentation.base64EncodedString()]) != nil else {
        fail("couldn't add the key to the Keychain.")
    }
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "public-key":
    print(storedKey().publicKey.rawRepresentation.base64EncodedString())

case "sign":
    guard args.count == 3 else { fail("usage: update-key.swift sign <file.dmg>") }
    let key = storedKey()
    let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    guard appPublicKey() == publicKey else {
        fail("the Keychain key's public key (\(publicKey)) isn't the one in Updater.swift, so the app would reject this signature.")
    }
    let file = URL(fileURLWithPath: args[2])
    guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { fail("can't read \(file.path)") }
    let signature = try key.signature(for: data)
    let output = file.appendingPathExtension("sig")
    try Data((signature.base64EncodedString() + "\n").utf8).write(to: output)
    print("✓ Signed \(output.path)")

default:
    fail("usage: update-key.swift generate | public-key | sign <file.dmg>")
}
