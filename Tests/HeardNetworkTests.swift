import Foundation
@main struct HeardNetworkTests {
    @MainActor static func main() async throws {
        let modem = Modem(chatDefaults: nil)
        var station = StationSettings(); station.callsign = "TEST1"
        var config = Modem73Settings(); config.embedded = false; config.catEnabled = false
        config.controlPort = Int(CommandLine.arguments[1])!; config.kissPort = Int(CommandLine.arguments[2])!
        modem.autoHeardReply = true; modem.attachExternal(station, modem: config)
        for _ in 0..<2000 {
            if modem.entries.filter({ $0.direction.hasPrefix("You") && $0.text.hasPrefix("HEARD reply") }).count == 3 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let replies = modem.entries.filter { $0.direction.hasPrefix("You") && $0.text.hasPrefix("HEARD reply") }
        guard replies.count == 3, replies.allSatisfy(\.automatic), replies.contains(where: { $0.text.contains("TEST3") && $0.text.contains("-8.5 dB") }), replies.contains(where: { $0.text.contains("not heard STALE1") }) else { fatalError("Heard network responses: \(replies.map(\.text)); error=\(modem.error ?? "none")") }
        modem.detach()
        print("PASS: actual modem-control/KISS Heard requests generate recent, specific measured-SNR and stale/not-heard automatic replies")
    }
}
