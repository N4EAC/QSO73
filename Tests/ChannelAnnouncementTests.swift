import Foundation

@main struct ChannelAnnouncementTests {
    @MainActor static func main() throws {
        let rooms = ChatRooms(defaults: nil)
        let controller = ChannelAnnouncements()
        let start = Date(timeIntervalSince1970: 1000)
        var ready = false, sent: [String] = []
        controller.canSend = { ready }
        controller.hasParticipant = { room, now in rooms.hasParticipant(in: room, now: now) }
        controller.transmit = { sent.append($0) }
        rooms.onParticipantHeard = { controller.participantHeard(in: $0) }
        rooms.onLeave = { controller.left($0) }
        try rooms.join("#hf")
        try controller.configure(room: "#hf", enabled: true, intervalMinutes: 1, now: start)
        controller.tick(now: start.addingTimeInterval(100))
        guard sent.isEmpty, controller.states["#hf"]?.nextDue == nil else { fatalError("Offline transmission") }
        controller.start(now: start)
        ready = true; controller.tick(now: start.addingTimeInterval(59))
        guard sent.isEmpty else { fatalError("Early announcement") }
        ready = false; controller.tick(now: start.addingTimeInterval(60))
        guard sent.isEmpty, controller.states["#hf"]?.nextDue == start.addingTimeInterval(60) else { fatalError("Busy deferral") }
        ready = true; controller.tick(now: start.addingTimeInterval(65))
        guard sent == ["#hf"], controller.states["#hf"]?.nextDue == start.addingTimeInterval(125) else { fatalError("Submission timing") }
        controller.tick(now: start.addingTimeInterval(10000))
        guard sent.count == 2 else { fatalError("Wake burst") }
        func hear(_ kind: String, from: String = "K1ABC", room: String = "#hf", text: String = "") throws {
            let wire = try RoomEnvelope(kind: kind, room: room, text: text).encoded()
            _ = try rooms.route(ChatEntry(time: start.addingTimeInterval(10001), direction: "RX", text: wire, source: from, destination: "QST"), local: "N4EAC", outgoing: false)
        }
        try hear("announce", text: "Test topic")
        guard controller.states["#hf"]?.enabled == true, rooms.topics["#hf"] == "Test topic" else { fatalError("Another advertisement stopped announcements") }
        try hear("join", from: "N4EAC")
        guard controller.states["#hf"]?.enabled == true else { fatalError("Own echoed join stopped announcements") }
        try hear("join")
        guard controller.states["#hf"]?.enabled == false, controller.states["#hf"]?.nextDue == nil else { fatalError("Join did not stop announcements") }
        controller.tick(now: start.addingTimeInterval(20000))
        guard sent.count == 2 else { fatalError("Announcement after another station joined") }
        try controller.configure(room: "#hf", enabled: true, intervalMinutes: 1, now: start.addingTimeInterval(10002))
        guard controller.states["#hf"]?.enabled == false else { fatalError("Armed on an occupied channel") }
        try rooms.join("#other")
        try controller.configure(room: "#other", enabled: true, intervalMinutes: 1, now: start)
        try hear("msg", room: "#other", text: "hello")
        guard controller.states["#other"]?.enabled == false else { fatalError("Channel message did not stop announcements") }
        try rooms.join("#empty")
        try controller.configure(room: "#empty", enabled: true, intervalMinutes: 1, now: start)
        rooms.leave("#empty")
        guard controller.states["#empty"] == nil else { fatalError("Leaving did not remove timer") }
        try controller.configure(room: "#hf", enabled: true, intervalMinutes: 1, now: start.addingTimeInterval(20000))
        controller.stop(); controller.tick(now: start.addingTimeInterval(30000))
        guard sent.count == 2, controller.states["#hf"]?.nextDue == nil else { fatalError("Disconnected scheduler transmitted") }
        do { try controller.configure(room: "#hf", enabled: true, intervalMinutes: 0); fatalError("Invalid interval accepted") } catch {}
        print("PASS: channel announcement interval, idle deferral, wake behavior, discovery/topic, own-echo immunity, join/message stop, occupied channel guard, leave and disconnect")
    }
}
