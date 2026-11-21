//
//  Concurrency.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin

/// Thread-safe cancellation flag shared between the UI and blocking socket loops.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

/// Minimal lock-protected box.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    @discardableResult
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    var current: Value { withLock { $0 } }
}

enum Blocking {
    /// Runs blocking socket work off the Swift concurrency pool.
    static func run<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: work())
            }
            thread.qualityOfService = .userInitiated
            thread.stackSize = 1 << 20
            thread.start()
        }
    }

    /// Calls `body` for every item using up to `width` dedicated threads, returning when all are done.
    /// With a `deadline` (seconds) it stops waiting after that long; straggling threads finish on their own.
    static func forEach<T>(_ items: [T], width: Int, cancel: CancelToken, deadline: TimeInterval? = nil, _ body: @escaping (T) -> Void) {
        guard !items.isEmpty else { return }
        let cursor = Locked(0)
        let group = DispatchGroup()
        for _ in 0..<max(1, min(width, items.count)) {
            group.enter()
            let thread = Thread {
                while !cancel.isCancelled {
                    let index: Int = cursor.withLock { value in
                        defer { value += 1 }
                        return value
                    }
                    guard index < items.count else { break }
                    body(items[index])
                }
                group.leave()
            }
            thread.qualityOfService = .userInitiated
            thread.stackSize = 512 * 1024
            thread.start()
        }
        if let deadline {
            _ = group.wait(timeout: .now() + deadline)
        } else {
            group.wait()
        }
    }

    /// Sleeps in small slices so cancellation is honoured promptly.
    static func sleep(_ seconds: TimeInterval, cancel: CancelToken) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !cancel.isCancelled {
            Thread.sleep(forTimeInterval: min(0.05, max(0, deadline.timeIntervalSinceNow)))
        }
    }
}

enum SystemLimits {
    /// Port scans keep hundreds of sockets in flight; the default soft limit is 256.
    static func raiseFileDescriptorLimit(to desired: rlim_t = 8192) {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return }
        let target = min(limit.rlim_max, desired)
        if limit.rlim_cur < target {
            limit.rlim_cur = target
            setrlimit(RLIMIT_NOFILE, &limit)
        }
    }
}

extension Socket {
    static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    static func setOption(_ fd: Int32, _ level: Int32, _ name: Int32, _ value: Int32) {
        var v = value
        setsockopt(fd, level, name, &v, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Waits until `fd` is readable or the timeout expires.
    static func waitReadable(_ fd: Int32, timeout: TimeInterval) -> Bool {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ms = Int32(max(0, min(timeout, 1)) * 1000)
        return poll(&pfd, 1, ms) > 0
    }

    @discardableResult
    static func send(_ fd: Int32, _ bytes: [UInt8], to address: IPAddress, port: UInt16) -> Int32 {
        let rc = address.withSocketAddress(port: port) { sa, len in
            bytes.withUnsafeBytes { sendto(fd, $0.baseAddress, bytes.count, 0, sa, len) }
        }
        return rc < 0 ? errno : 0
    }

    /// Receives one datagram. Returns nil when nothing is pending.
    static func receive(_ fd: Int32, into buffer: inout [UInt8]) -> (count: Int, from: IPAddress)? {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let n = buffer.withUnsafeMutableBytes { buf in
            withUnsafeMutablePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, buf.baseAddress, buf.count, 0, $0, &length)
                }
            }
        }
        guard n > 0 else { return nil }
        let from = withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { IPAddress(socketAddress: $0) }
        }
        guard let from else { return nil }
        return (n, from)
    }
}

/// Namespace for small BSD socket helpers.
enum Socket {}
