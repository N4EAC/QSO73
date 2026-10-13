import Foundation

@main struct NetworkTests {
    @MainActor static func main() async throws {
        func awaitCondition(_ label: String, _ condition: @escaping @MainActor () -> Bool) async throws {
            for _ in 0..<600 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            fatalError("Timed out: \(label)")
        }
        let modem = Modem(chatDefaults: nil)
        var station = StationSettings(); station.callsign = "TEST1"; station.locator = "AA00AA"
        var settings = Modem73Settings(); settings.embedded = false; settings.catEnabled = true
        settings.controlPort = Int(CommandLine.arguments[1])!
        settings.kissPort = Int(CommandLine.arguments[2])!
        modem.attachExternal(station, modem: settings)
        try await awaitCondition("audio and modem configuration") { modem.attached && modem.audioConnected && modem.activeMode == "RDM-600" }
        try await awaitCondition("active decoder event") { modem.decoding }
        guard modem.rxAudioLevel == -32.5 else { fatalError("RX audio level did not reach the client") }
        try await awaitCondition("modem activity and frame history") { !modem.activity.isEmpty && modem.recentFrames.count == 1 }
        guard modem.txQueue == 3, modem.rxErrors == 4, modem.occupancy == 12, modem.clients == 1,
              modem.recentFrames.first?.size == 64, modem.recentFrames.first?.mode == "RDM-600",
              abs((modem.lastBER ?? 0) - 0.6) < 0.001 else { fatalError("Modem activity fields") }
        guard modem.statusDetails["csma_wait_ms"] == "120", modem.statusDetails["sync_count"] == "7",
              modem.configDetails["slot_time_ms"] == "500", modem.recentTX.first?.size == 40,
              modem.dcdActive, !modem.pttOn, modem.snrHistory == [-8], modem.activity.first?.occupancy == 18,
              modem.recentFrames.first?.metadata["ber_pct"] == "0.6" else { fatalError("Complete activity telemetry") }
        modem.reporter.enabled = true
        let received = Date(timeIntervalSince1970: 1700000000)
        guard modem.signalReport(for: "test2-0", now: received.addingTimeInterval(10)) == -8,
              modem.signalReport(for: "TEST3", now: received) == nil,
              modem.signalReport(for: "TEST2", now: received.addingTimeInterval(601)) == nil else { fatalError("Signal report station and age validation") }
        modem.send("café 👋", to: "TEST2")
        try await awaitCondition("addressed and broadcast receive") {
            modem.entries.contains { $0.text == "Hello 👋" } && modem.entries.contains { $0.text == "CQ café" }
        }
        guard !modem.entries.contains(where: { $0.text == "for someone else" }) else { fatalError("Destination filtering failed") }
        guard modem.callsigns.destinations == ["QST", "TEST2"] else { fatalError("Contact destinations not tracked or unrelated callsign included") }
        try modem.rooms.join("#hf")
        modem.sendRoom("channel socket test", room: "#hf")
        modem.sendRoom("direct socket test", room: "TEST2")
        try await awaitCondition("conversation socket routing") {
            modem.entries.contains { $0.text == "channel reply" && $0.conversation == "#hf" } &&
            modem.entries.contains { $0.text == "direct reply" && $0.conversation == "TEST2" } &&
            modem.rooms.topics["#hf"] == "Socket test net"
        }
        guard modem.entries.filter({ $0.text == "channel reply" }).count == 1,
              !modem.entries.contains(where: { $0.text.hasPrefix("~Q73:") }), modem.attached else { fatalError("Envelope display or malformed packet handling failed") }
        try await awaitCondition("unsupported meter marked unavailable") { modem.rigMeters["STRENGTH"] == "Unavailable" }
        try await awaitCondition("CAT read") { modem.frequency == "14.105000 MHz" && modem.radioMode == "USB" && modem.rigConnected }
        try await awaitCondition("power setting in watts") { modem.rigMeters["RFPOWER_SET_WATTS"] == "15" }
        guard modem.transmitMeter("SWR") == nil, modem.transmitMeter("RFPOWER_METER_WATTS") == nil else { fatalError("Idle meter floor shown as an actual TX measurement") }
        try await awaitCondition("decoded-frame PSK report with fresh CAT") { modem.reporter.status.hasPrefix("1 queued") }
        modem.reporter.enabled = false
        modem.tune("14.106")
        try await awaitCondition("CAT tune and reread") { modem.frequency == "14.106000 MHz" && modem.frequencyFeedback == "Radio confirmed 14.106000 MHz" }
        modem.send(String(repeating: "x", count: 201), to: "TEST2")
        guard modem.error != nil else { fatalError("Message-size guard failed") }
        modem.error = nil
        modem.tune("nan")
        guard modem.error != nil else { fatalError("Frequency validation failed") }
        modem.error = nil
        try await awaitCondition("SNR event") { modem.snr == "-8.0 dB" }
        guard modem.entries.contains(where: { $0.direction.hasPrefix("You") && $0.text == "café 👋" }) else { fatalError("Submitted chat entry missing") }
        try await awaitCondition("actual-radio TX meters") { modem.transmitMeter("SWR") == "1.70" && modem.transmitMeter("RFPOWER_METER_WATTS") == "12.50" && modem.transmitMeter("ALC") == "0.08" }
        guard modem.transmitMeter("SWR", now: Date().addingTimeInterval(7)) == nil else { fatalError("Stale TX reading shown as live") }
        try await awaitCondition("TX readings clear when radio returns to RX") { modem.radioPTT == false && modem.transmitMeter("SWR") == nil && modem.transmitMeter("RFPOWER_METER_WATTS") == nil }
        guard !modem.decoding && modem.dcdActive && modem.audioConnected else { fatalError("Busy audio must not imply active decoding") }
        // Server closes after the RX/TX/RX fixture sequence.
        try await awaitCondition("remote channel closure") { !modem.attached && modem.error != nil }
        modem.detach()
        guard !modem.attached, !modem.connecting, modem.status == "Offline" else { fatalError("Detach state") }
        guard modem.statusDetails.isEmpty, modem.configDetails.isEmpty, modem.rigMeters.isEmpty, modem.recentTX.isEmpty, modem.snrHistory.isEmpty else { fatalError("Stale telemetry after disconnect") }
        guard modem.activity.isEmpty, modem.recentFrames.isEmpty else { fatalError("Stale activity after disconnect") }
        guard !modem.decoding else { fatalError("Stale decoding indicator after disconnect") }
        guard modem.rxAudioLevel == nil else { fatalError("Stale RX audio level after disconnect") }
        let historyCount = modem.entries.count
        modem.callsigns.clear()
        guard modem.callsigns.destinations == ["QST"], modem.entries.count == historyCount else { fatalError("Clearing callsigns changed chat history") }
        modem.callsigns.remember("test2-0"); modem.callsigns.remember("TEST2"); modem.callsigns.remember("QST")
        guard modem.callsigns.destinations == ["QST", "TEST2"] else { fatalError("Callsign normalization or broadcast exclusion failed") }
        print("PASS: modem73 TCP startup, KISS send/receive, native channels/direct messages/topics, duplicate and malformed envelopes, Unicode, destination filtering, control events, CAT read/tune, power-setting conversion, fresh TX-only RF/SWR/ALC, size guards and closure")
    }
}
