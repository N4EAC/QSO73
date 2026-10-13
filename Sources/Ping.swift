import Foundation

struct PingMessage: Codable {
    static let prefix = "~Q73P:"
    var v = 1
    let k: String
    let id: String
    var call: String? = nil
    var grid: String? = nil
    var snr: Double? = nil
    func validate() throws {
        guard v == 1, UUID(uuidString: id) != nil, ["request", "reply"].contains(k) else { throw RadioError.invalid("Invalid PING packet.") }
        if k == "reply" {
            guard let call, StationSettings.validCallsign(call), PacketAddress.canonical(call) == call,
                  let grid, grid.range(of: "^[A-R]{2}[0-9]{2}(?:[A-X]{2}(?:[0-9]{2})?)?$", options: .regularExpression) != nil,
                  let snr, snr.isFinite else { throw RadioError.invalid("PING reply requires a callsign, grid and measured SNR.") }
        } else if call != nil || grid != nil || snr != nil { throw RadioError.invalid("Invalid PING request fields.") }
    }
    func encoded() throws -> String {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = Self.prefix + String(decoding: try encoder.encode(self), as: UTF8.self)
        guard text.utf8.count <= 200 else { throw RadioError.invalid("PING packet too long.") }; return text
    }
    static func decode(_ text: String) throws -> Self {
        guard text.hasPrefix(prefix), text.utf8.count <= 200 else { throw RadioError.invalid("Invalid PING packet.") }
        let value = try JSONDecoder().decode(Self.self, from: Data(text.dropFirst(prefix.count).utf8)); try value.validate(); return value
    }
}
struct PingSession {
    struct Pending { let source: String; let id: String; let received: Date }
    private(set) var pending: [Pending] = []
    private var seen: Set<String> = []; private var order: [String] = []
    private var requested: [String: Date] = [:]; private var replied: [String: Date] = [:]
    mutating func clearPending() { pending.removeAll() }
    mutating func receive(_ wire: String, source: String, destination: String, own: String, outgoing: Bool, enabled: Bool, now: Date) throws -> String? {
        let event = try PingMessage.decode(wire)
        guard StationSettings.validCallsign(source) else { throw RadioError.invalid("Invalid PING sender.") }
        let key = source + ":" + event.k + ":" + event.id
        guard !seen.contains(key) else { return nil }
        if event.k == "reply" {
            guard event.call == source, destination == (outgoing ? destination : own),
                  outgoing || requested[event.id].map({ now.timeIntervalSince($0) <= 180 }) == true else { return nil }
        } else {
            guard destination == own || ["QST", "CQ", "ALL"].contains(destination) || outgoing else { return nil }
            if outgoing { requested[event.id] = now; requested = requested.filter { now.timeIntervalSince($0.value) <= 180 } }
            else if enabled && source != own && pending.count < 16 && (replied[source].map { now.timeIntervalSince($0) >= 30 } ?? true) {
                pending.append(Pending(source: source, id: event.id, received: now))
            }
        }
        seen.insert(key); order.append(key); if order.count > 512 { seen.remove(order.removeFirst()) }
        return event.k == "request" ? "PING request" : String(format: "PING reply: %@ %@ · SNR %.1f dB (your request at this station)", event.call!, event.grid!, event.snr!)
    }
    mutating func reply(own: String, grid: String, now: Date, snr: (Pending) -> Double?) throws -> (String, String)? {
        let replyTimes = replied
        pending.removeAll { now.timeIntervalSince($0.received) > 30 || (replyTimes[$0.source].map { now.timeIntervalSince($0) < 30 } ?? false) }
        for (index, item) in pending.enumerated() {
            guard now.timeIntervalSince(item.received) >= 2, let signal = snr(item), signal.isFinite else { continue }
            let text = try PingMessage(k: "reply", id: item.id, call: own, grid: grid.uppercased(), snr: signal).encoded()
            pending.remove(at: index); replied[item.source] = now; return (item.source, text)
        }
        return nil
    }
}
