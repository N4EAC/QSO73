import Foundation

@main struct ChatRoomsTests {
    @MainActor static func main() throws {
        let a = ChatRooms(defaults: nil), b = ChatRooms(defaults: nil), observer = ChatRooms(defaults: nil)
        try a.join("#hf"); try b.join("#hf")
        func received(_ event: RoomEnvelope, from: String = "N4EAC", to: String = "QST", at: Date = Date()) throws -> ChatEntry {
            let packet = try RadioPacket.decode(RadioPacket(source: from, destination: to, text: event.encoded()).encode())
            let frames = KISSFramer.encode(try packet.encode())
            var framer = KISSFramer()
            let decoded = try RadioPacket.decode(framer.feed(frames)[0])
            return ChatEntry(time: at, direction: "\(from) → \(to)", text: decoded.text, source: decoded.source, destination: decoded.destination)
        }
        let message = RoomEnvelope(kind: "msg", room: "#hf", text: "Hello HF 👋")
        let entry = try received(message)
        guard try b.route(entry, local: "K1ABC", outgoing: false)?.text == "Hello HF 👋",
              try b.route(entry, local: "K1ABC", outgoing: false) == nil else { fatalError("Channel routing / duplicate suppression failed") }
        guard try observer.route(entry, local: "W1AW", outgoing: false) == nil, observer.discovered.contains("#hf") else { fatalError("Unjoined channel discovery failed") }
        b.selected = "radio"
        let next = try received(RoomEnvelope(kind: "msg", room: "#hf", text: "another"))
        _ = try b.route(next, local: "K1ABC", outgoing: false)
        guard b.unread["#hf"] == 1 else { fatalError("Unread count failed") }
        b.selected = "#hf"
        guard b.unread["#hf"] == 0 else { fatalError("Read clearing failed") }
        let topic = try received(RoomEnvelope(kind: "topic", room: "#hf", text: "40m net"))
        _ = try b.route(topic, local: "K1ABC", outgoing: false)
        guard b.topics["#hf"] == "40m net" else { fatalError("Topic failed") }
        let clear = try received(RoomEnvelope(kind: "topic", room: "#hf"))
        _ = try b.route(clear, local: "K1ABC", outgoing: false)
        guard b.topics["#hf"] == "" else { fatalError("Topic clearing failed") }
        let direct = try received(RoomEnvelope(kind: "msg", room: "K1ABC", text: "direct"), to: "K1ABC")
        guard try b.route(direct, local: "K1ABC", outgoing: false)?.conversation == "N4EAC",
              try observer.route(direct, local: "W1AW", outgoing: false) == nil else { fatalError("Direct routing failed") }
        guard try a.route(direct, local: "N4EAC", outgoing: true)?.conversation == "K1ABC" else { fatalError("Outgoing direct routing failed") }
        let now = Date()
        let old = try received(RoomEnvelope(kind: "join", room: "#hf"), from: "W1AW", at: now.addingTimeInterval(-601))
        _ = try b.route(old, local: "K1ABC", outgoing: false)
        guard !b.users(in: "#hf", local: "K1ABC", now: now).contains("W1AW"),
              b.users(in: "#hf", local: "K1ABC", now: now).contains("N4EAC") else { fatalError("User age failed") }
        _ = try b.route(received(RoomEnvelope(kind: "leave", room: "#hf")), local: "K1ABC", outgoing: false)
        guard !b.users(in: "#hf", local: "K1ABC", now: now).contains("N4EAC") else { fatalError("Leave failed") }
        let legacy = ChatEntry(direction: "N4EAC → QST", text: "CQ CQ")
        guard try b.route(legacy, local: "K1ABC", outgoing: false)?.conversation == "radio" else { fatalError("Legacy chat changed") }
        func rejects(_ action: () throws -> Void) { do { try action(); fatalError("Invalid data accepted") } catch {} }
        rejects { _ = try RoomEnvelope.channel("#bad name") }
        rejects { _ = try RoomEnvelope(kind: "msg", room: "#hf", text: String(repeating: "é", count: 200)).encoded() }
        rejects { _ = try RoomEnvelope(kind: "join", room: "K1ABC").encoded() }
        rejects { _ = try RoomEnvelope(kind: "msg", room: "#hf", text: "hello\nspoof").encoded() }
        rejects { _ = try b.route(received(RoomEnvelope(kind: "msg", room: "#hf", text: "bad destination"), to: "K1ABC"), local: "K1ABC", outgoing: false) }
        b.leave("#hf")
        guard !b.joined.contains("#hf"), b.selected == "radio" else { fatalError("Local leave failed") }
        print("PASS: two-station QSO73 channels, topics, direct routing, KISS/AX.25 round trips, unread counts, deduplication, membership expiry, malformed packets and legacy chat")
    }
}
