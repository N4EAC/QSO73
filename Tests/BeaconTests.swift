import Foundation

@main struct BeaconTests {
    @MainActor static func main() throws {
        var station = StationSettings(); station.callsign = "TEST1-15"; station.locator = "fm18fw"
        var settings = BeaconSettings(); settings.enabled = true; settings.intervalMinutes = 2
        let text = try settings.message(station: station, softwareVersion: "0.3.2")
        guard text == "BEACON TEST1-15 FM18FW QSO73 v0.3.2" else { fatalError("Beacon payload") }
        var invalidGrid = station; invalidGrid.locator = "not a grid"
        do { _ = try settings.message(station: invalidGrid, softwareVersion: "0.3.2"); fatalError("Invalid grid accepted") } catch {}
        var invalidInterval = settings; invalidInterval.intervalMinutes = 0
        do { try invalidInterval.validate(station: station); fatalError("Invalid interval accepted") } catch {}
        let start = Date(timeIntervalSince1970: 1000)
        let beacon = BeaconController()
        var ready = true
        var sent: [String] = []
        beacon.canSend = { ready }
        beacon.transmit = { sent.append($0) }
        try beacon.configure(settings, station: station, softwareVersion: "0.3.2")
        beacon.start(now: start)
        beacon.tick(now: start.addingTimeInterval(119))
        guard sent.isEmpty else { fatalError("Beacon sent before interval") }
        ready = false
        beacon.tick(now: start.addingTimeInterval(120))
        guard sent.isEmpty, beacon.nextDue == start.addingTimeInterval(120) else { fatalError("Busy deferral") }
        ready = true
        beacon.tick(now: start.addingTimeInterval(125))
        guard sent == [text], beacon.nextDue == start.addingTimeInterval(245) else { fatalError("Deferred beacon submission") }
        beacon.tick(now: start.addingTimeInterval(1000))
        guard sent.count == 2, beacon.nextDue == start.addingTimeInterval(1120) else { fatalError("Wake catch-up burst") }
        ready = false
        beacon.sendNow(now: start.addingTimeInterval(1001))
        ready = true
        beacon.tick(now: start.addingTimeInterval(1005))
        guard sent.count == 3 else { fatalError("Manual beacon deferral") }
        beacon.stop()
        beacon.tick(now: start.addingTimeInterval(9999))
        guard sent.count == 3, beacon.nextDue == nil else { fatalError("Beacon sent after stop") }
        settings.enabled = false
        try beacon.configure(settings, station: station, softwareVersion: "0.3.2")
        beacon.start(now: start)
        beacon.tick(now: start.addingTimeInterval(9999))
        guard !beacon.enabled, beacon.nextDue == nil, sent.count == 3 else { fatalError("Disabled beacon sends") }
        print("PASS: beacon payload/grid, interval, busy/manual deferral, wake scheduling and stop/disable")
    }
}
