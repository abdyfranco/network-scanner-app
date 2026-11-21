//
//  TCPProber.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin

enum PortState: Sendable {
    /// SYN/ACK received.
    case open
    /// RST received: the port is closed but the host is alive.
    case closed
    /// No answer, or unreachable.
    case filtered
}

struct ProbeTarget: Hashable, Sendable {
    let address: IPAddress
    let port: UInt16
}

/// Non-blocking `connect()` scanner multiplexed with `poll()`: hundreds of probes in flight on one thread.
enum TCPProber {
    static func run(_ targets: [ProbeTarget], timeout: TimeInterval, concurrency: Int, cancel: CancelToken,
                    onResult: (ProbeTarget, PortState, TimeInterval) -> Void) {
        struct Pending {
            let fd: Int32
            let target: ProbeTarget
            let start: CFAbsoluteTime
        }

        let limit = max(1, concurrency)
        var pending: [Pending] = []
        pending.reserveCapacity(limit)
        var next = 0

        while !cancel.isCancelled, next < targets.count || !pending.isEmpty {
            // Fill the window.
            while pending.count < limit, next < targets.count, !cancel.isCancelled {
                let target = targets[next]
                let fd = socket(target.address.family, SOCK_STREAM, IPPROTO_TCP)
                if fd < 0 {
                    if (errno == EMFILE || errno == ENFILE), !pending.isEmpty { break }
                    next += 1
                    onResult(target, .filtered, 0)
                    continue
                }
                next += 1
                Socket.setNonBlocking(fd)
                Socket.setOption(fd, SOL_SOCKET, SO_NOSIGPIPE, 1)

                let start = CFAbsoluteTimeGetCurrent()
                let rc = target.address.withSocketAddress(port: target.port) { connect(fd, $0, $1) }
                if rc == 0 {
                    closeWithReset(fd)
                    onResult(target, .open, CFAbsoluteTimeGetCurrent() - start)
                    continue
                }
                let err = errno
                if err == EINPROGRESS {
                    pending.append(Pending(fd: fd, target: target, start: start))
                } else {
                    close(fd)
                    onResult(target, err == ECONNREFUSED ? .closed : .filtered, CFAbsoluteTimeGetCurrent() - start)
                }
            }

            guard !pending.isEmpty else { continue }
            var pollSet = pending.map { pollfd(fd: $0.fd, events: Int16(POLLOUT), revents: 0) }
            _ = poll(&pollSet, nfds_t(pollSet.count), 20)

            let now = CFAbsoluteTimeGetCurrent()
            var stillPending: [Pending] = []
            stillPending.reserveCapacity(pending.count)
            for (i, probe) in pending.enumerated() {
                if pollSet[i].revents != 0 {
                    var socketError: Int32 = 0
                    var length = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(probe.fd, SOL_SOCKET, SO_ERROR, &socketError, &length)
                    let state: PortState = socketError == 0 ? .open : (socketError == ECONNREFUSED ? .closed : .filtered)
                    if state == .open { closeWithReset(probe.fd) } else { close(probe.fd) }
                    onResult(probe.target, state, now - probe.start)
                } else if now - probe.start >= timeout {
                    close(probe.fd)
                    onResult(probe.target, .filtered, now - probe.start)
                } else {
                    stillPending.append(probe)
                }
            }
            pending = stillPending
        }

        for probe in pending { close(probe.fd) }
    }

    /// Avoids leaving thousands of sockets in TIME_WAIT during large scans.
    private static func closeWithReset(_ fd: Int32) {
        var lingerOption = linger(l_onoff: 1, l_linger: 0)
        setsockopt(fd, SOL_SOCKET, SO_LINGER, &lingerOption, socklen_t(MemoryLayout<linger>.size))
        close(fd)
    }
}
