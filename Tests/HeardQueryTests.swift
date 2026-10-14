import Foundation

@main struct HeardQueryTests {
    static func main() throws {
        func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
        let now = Date(timeIntervalSince1970: 1700001000)
        let id = "01234567-89AB-CDEF-0123-456789ABCDEF"
        var book = HeardBook(); book.begin(own: "N4EAC", now: now.addingTimeInterval(-3600))
        book.observe(call: "K1ABC-7", snr: -8.4, time: now.addingTimeInterval(-120), now: now)
        book.observe(call: "K1ABC", snr: -9, time: now.addingTimeInterval(-130), now: now)
        book.observe(call: "W0XYZ", snr: nil, time: now.addingTimeInterval(-60), now: now)
        book.observe(call: "N4EAC", snr: 1, time: now, now: now)
        book.observe(call: "STALE1", snr: 0, time: now.addingTimeInterval(-3601), now: now)
        check(book.select(query: nil, requester: "W0XYZ", now: now) == [HeardItem(call: "K1ABC-7", age: 120, signal: -84)], "Latest per base, excludes own/requester/stale")
        check(book.select(query: "K1ABC-0", requester: "TEST1", now: now).first?.call == "K1ABC", "Exact SSID zero")
        check(book.select(query: "K1ABC", requester: "TEST1", now: now).first?.call == "K1ABC-7", "Base callsign query")
        check(book.select(query: "N9ZZZ", requester: "TEST1", now: now).isEmpty, "Not heard")
        book.observe(call: "N4EAC-7", snr: 1, time: now, now: now)
        check(book.select(query: "N4EAC-7", requester: "TEST1", now: now).first?.call == "N4EAC-7", "Different SSID station can be queried")

        book.observe(call: "W0XYZ", snr: nil, time: now.addingTimeInterval(-59), now: now, packetFallback: true)
        book.observe(call: "W0XYZ", snr: -3.2, time: now.addingTimeInterval(-60), now: now)
        check(book.select(query: "W0XYZ", requester: "TEST1", now: now).first?.signal == -32, "Metadata upgrades unknown SNR")
        let request = try HeardMessage(k: "request", id: id).encoded()
        var receiver = HeardSession(), requester = HeardSession()
        _ = try requester.receive(request, source: "TEST1", destination: "QST", own: "TEST1", outgoing: true, enabled: false, now: now, delay: 2)
        _ = try receiver.receive(request, source: "TEST1", destination: "QST", own: "N4EAC", outgoing: false, enabled: true, now: now, delay: 12)
        check(try receiver.receive(request, source: "TEST1", destination: "QST", own: "N4EAC", outgoing: false, enabled: true, now: now, delay: 12) == nil, "Duplicate suppression")
        check(try receiver.reply(now: now.addingTimeInterval(11), history: book) == nil, "Reply delay")
        let reply = try receiver.reply(now: now.addingTimeInterval(12), history: book)!
        check(try requester.receive(reply.1, source: "N4EAC", destination: "TEST1", own: "TEST1", outgoing: false, enabled: false, now: now.addingTimeInterval(12), delay: 2) != nil, "Correlated broadcast reply")
        check(try requester.receive(reply.1, source: "W1AAA", destination: "TEST1", own: "TEST1", outgoing: false, enabled: false, now: now.addingTimeInterval(13), delay: 2) != nil, "Multiple stations can answer QST")
        var stranger = HeardSession()
        check(try stranger.receive(reply.1, source: "N4EAC", destination: "TEST1", own: "TEST1", outgoing: false, enabled: true, now: now, delay: 2) == nil, "No unsolicited reply")
        let second = try HeardMessage(k: "request", id: "11234567-89AB-CDEF-0123-456789ABCDEF", q: "K1ABC-0").encoded()
        _ = try receiver.receive(second, source: "TEST1", destination: "QST", own: "N4EAC", outgoing: false, enabled: true, now: now.addingTimeInterval(20), delay: 2)
        check(receiver.pending.isEmpty, "One reply per requester per minute")
        _ = try receiver.receive(second, source: "TEST2", destination: "QST", own: "N4EAC", outgoing: false, enabled: true, now: now, delay: 2)
        receiver.clearPending(); check(receiver.pending.isEmpty, "Disable cancels pending")
        _ = try receiver.receive(second, source: "TEST3", destination: "QST", own: "N4EAC", outgoing: false, enabled: true, now: now, delay: 2)
        check(try receiver.reply(now: now.addingTimeInterval(121), history: book) == nil, "Busy requests expire")
        let fixtures = [request, second, reply.1, try HeardMessage(k: "reply", id: id, q: "N9ZZZ", h: []).encoded()]
        if CommandLine.arguments.count > 1 { try fixtures.joined(separator: "\n").write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8) }
        if CommandLine.arguments.count > 2 { for wire in try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8).split(separator: "\n") { _ = try HeardMessage.decode(String(wire)) } }
        print("PASS: Heard history, SSIDs, SNR, correlation, multi-station replies, rate limits, delays and expiry")
    }
}
