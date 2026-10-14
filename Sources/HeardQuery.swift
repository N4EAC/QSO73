import Foundation

struct HeardItem: Codable, Equatable {
    let call: String
    let age: Int
    let signal: Int?
    init(call: String, age: Int, signal: Int?) { self.call = call; self.age = age; self.signal = signal }
    init(from decoder: Decoder) throws { var c = try decoder.unkeyedContainer(); call = try c.decode(String.self); age = try c.decode(Int.self); signal = try c.decodeIfPresent(Int.self); guard c.isAtEnd else { throw RadioError.invalid("Invalid heard item.") } }
    func encode(to encoder: Encoder) throws { var c = encoder.unkeyedContainer(); try c.encode(call); try c.encode(age); try c.encode(signal) }
}
struct HeardMessage: Codable {
    static let prefix = "~Q73H:"
    var v = 1
    let k: String
    let id: String
    var q: String? = nil
    var h: [HeardItem]? = nil
    var w = 60
    static func base(_ call: String) -> String { PacketAddress.canonical(call).components(separatedBy: "-").first ?? "" }
    static func matches(_ call: String, _ query: String) -> Bool { query.contains("-") ? PacketAddress.canonical(call) == PacketAddress.canonical(query) : base(call) == base(query) }
    func validate() throws {
        guard v == 1, w == 60, UUID(uuidString: id) != nil, ["request", "reply"].contains(k) else { throw RadioError.invalid("Invalid Heard query.") }
        if let q { guard StationSettings.validCallsign(q), q == q.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) else { throw RadioError.invalid("Enter a valid callsign, optionally with an SSID.") } }
        if k == "request" { guard h == nil else { throw RadioError.invalid("Invalid Heard request fields.") } }
        else {
            guard let h, h.count <= (q == nil ? 3 : 1), Set(h.map(\.call)).count == h.count,
                  h.allSatisfy({ item in StationSettings.validCallsign(item.call) && PacketAddress.canonical(item.call) == item.call && (0...3600).contains(item.age) && (item.signal.map { (-2000...2000).contains($0) } ?? true) && (q.map { Self.matches(item.call, $0) } ?? true) }) else { throw RadioError.invalid("Invalid Heard response.") }
        }
    }
    func encoded() throws -> String {
        try validate(); let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let wire = Self.prefix + String(decoding: try e.encode(self), as: UTF8.self)
        guard wire.utf8.count <= 200 else { throw RadioError.invalid("Heard packet exceeds 200 bytes.") }; return wire
    }
    static func decode(_ text: String) throws -> Self {
        guard text.hasPrefix(prefix), text.utf8.count <= 200 else { throw RadioError.invalid("Invalid Heard packet.") }
        let event = try JSONDecoder().decode(Self.self, from: Data(text.dropFirst(prefix.count).utf8)); try event.validate(); return event
    }
    var readable: String {
        if k == "request" { return q.map { "HEARD query: have you heard \($0) in the last 60 min?" } ?? "HEARD query: recent callsigns (last 60 min)" }
        guard let h, !h.isEmpty else { return q.map { "HEARD reply: not heard \($0) in the last 60 min of this session" } ?? "HEARD reply: no other recent callsigns in this session" }
        return "HEARD reply: " + h.map { item in
            let age = item.age < 60 ? "\(item.age)s" : "\(item.age / 60)m"
            let signal = item.signal.map { String(format: ", SNR %.1f dB", Double($0) / 10) } ?? ", SNR unavailable"
            return "\(item.call) (\(age) ago\(signal))"
        }.joined(separator: "; ")
    }
}
struct HeardBook {
    struct Observation { let call: String; let time: Date; let signal: Int? }
    private(set) var entries: [String: Observation] = [:]
    private var start = Date.distantFuture
    private var own = ""
    mutating func begin(own: String, now: Date) { entries = [:]; start = now; self.own = own }
    mutating func clear() { entries = [:]; start = .distantFuture; own = "" }
    mutating func observe(call: String, snr: Double?, time: Date, now: Date, packetFallback: Bool = false) {
        let call = PacketAddress.canonical(call), age = now.timeIntervalSince(time)
        guard StationSettings.validCallsign(call), call != PacketAddress.canonical(own), time >= start, age.isFinite, age >= -5, age <= 3600 else { return }
        entries = entries.filter { now.timeIntervalSince($0.value.time) <= 3600 }
        if let old = entries[call] {
            if packetFallback && abs(time.timeIntervalSince(old.time)) <= 5 { return }
            if time < old.time && !(old.signal == nil && snr != nil && abs(time.timeIntervalSince(old.time)) <= 5) { return }
        }
        let signal = snr.flatMap { $0.isFinite && abs($0) <= 200 ? Int(($0 * 10).rounded()) : nil }
        entries[call] = Observation(call: call, time: time, signal: signal)
        if entries.count > 256, let oldest = entries.min(by: { $0.value.time < $1.value.time })?.key { entries[oldest] = nil }
    }
    func select(query: String?, requester: String, now: Date) -> [HeardItem] {
        var bases = Set<String>()
        return entries.values.sorted { $0.time == $1.time ? $0.call < $1.call : $0.time > $1.time }.compactMap { item in
            let age = now.timeIntervalSince(item.time)
            guard age.isFinite, age >= -5, age <= 3600 else { return nil }
            if let query { guard HeardMessage.matches(item.call, query) else { return nil } }
            else { guard HeardMessage.base(item.call) != HeardMessage.base(requester), bases.insert(HeardMessage.base(item.call)).inserted else { return nil } }
            return HeardItem(call: item.call, age: max(0, Int(age)), signal: item.signal)
        }.prefix(query == nil ? 3 : 1).map { $0 }
    }
}
struct HeardSession {
    struct Pending { let source: String; let id: String; let query: String?; let received: Date; let due: Date }
    struct Requested { let time: Date; let query: String?; let destination: String }
    private(set) var pending: [Pending] = []
    private var requested: [String: Requested] = [:]
    private var replied: [String: Date] = [:]
    private var seen = Set<String>(), order: [String] = []
    mutating func clearPending() { pending = [] }
    mutating func reset() { self = HeardSession() }
    mutating func receive(_ wire: String, source: String, destination: String, own: String, outgoing: Bool, enabled: Bool, now: Date, delay: Double) throws -> String? {
        let event = try HeardMessage.decode(wire)
        guard StationSettings.validCallsign(source) else { throw RadioError.invalid("Invalid Heard sender.") }
        let key = source + ":" + event.k + ":" + event.id
        guard !seen.contains(key) else { return nil }
        requested = requested.filter { now.timeIntervalSince($0.value.time) <= 600 }
        if event.k == "reply" && !outgoing {
            guard destination == own, let request = requested[event.id], request.query == event.q,
                  ["QST", "CQ", "ALL"].contains(request.destination) || source == request.destination else { return nil }
        } else if event.k == "request" {
            guard outgoing || destination == own || ["QST", "CQ", "ALL"].contains(destination) else { return nil }
            if outgoing {
                if requested.count >= 16, let oldest = requested.min(by: { $0.value.time < $1.value.time })?.key { requested[oldest] = nil }
                requested[event.id] = Requested(time: now, query: event.q, destination: destination)
            } else if enabled && source != own && pending.count < 8 && (replied[source].map { now.timeIntervalSince($0) >= 60 } ?? true) {
                pending.append(Pending(source: source, id: event.id, query: event.q, received: now, due: now.addingTimeInterval(max(2, min(24, delay)))))
            }
        }
        seen.insert(key); order.append(key); if order.count > 512 { seen.remove(order.removeFirst()) }
        return event.readable
    }
    mutating func reply(now: Date, history: HeardBook) throws -> (String, String)? {
        let replies = replied
        pending.removeAll { now.timeIntervalSince($0.received) > 120 || (replies[$0.source].map { now.timeIntervalSince($0) < 60 } ?? false) }
        guard let index = pending.firstIndex(where: { now >= $0.due }) else { return nil }
        let item = pending[index]
        var event = HeardMessage(k: "reply", id: item.id, q: item.query, h: history.select(query: item.query, requester: item.source, now: now))
        while (try? event.encoded()) == nil, event.h?.isEmpty == false { event.h?.removeLast() }
        let wire = try event.encoded()
        pending.remove(at: index); replied[item.source] = now
        if replied.count > 256, let oldest = replied.min(by: { $0.value < $1.value })?.key { replied[oldest] = nil }
        return (item.source, wire)
    }
}
