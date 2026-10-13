import Foundation
import Network

struct RigSettings: Codable, Equatable {
    var automatic = true
    var model = 1049
    var device = ""
    var baud = 38400
    func arguments(port: Int) throws -> [String] {
        guard model > 0, device.hasPrefix("/dev/"), [4800,9600,19200,38400,57600,115200].contains(baud), (1...65535).contains(port) else {
            throw RadioError.invalid("Select the CAT serial device, radio model and matching CAT baud rate.")
        }
        return ["-m", String(model), "-r", device, "-s", String(baud), "-P", "RIG", "-T", "127.0.0.1", "-t", String(port)]
    }
    static var serialDevices: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? [])
            .filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && !$0.contains("debug-console") }
            .map { "/dev/" + $0 }.sorted()
    }
}

@MainActor final class RigController {
    private var process: Process?
    private var output: Pipe?
    private var epoch = UUID()
    var onLog: ((String) -> Void)?
    var onExit: ((Int32) -> Void)?
    static var executable: URL? {
        let directories = ["/opt/homebrew/bin", "/usr/local/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent("rigctld") }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    @MainActor private final class Probe {
        var done = false
        var usable = false
        var buffer = Data()
    }
    static func available(host: String, port: Int) async -> Bool {
        guard (1...65535).contains(port) else { return false }
        let probe = Probe()
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
        defer { connection.cancel() }
        connection.stateUpdateHandler = { state in
            Task { @MainActor in
                switch state {
                case .ready:
                    connection.send(content: Data("f\n".utf8), completion: .contentProcessed { _ in })
                    func receive() {
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { data, _, complete, error in
                            Task { @MainActor in
                                if let data { probe.buffer.append(data) }
                                if let end = probe.buffer.firstIndex(of: 10) {
                                    let line = String(decoding: probe.buffer[..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                                    probe.usable = Double(line).map { $0 > 0 && $0.isFinite } ?? false
                                    probe.done = true
                                } else if complete || error != nil || probe.buffer.count > 512 { probe.done = true }
                                else { receive() }
                            }
                        }
                    }
                    receive()
                case .failed: probe.done = true
                default: break
                }
            }
        }
        connection.start(queue: DispatchQueue(label: "org.qso73.rig-probe"))
        for _ in 0..<40 {
            if Task.isCancelled { return false }
            if probe.done { return probe.usable }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
    func prepare(_ settings: RigSettings, station: StationSettings, executable override: URL? = nil) async throws {
        let token = epoch
        if await Self.available(host: station.rigHost, port: station.rigPort) {
            guard epoch == token else { throw CancellationError() }
            onLog?("Using the running rigctld at \(station.rigHost):\(station.rigPort); its process will remain untouched.")
            return
        }
        guard epoch == token else { throw CancellationError() }
        guard settings.automatic else { throw RadioError.invalid("rigctld is unavailable. Start it manually or enable automatic CAT startup.") }
        guard ["localhost", "127.0.0.1"].contains(station.rigHost) else { throw RadioError.invalid("Automatic rigctld startup requires a local host. Start rigctld at the remote radio instead.") }
        guard process?.isRunning != true else { throw RadioError.invalid("The managed rigctld process is still stopping.") }
        guard let executable = override ?? Self.executable else { throw RadioError.invalid("rigctld is not installed. Install Hamlib to enable automatic CAT startup.") }
        let child = Process(); child.executableURL = executable; child.arguments = try settings.arguments(port: station.rigPort)
        let pipe = Pipe(); child.standardOutput = pipe; child.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            let text = String(decoding: bytes, as: UTF8.self)
            Task { @MainActor [weak self] in self?.onLog?("rigctld: " + text.trimmingCharacters(in: .newlines)) }
        }
        child.terminationHandler = { [weak self] ended in
            let code = ended.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.process === ended else { return }
                self.output?.fileHandleForReading.readabilityHandler = nil
                self.process = nil; self.output = nil
                self.onExit?(code)
            }
        }
        process = child; output = pipe
        do { try child.run() } catch { stop(); throw error }
        onLog?("Started rigctld model \(settings.model) on \(settings.device) at \(settings.baud) baud.")
        for _ in 0..<4 {
            guard epoch == token else { throw CancellationError() }
            if await Self.available(host: station.rigHost, port: station.rigPort) {
                guard epoch == token else { throw CancellationError() }
                return
            }
            guard child.isRunning else { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        stop()
        throw RadioError.invalid("rigctld could not read the radio frequency. Check the CAT serial port and radio baud rate.")
    }
    func cancelStartup() { epoch = UUID() }
    func stop() {
        epoch = UUID()
        if let child = process, child.isRunning { child.terminate() }
    }
}
