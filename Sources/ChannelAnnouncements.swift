import Foundation
import Combine

struct ChannelAnnouncementState {
    var enabled = false
    var intervalMinutes = 10
    var nextDue: Date?
    var status = "Announcements off"
}

@MainActor final class ChannelAnnouncements: ObservableObject {
    @Published private(set) var states: [String: ChannelAnnouncementState] = [:]
    var canSend: () -> Bool = { false }
    var hasParticipant: (String, Date) -> Bool = { _, _ in false }
    var transmit: (String) throws -> Void = { _ in }
    private var running = false
    private var timer: Task<Void, Never>?
    func configure(room: String, enabled: Bool, intervalMinutes: Int, now: Date = Date()) throws {
        guard try RoomEnvelope.channel(room) == room, (1...60).contains(intervalMinutes) else {
            throw RadioError.invalid("Select a channel and an announcement interval from 1 to 60 minutes.")
        }
        states[room] = ChannelAnnouncementState(enabled: enabled, intervalMinutes: intervalMinutes,
            nextDue: enabled && running ? now.addingTimeInterval(Double(intervalMinutes * 60)) : nil,
            status: enabled ? (running ? "Announcement scheduled" : "Armed · waiting for modem") : "Announcements off")
        if enabled && hasParticipant(room, now) { participantHeard(in: room) }
    }
    func start(now: Date = Date()) {
        stop(); running = true
        for room in Array(states.keys) where states[room]?.enabled == true {
            if hasParticipant(room, now) { participantHeard(in: room) }
            else {
                states[room]?.nextDue = now.addingTimeInterval(Double(states[room]!.intervalMinutes * 60))
                states[room]?.status = "Announcement scheduled"
            }
        }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.tick(now: Date())
            }
        }
    }
    func tick(now: Date) {
        guard running else { return }
        let dueRooms = states.keys.filter { states[$0]?.enabled == true && (states[$0]?.nextDue ?? .distantFuture) <= now }
            .sorted { (states[$0]!.nextDue!, $0) < (states[$1]!.nextDue!, $1) }
        for room in dueRooms {
            if hasParticipant(room, now) { participantHeard(in: room); continue }
            guard canSend() else { states[room]?.status = "Deferred · modem busy or audio unavailable"; return }
            do { try transmit(room); states[room]?.status = "Channel announcement submitted" }
            catch { states[room]?.status = "Announcement failed: " + error.localizedDescription }
            states[room]?.nextDue = now.addingTimeInterval(Double(states[room]!.intervalMinutes * 60))
            // One per tick, with no catch-up burst after sleep or a busy channel.
            return
        }
    }
    func participantHeard(in room: String) {
        guard states[room]?.enabled == true else { return }
        states[room]?.enabled = false; states[room]?.nextDue = nil
        states[room]?.status = "Stopped · another station joined or sent a message"
    }
    func left(_ room: String) { states.removeValue(forKey: room) }
    func stop() {
        running = false; timer?.cancel(); timer = nil
        for room in Array(states.keys) where states[room]?.enabled == true {
            states[room]?.nextDue = nil; states[room]?.status = "Paused · modem offline"
        }
    }
}
