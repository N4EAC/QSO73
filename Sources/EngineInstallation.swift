import Foundation
import CryptoKit
import Combine
import Darwin

struct InstalledEngine: Codable, Equatable {
    let folder: String
    let label: String
    let sha256: String
    let headless: Bool
    var version: String? = nil
}

struct EngineStore {
    let root: URL
    let defaults: UserDefaults
    private let key = "modem73InstalledEngine.v1"
    static var standard: EngineStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return EngineStore(root: support.appendingPathComponent("QSO73/Engines", isDirectory: true), defaults: .standard)
    }
    var selected: InstalledEngine? {
        guard let bytes = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(InstalledEngine.self, from: bytes)
    }
    func executable(for engine: InstalledEngine) throws -> URL {
        guard UUID(uuidString: engine.folder) != nil else { throw RadioError.invalid("Invalid installed engine record. Select the bundled engine.") }
        let binary = root.appendingPathComponent(engine.folder).appendingPathComponent("modem73")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw RadioError.invalid("The installed engine is missing. Select the bundled engine or reinstall it.") }
        guard try digest(binary) == engine.sha256 else { throw RadioError.invalid("The installed engine has changed since validation. Reinstall it or select the bundled engine.") }
        return binary
    }
    func useBundled() { defaults.removeObject(forKey: key) }
    func restore(_ engine: InstalledEngine?) throws {
        if let engine { _ = try executable(for: engine); defaults.set(try JSONEncoder().encode(engine), forKey: key) }
        else { useBundled() }
    }
    func install(_ source: URL) async throws -> InstalledEngine {
        // Staging never alters the app bundle or the previously selected engine.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let folder = UUID().uuidString
        let destination = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            let binary = destination.appendingPathComponent("modem73")
            try FileManager.default.copyItem(at: source, to: binary)
            let header = try FileHandle(forReadingFrom: binary)
            let magic = Array(try header.read(upToCount: 4) ?? Data())
            try header.close()
            guard [[0xcf,0xfa,0xed,0xfe], [0xfe,0xed,0xfa,0xcf], [0xca,0xfe,0xba,0xbe], [0xca,0xfe,0xba,0xbf], [0xbe,0xba,0xfe,0xca], [0xbf,0xba,0xfe,0xca]].contains(magic.map(Int.init)) else {
                throw RadioError.invalid("Select a native macOS modem73 executable, not a script or Linux/Windows build.")
            }
            guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw RadioError.invalid("Select the macOS modem73 executable from an unpacked package.") }
            let parent = source.deletingLastPathComponent()
            for item in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
                if item.lastPathComponent == "lib" || item.pathExtension == "dylib" || ["LICENSE", "THIRD_PARTY_NOTICES.md"].contains(item.lastPathComponent) {
                    try FileManager.default.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
                }
            }
            let help = try await probe(binary, arguments: ["--help"])
            let required = ["--control-port", "--control-bind", "--bind", "--config", "--list-audio", "--input-device", "--output-device", "--tx-level", "--robust-mode", "--csma-mode", "--frag", "--ptt"]
            guard help.contains("MODEM73"), required.allSatisfy(help.contains) else { throw RadioError.invalid("This engine does not support QSO73's required modem73 command-line interface.") }
            let audio = try await probe(binary, arguments: ["--list-audio"])
            guard audio.contains("Input devices:"), audio.contains("Output devices:") else { throw RadioError.invalid("The engine's audio-device interface is incompatible.") }
            let engine = InstalledEngine(folder: folder, label: parent.lastPathComponent, sha256: try digest(binary), headless: help.contains("--headless"), version: EngineReleaseStatus.version(in: help))
            defaults.set(try JSONEncoder().encode(engine), forKey: key)
            return engine
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
    private func digest(_ url: URL) throws -> String {
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private func probe(_ binary: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let child = Process(); child.executableURL = binary; child.arguments = arguments
            child.currentDirectoryURL = binary.deletingLastPathComponent()
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            _ = FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close(); try? FileManager.default.removeItem(at: file) }
            child.standardOutput = handle; child.standardError = handle
            try child.run()
            defer { if child.isRunning { child.terminate(); kill(child.processIdentifier, SIGKILL); child.waitUntilExit() } }
            let deadline = Date().addingTimeInterval(8)
            while child.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
            if child.isRunning {
                child.terminate()
                let grace = Date().addingTimeInterval(1)
                while child.isRunning && Date() < grace { try await Task.sleep(nanoseconds: 50_000_000) }
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                child.waitUntilExit()
                throw RadioError.invalid("Engine compatibility check timed out.")
            }
            child.waitUntilExit()
            let bytes = try Data(contentsOf: file)
            guard child.terminationStatus == 0 else { throw RadioError.invalid("Cannot run this engine on this Mac, or a bundled library is missing. " + String(decoding: bytes.prefix(1000), as: UTF8.self)) }
            return String(decoding: bytes, as: UTF8.self)
        }.value
    }
}

@MainActor final class EngineUpdates: ObservableObject {
    @Published var installed = EngineStore.standard.selected
    @Published var previous: InstalledEngine?
    @Published var busy = false
    @Published var message = ""
    var selectionLabel: String { installed.map { "Installed: \($0.label) · \($0.sha256.prefix(8))" } ?? "Bundled: modem73 2.4.2 · QSO73 build" }
    func install(_ source: URL) async {
        guard !busy else { return }
        busy = true; message = "Validating the engine and bundled libraries…"
        defer { busy = false }
        do {
            let old = installed
            installed = try await EngineStore.standard.install(source)
            previous = old
            message = "Engine installed. It will be used on the next Start Modem."
        } catch { message = error.localizedDescription }
    }
    func useBundled() { EngineStore.standard.useBundled(); installed = nil; message = "The bundled engine will be used on the next Start Modem." }
    func rollback() {
        do { try EngineStore.standard.restore(previous); installed = previous; previous = nil; message = "Previous engine selected." }
        catch { message = error.localizedDescription }
    }
    func check() async {
        guard !busy else { return }
        busy = true; message = "Checking upstream releases…"
        defer { busy = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/RFnexus/modem73/releases/latest")!)
            request.timeoutInterval = 15
            request.setValue("QSO73", forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let tag = object["tag_name"] as? String else { throw RadioError.invalid("Could not check releases. Open Upstream Releases to check manually.") }
            message = EngineReleaseStatus.message(latest: tag, current: installed == nil ? "2.4.2" : installed?.version)
        } catch { message = error.localizedDescription }
    }
}

enum EngineReleaseStatus {
    static func version(in help: String) -> String? {
        let regex = try! NSRegularExpression(pattern: #"(?im)^MODEM73\s+v?(\d+\.\d+\.\d+)(?=\s|$)"#)
        guard let match = regex.firstMatch(in: help, range: NSRange(help.startIndex..., in: help)),
              let range = Range(match.range(at: 1), in: help) else { return nil }
        return String(help[range])
    }
    private static func parts(_ value: String) -> [Int]? {
        let clean = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let values = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard values.count == 3, values.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = values.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }
    static func message(latest: String, current: String?) -> String {
        guard let current, let active = parts(current), let released = parts(latest) else {
            return "Latest upstream release: \(latest). The selected engine's version could not be compared. Use Install Local Engine… to select a downloaded package."
        }
        if active == released { return "Up to date · modem73 \(current). No newer upstream release is available." }
        if active.lexicographicallyPrecedes(released) {
            return "Update available: modem73 \(latest) (selected: \(current)). Download and unpack the macOS package, then choose Install Local Engine…."
        }
        return "Up to date · selected modem73 \(current) is newer than the latest upstream release \(latest)."
    }
}
