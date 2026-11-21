//
//  PortScanSession.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Observation

struct PortResult: Identifiable, Hashable {
    var id: UInt16 { port }
    let port: UInt16
    let service: String
    let detail: String?
    let latency: TimeInterval
}

/// A TCP port scan of one device. Results stream in as ports answer.
@MainActor
@Observable
final class PortScanSession {
    let deviceID: UUID
    var address: IPAddress?
    var preset: PortPreset = .common
    var customPorts = "1-1024, 3389, 5900, 8000-8100"
    var timeoutMilliseconds: Double = 800
    var parallelProbes = 192

    private(set) var isRunning = false
    private(set) var scanned = 0
    private(set) var total = 0
    private(set) var results: [PortResult] = []
    private(set) var closedCount = 0
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?
    private(set) var scannedAddress: IPAddress?
    var errorMessage: String?

    @ObservationIgnored var onOpenPort: ((UUID, UInt16) -> Void)?
    @ObservationIgnored private var cancel: CancelToken?

    init(deviceID: UUID, address: IPAddress?) {
        self.deviceID = deviceID
        self.address = address
    }

    var progress: Double { total == 0 ? 0 : Double(scanned) / Double(total) }

    var elapsed: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    func start() {
        guard !isRunning, let address else { return }
        errorMessage = nil
        let ports: [UInt16]
        do {
            ports = try preset.ports ?? PortCatalog.parse(customPorts)
        } catch {
            errorMessage = String(localized: "Enter ports like “22, 80, 443, 8000-8100”.")
            return
        }

        let token = CancelToken()
        cancel = token
        isRunning = true
        results = []
        scanned = 0
        closedCount = 0
        total = ports.count
        startedAt = Date()
        finishedAt = nil
        scannedAddress = address

        let timeout = timeoutMilliseconds / 1000
        let concurrency = parallelProbes
        let deviceID = deviceID
        let owner = WeakReference(self)
        Task.detached(priority: .userInitiated) {
            await Blocking.run {
                let probes = ports.map { ProbeTarget(address: address, port: $0) }
                var done = 0
                var closed = 0
                var batch: [PortResult] = []
                var lastFlush = CFAbsoluteTimeGetCurrent()

                func flush() {
                    let newResults = batch
                    let doneNow = done, closedNow = closed
                    batch.removeAll()
                    lastFlush = CFAbsoluteTimeGetCurrent()
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self = owner.value else { return }
                            self.scanned = doneNow
                            self.closedCount = closedNow
                            if !newResults.isEmpty {
                                self.results.append(contentsOf: newResults)
                                self.results.sort { $0.port < $1.port }
                                for result in newResults { self.onOpenPort?(deviceID, result.port) }
                            }
                        }
                    }
                }

                TCPProber.run(probes, timeout: timeout, concurrency: concurrency, cancel: token) { probe, state, latency in
                    done += 1
                    switch state {
                    case .open:
                        batch.append(PortResult(port: probe.port, service: PortCatalog.serviceName(for: probe.port),
                                                detail: PortCatalog.serviceDescription(for: probe.port), latency: latency))
                        flush()
                    case .closed:
                        closed += 1
                    case .filtered:
                        break
                    }
                    if CFAbsoluteTimeGetCurrent() - lastFlush > 0.1 { flush() }
                }
                flush()
            }
            await MainActor.run {
                guard let self = owner.value else { return }
                self.isRunning = false
                self.finishedAt = Date()
            }
        }
    }

    func stop() {
        cancel?.cancel()
    }
}

final class WeakReference<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
