import Foundation
import Combine

struct BeaconSettings: Codable, Equatable {
    var enabled = false
    var intervalMinutes = 5
    func validate(station: StationSettings) throws {
        guard (1...60).contains(intervalMinutes) else { throw RadioError.invalid("Choose a beacon interval from 1 to 60 minutes.") }
        if enabled { _ = try message(station: station, softwareVersion: "validation") }
    }
    func message(station: StationSettings, softwareVersion: String) throws -> String {
        try station.validate()
        let grid = station.locator.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard grid.range(of: "^[A-R]{2}[0-9]{2}(?:[A-X]{2}(?:[0-9]{2})?)?$", options: .regularExpression) != nil else {
            throw RadioError.invalid("Enter a valid 4, 6 or 8-character Maidenhead grid before transmitting a beacon.")
        }
        let text = "BEACON \(PacketAddress.canonical(station.callsign)) \(grid) QSO73 v\(softwareVersion)"
        guard text.utf8.count <= RadioPacket.maxTextBytes else { throw RadioError.invalid("Beacon exceeds the packet message limit.") }
        return text
    }
}

@MainActor final class BeaconController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var nextDue: Date?
    @Published private(set) var status = "Beacon off"
    @Published private(set) var message = ""
    @Published private(set) var submittedCount = 0
    var canSend: () -> Bool = { false }
    var transmit: (String) throws -> Void = { _ in }
    private var interval: TimeInterval = 300
    private var timer: Task<Void, Never>?

    func configure(_ settings: BeaconSettings, station: StationSettings, softwareVersion: String) throws {
        try settings.validate(station: station)
        let text = settings.enabled ? try settings.message(station: station, softwareVersion: softwareVersion) : ""
        stop()
        enabled = settings.enabled; interval = TimeInterval(settings.intervalMinutes * 60); message = text
        status = enabled ? "Beacon armed · waiting for modem" : "Beacon off"
    }
    func start(now: Date = Date()) {
        guard enabled else { return }
        timer?.cancel()
        nextDue = now.addingTimeInterval(interval)
        status = "Beacon scheduled"
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.tick(now: Date())
            }
        }
    }
    func tick(now: Date) {
        guard enabled, let due = nextDue, now >= due else { return }
        guard canSend() else { status = "Beacon deferred · modem busy or audio unavailable"; return }
        submit(now: now)
    }
    func sendNow(now: Date = Date()) {
        guard enabled, nextDue != nil else { status = "Enable the beacon and start the modem first"; return }
        nextDue = now
        tick(now: now)
    }
    private func submit(now: Date) {
        do {
            try transmit(message)
            submittedCount += 1
            status = "Beacon submitted to QST"
            // Never catch up with a burst after sleep or a busy channel.
            nextDue = now.addingTimeInterval(interval)
        } catch {
            status = "Beacon failed: " + error.localizedDescription
            nextDue = now.addingTimeInterval(interval)
        }
    }
    func stop() {
        timer?.cancel(); timer = nil; nextDue = nil
        status = enabled ? "Beacon paused · modem offline" : "Beacon off"
    }
}
