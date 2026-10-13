import Foundation
import AVFoundation
import Darwin

private final class AudioPermissionReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func finish(_ allowed: Bool) {
        lock.lock()
        let reply = continuation; continuation = nil
        lock.unlock()
        reply?.resume(returning: allowed)
    }
}

@MainActor final class EmbeddedEngine {
    private(set) var process: Process?
    private var output: Pipe?
    var onLog: ((String) -> Void)?
    var onExit: ((Int32) -> Void)?
    static var bundledExecutable: URL? {
        guard let folder = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let path = folder.appendingPathComponent("modem73")
        return FileManager.default.isExecutableFile(atPath: path.path) ? path : nil
    }
    static var executable: URL? {
        if let installed = EngineStore.standard.selected { return try? EngineStore.standard.executable(for: installed) }
        return bundledExecutable
    }
    static func resolvedExecutable() throws -> URL {
        if let installed = EngineStore.standard.selected { return try EngineStore.standard.executable(for: installed) }
        guard let binary = bundledExecutable else { throw RadioError.invalid("The bundled engine is missing.") }
        return binary
    }
    var isRunning: Bool { process?.isRunning ?? false }
    static func audioPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                let reply = AudioPermissionReply(continuation)
                AVCaptureDevice.requestAccess(for: .audio) { reply.finish($0) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) { reply.finish(false) }
            }
        default: return false
        }
    }
    private static func portAvailable(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return withUnsafePointer(to: &address) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }
    func launch(station: StationSettings, settings: Modem73Settings) throws {
        guard !isRunning else { throw RadioError.invalid("The bundled modem is still stopping. Wait before restarting it.") }
        let binary = try Self.resolvedExecutable()
        guard Self.portAvailable(settings.connectionKISSPort), Self.portAvailable(settings.connectionControlPort) else { throw RadioError.invalid("A local modem connection port is already in use. Stop the other modem application and try again.") }
        let child = Process()
        child.executableURL = binary
        child.arguments = try settings.arguments(station: station)
        if EngineStore.standard.selected?.headless == true { child.arguments?.append("--headless") }
        child.currentDirectoryURL = binary.deletingLastPathComponent()
        onLog?("Engine executable: \(binary.path)")
        let pipe = Pipe()
        child.standardOutput = pipe; child.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { handle.readabilityHandler = nil; return }
            let text = String(decoding: bytes, as: UTF8.self)
            Task { @MainActor [weak self] in self?.onLog?(text.trimmingCharacters(in: .newlines)) }
        }
        child.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.process === ended else { return }
                self.output?.fileHandleForReading.readabilityHandler = nil
                self.process = nil; self.output = nil
                self.onExit?(status)
            }
        }
        process = child; output = pipe
        do { try child.run() }
        catch { process = nil; output = nil; pipe.fileHandleForReading.readabilityHandler = nil; throw error }
    }
    func stop() {
        guard let child = process, child.isRunning else { return }
        child.terminate() // SIGTERM lets modem73 release PTT and close CoreAudio.
    }
    static func audioDevices() async throws -> (input: [String], output: [String]) {
        let binary = try resolvedExecutable()
        let text = try await Task.detached(priority: .userInitiated) {
            let child = Process(); child.executableURL = binary; child.arguments = ["--list-audio"]
            child.currentDirectoryURL = binary.deletingLastPathComponent()
            let pipe = Pipe(); child.standardOutput = pipe; child.standardError = FileHandle.nullDevice
            try child.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) { if child.isRunning { child.terminate() } }
            let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            guard child.terminationStatus == 0 else { throw RadioError.invalid("Audio device enumeration failed.") }
            return String(decoding: bytes, as: UTF8.self)
        }.value
        var input = ["default"], output = ["default"]
        var section = ""
        for raw in text.components(separatedBy: .newlines) {
            if raw == "Input devices:" { section = "input"; continue }
            if raw == "Output devices:" { section = "output"; continue }
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard raw.hasPrefix("  "), !name.isEmpty, !name.hasPrefix("default -") else { continue }
            if section == "input" && !input.contains(name) { input.append(name) }
            if section == "output" && !output.contains(name) { output.append(name) }
        }
        return (input, output)
    }
}
