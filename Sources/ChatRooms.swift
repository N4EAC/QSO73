import Foundation
import Combine

struct ChatEntry: Identifiable, Codable {
    var id = UUID()
    var time = Date()
    let direction: String
    var text: String
    var conversation = "radio"
    var source: String? = nil
    var destination: String? = nil
}

// QSO73's versioned application protocol remains inside ordinary AX.25 UI packets.
struct RoomEnvelope: Codable, Equatable {
    var v = 1
    let k: String
    let r: String
    let t: String
    let id: String
    static let prefix = "~Q73:"
    init(kind: String, room: String, text: String = "", id: String = UUID().uuidString) {
        k = kind; r = room; t = text; self.id = id
    }
    static func channel(_ value: String) throws -> String {
        let name = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = name.hasPrefix("#") ? name : "#" + name
        guard (2...21).contains(normalized.utf8.count), normalized.dropFirst().allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw RadioError.invalid("Use a channel name of 1–20 letters, numbers, hyphens or underscores.")
        }
        return normalized
    }
    func validate() throws {
        guard v == 1, UUID(uuidString: id) != nil, ["msg", "join", "leave", "topic", "announce"].contains(k), !t.contains(where: { $0.isNewline || $0 == "\0" }) else { throw RadioError.invalid("Invalid QSO73 conversation packet.") }
        if r.hasPrefix("#") { guard try Self.channel(r) == r else { throw RadioError.invalid("Invalid channel.") } }
        else {
            guard k == "msg", StationSettings.validCallsign(r), PacketAddress.canonical(r) == r,
                  !["QST", "CQ", "ALL"].contains(r) else { throw RadioError.invalid("Enter a station callsign for a direct conversation.") }
        }
        guard k != "msg" || !t.trimmingCharacters(in: .whitespaces).isEmpty else { throw RadioError.invalid("Enter a message.") }
        guard !["join", "leave"].contains(k) || t.isEmpty else { throw RadioError.invalid("Invalid membership event.") }
    }
    func encoded() throws -> String {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let wire = Self.prefix + String(decoding: try encoder.encode(self), as: UTF8.self)
        guard wire.utf8.count <= RadioPacket.maxTextBytes else { throw RadioError.invalid("This conversation message is too long after adding routing data. Shorten the message or topic.") }
        return wire
    }
    static func decode(_ wire: String) throws -> Self {
        guard wire.hasPrefix(prefix), wire.utf8.count <= RadioPacket.maxTextBytes else { throw RadioError.invalid("Invalid conversation packet.") }
        let value = try JSONDecoder().decode(Self.self, from: Data(wire.dropFirst(prefix.count).utf8))
        try value.validate(); return value
    }
}

@MainActor final class ChatRooms: ObservableObject {
    @Published var selected = "radio" { didSet { unread[selected] = 0 } }
    @Published private(set) var joined: Set<String> = []
    @Published private(set) var discovered: Set<String> = []
    @Published private(set) var directs: Set<String> = []
    @Published private(set) var topics: [String: String] = [:]
    @Published private(set) var unread: [String: Int] = [:]
    @Published private(set) var members: [String: [String: Date]] = [:]
    private var participants: [String: [String: Date]] = [:]
    var onParticipantHeard: (String) -> Void = { _ in }
    var onLeave: (String) -> Void = { _ in }
    func hasParticipant(in room: String, now: Date) -> Bool {
        (participants[room] ?? [:]).values.contains { now.timeIntervalSince($0) <= 600 }
    }
    private var seen: Set<String> = []
    private var seenOrder: [String] = []
    private let defaults: UserDefaults?
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        joined = Set((defaults?.stringArray(forKey: "qso73.channels.v1") ?? []).compactMap { try? RoomEnvelope.channel($0) })
        discovered = joined
    }
    var conversations: [String] { ["radio"] + discovered.sorted() + directs.sorted() }
    func join(_ name: String) throws {
        let room = try RoomEnvelope.channel(name)
        joined.insert(room); discovered.insert(room); selected = room
        defaults?.set(joined.sorted(), forKey: "qso73.channels.v1")
    }
    func leave(_ room: String) {
        onLeave(room)
        participants[room] = nil
        joined.remove(room); selected = "radio"
        defaults?.set(joined.sorted(), forKey: "qso73.channels.v1")
    }
    func direct(_ value: String) throws {
        let call = PacketAddress.canonical(value.trimmingCharacters(in: .whitespacesAndNewlines))
        try RoomEnvelope(kind: "msg", room: call, text: "check").validate()
        directs.insert(call); selected = call
    }
    func users(in room: String, local: String, now: Date) -> [String] {
        var calls = Set((members[room] ?? [:]).filter { now.timeIntervalSince($0.value) <= 600 }.keys)
        if joined.contains(room) { calls.insert(PacketAddress.canonical(local)) }
        return calls.sorted()
    }
    // Returns a readable entry, or nil for duplicate / unjoined / misaddressed packets.
    func route(_ original: ChatEntry, local: String, outgoing: Bool) throws -> ChatEntry? {
        guard original.text.hasPrefix(RoomEnvelope.prefix) else {
            if !outgoing && selected != "radio" { unread["radio", default: 0] += 1 }
            return original
        }
        let event = try RoomEnvelope.decode(original.text)
        let source = PacketAddress.canonical(original.source ?? "")
        let destination = PacketAddress.canonical(original.destination ?? "")
        let own = PacketAddress.canonical(local)
        guard StationSettings.validCallsign(source) else { throw RadioError.invalid("Missing conversation sender.") }
        let room: String
        if event.r.hasPrefix("#") {
            guard destination == "QST" else { throw RadioError.invalid("Channel packet must be broadcast.") }
            room = event.r
        } else {
            guard destination == event.r, outgoing || destination == own else { return nil }
            room = outgoing ? destination : source
        }
        let key = source + ":" + event.id
        guard !seen.contains(key) else { return nil }
        seen.insert(key); seenOrder.append(key)
        if seenOrder.count > 4000 { seen.remove(seenOrder.removeFirst()) }
        if room.hasPrefix("#") {
            discovered.insert(room)
            if event.k == "leave" { members[room]?[source] = nil; participants[room]?[source] = nil }
            else { members[room, default: [:]][source] = original.time }
            if event.k == "topic" { topics[room] = event.t }
            if event.k == "announce" && topics[room] == nil { topics[room] = event.t }
            if !outgoing && source != own && ["join", "msg"].contains(event.k) {
                participants[room, default: [:]][source] = original.time
                if joined.contains(room) { onParticipantHeard(room) }
            }
            guard joined.contains(room) || outgoing else { return nil }
        } else { directs.insert(room) }
        var entry = original; entry.conversation = room
        switch event.k {
        case "join": entry.text = "\(source) joined \(room)."
        case "leave": entry.text = "\(source) left \(room)."
        case "topic": entry.text = event.t.isEmpty ? "\(source) cleared the topic." : "\(source) set the topic: \(event.t)"
        case "announce": entry.text = "\(source) invites stations to \(room)" + (event.t.isEmpty ? "." : " · Topic: \(event.t)")
        default: entry.text = event.t
        }
        if !outgoing && room != selected { unread[room, default: 0] += 1 }
        return entry
    }
}
