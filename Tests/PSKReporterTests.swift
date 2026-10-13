import Foundation

@main struct PSKReporterTests {
    @MainActor static func main() throws {
        let now = Date(timeIntervalSince1970: 1700000010), since = now.addingTimeInterval(-10)
        func check(_ b: Bool, _ message: String) { if !b { fatalError(message) } }
        check(PSKReportQueue.rfFrequency(dial: 7105000, mode: "PKTUSB") == 7106500, "USB center offset")
        check(PSKReportQueue.rfFrequency(dial: 7105000, mode: "LSB") == 7103500, "LSB center offset")
        check(PSKReportQueue.rfFrequency(dial: 145500000, mode: "FM") == 145500000, "FM carrier frequency")
        check(PSKReportQueue.rfFrequency(dial: .nan, mode: "USB") == nil && PSKReportQueue.rfFrequency(dial: 7105000, mode: "CW") == nil, "Reject unknown CAT data")
        check(PSKReportQueue.grid("FM18FW") && !PSKReportQueue.grid("ZZ99"), "Grid validation")
        var queue = PSKReportQueue(); queue.clear(now: now, delay: 315)
        func add(_ call: String, frequency: UInt64 = 7106500, snr: Double = -12.5, received: Date = now) -> Bool {
            queue.add(call: call, own: "N4EAC-7", frequency: frequency, snr: snr, received: received, since: since, now: now)
        }
        check(!add("N4EAC") && !add("NOCALL") && !add("K1ABC", snr: .nan), "Exclude own/invalid receptions")
        check(!add("K1ABC", received: since.addingTimeInterval(-1)), "No historic replay")
        check(add("K1ABC-2") && !add("K1ABC-3"), "SSID normalization and five-minute dedup")
        check(add("K1ABC", frequency: 5400000000), "Five-byte frequency")
        check(queue.reports[0].call == "K1ABC" && queue.reports[0].snr == -13, "Measured SNR rounded and normalized")
        check(queue.due.timeIntervalSince(now) == 315, "Batch timer")
        let packet = try PSKReportQueue.encode(receiver: "N4EAC-7", grid: "FM18FW", software: "QSO73 test", reports: queue.reports, sequence: 9, domain: 42, time: 1700000020)
        try packet.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        var later = PSKReportQueue(); later.clear(now: now)
        check(later.add(call: "K1ABC", own: "N4EAC", frequency: 7106500, snr: 3, received: now, since: since, now: now), "First report")
        later.submitted(now: now)
        check(!later.add(call: "K1ABC", own: "N4EAC", frequency: 7106500, snr: 3, received: now.addingTimeInterval(100), since: since, now: now.addingTimeInterval(100)), "Dedup preserved after upload")
        let future = now.addingTimeInterval(301)
        check(later.add(call: "K1ABC", own: "N4EAC", frequency: 7106500, snr: 3, received: future, since: since, now: future), "Report after five minutes")
        for i in 0..<56 { _ = later.add(call: "K\(i)AA", own: "N4EAC", frequency: 7106500, snr: 0, received: future, since: since, now: future) }
        check(later.full && later.reports.count == 56, "Bounded batch")
        later.expire(now: future.addingTimeInterval(901)); check(later.reports.isEmpty, "Expire unsent stale receptions")
        let maximum = (0..<56).map { PSKReception(call: "AA0AAA", frequency: 7106500 + UInt64($0), snr: -20, time: 1700000010) }
        let maximumPacket = try PSKReportQueue.encode(receiver: "N4EAC-7", grid: "FM18FW00", software: "QSO73 0.4.10 / modem73 2.4.2", reports: maximum, sequence: 0, domain: 42, time: 1700000020)
        check(maximumPacket.count <= 1400, "Largest production batch fits safe datagram size")
        let reporter = PSKReporter(defaults: nil)
        check(!reporter.enabled, "Reporting off by default")
        reporter.begin(call: "N4EAC", grid: "FM18FW"); reporter.enabled = true
        reporter.receive(call: "K1ABC", source: "phy", snr: -7, time: Date(), frequency: 7106500, catTime: Date())
        check(reporter.status.hasPrefix("Waiting"), "Only decoded AX.25 sources")
        reporter.receive(call: "K1ABC", source: "ax25", snr: -7, time: Date(), frequency: 7106500, catTime: Date().addingTimeInterval(-31))
        check(reporter.status.hasPrefix("Waiting"), "Reject stale CAT")
        reporter.receive(call: "K1ABC", source: "ax25", snr: -7, time: Date(), frequency: 7106500, catTime: Date().addingTimeInterval(-1))
        check(reporter.status.hasPrefix("1 queued"), "Verified reception queued")
        reporter.enabled = false; check(reporter.status == "Off", "Immediate disable")
        reporter.enabled = true; check(reporter.status.hasPrefix("Waiting"), "Re-enable during radio session")
        reporter.stop()
        print("PASS: PSK Reporter encoding, freshness, dedup, bounds, mode offsets, opt-in and disable/re-enable")
    }
}
