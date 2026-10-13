import Foundation

@main struct PSKReporterTransportTests {
    @MainActor static func main() async throws {
        let reporter = PSKReporter(defaults: nil, destinationHost: "127.0.0.1", destinationPort: UInt16(CommandLine.arguments[1])!)
        reporter.begin(call: "TEST1", grid: "AA00AA"); reporter.enabled = true
        reporter.receive(call: "TEST2", source: "ax25", snr: -9.6, time: Date(), frequency: 7106500, catTime: Date().addingTimeInterval(-1))
        guard reporter.status.hasPrefix("1 queued") else { fatalError("Missing queued report") }
        reporter.flush(now: Date().addingTimeInterval(331))
        for _ in 0..<200 {
            if reporter.status.hasPrefix("1 submitted") { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard reporter.status.hasPrefix("1 submitted") else { fatalError("UDP send failed: \(reporter.status)") }
        reporter.enabled = false
        guard reporter.status == "Off" else { fatalError("Disable failed") }
        reporter.stop()
        print("PASS: native macOS UDP submission and immediate reporting disable, loopback only")
    }
}
