import Foundation
@main struct RigTests {
    @MainActor static func main() async throws {
        var station = StationSettings(); station.callsign = "TEST1"; station.rigPort = Int(CommandLine.arguments[1])!
        var rig = RigSettings(); rig.device = "/dev/test-radio"
        let args = try rig.arguments(port: station.rigPort)
        guard args.contains("1049"), args.contains("38400"), args.contains("/dev/test-radio") else { fatalError("CAT arguments") }
        var network = rig; network.model = 4; network.device = "127.0.0.1:12345"
        let networkArgs = try network.arguments(port: station.rigPort)
        guard networkArgs.contains("127.0.0.1:12345"), !networkArgs.contains("-s") else { fatalError("FLRig requires a network endpoint, not serial settings") }
        network.model = 2; network.device = "localhost:5000"
        _ = try network.arguments(port: 4532)
        do { _ = try network.arguments(port: 5000); fatalError("Recursive network backend accepted") } catch RadioError.invalid { }
        network.device = ""; do { _ = try network.arguments(port: 4532); fatalError("Missing endpoint accepted") } catch RadioError.invalid { }
        network.model = 1; _ = try network.arguments(port: 4532)
        let owned = RigController()
        try await owned.prepare(rig, station: station, executable: URL(fileURLWithPath: CommandLine.arguments[2]))
        guard await RigController.available(host: station.rigHost, port: station.rigPort) else { fatalError("Owned daemon not ready") }
        let reused = RigController()
        try await reused.prepare(rig, station: station)
        reused.stop()
        guard await RigController.available(host: station.rigHost, port: station.rigPort) else { fatalError("Reused process was stopped") }
        owned.stop()
        try await Task.sleep(nanoseconds: 400_000_000)
        guard !(await RigController.available(host: station.rigHost, port: station.rigPort)) else { fatalError("Owned daemon survived stop") }
        print("PASS: CAT arguments, automatic daemon startup/readiness, existing-service reuse and owned-process stop")
    }
}
