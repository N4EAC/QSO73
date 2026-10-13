import Foundation
import Combine
import Darwin

struct RadioModel: Identifiable, Equatable {
    let id: Int
    let brand: String
    let model: String
    let status: String
    var label: String { "\(id) · \(brand) \(model)" }
    static func parse(_ text: String) -> [RadioModel] {
        let regex = try! NSRegularExpression(pattern: #"^\s*(\d+)\s{2,}(.+?)\s{2,}(.+?)\s{2,}(\S+)\s+(\S+)"#)
        var entries: [Int: RadioModel] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
            func value(_ index: Int) -> String { Range(match.range(at: index), in: line).map { String(line[$0]).trimmingCharacters(in: .whitespaces) } ?? "" }
            guard let id = Int(value(1)), id > 0 else { continue }
            entries[id] = RadioModel(id: id, brand: value(2), model: value(3), status: value(5))
        }
        return entries.values.sorted { ($0.brand.lowercased(), $0.model.lowercased(), $0.id) < ($1.brand.lowercased(), $1.model.lowercased(), $1.id) }
    }
}

@MainActor final class RadioModelCatalog: ObservableObject {
    @Published private(set) var models: [RadioModel] = []
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    func refresh() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        guard let executable = RigController.executable else { message = "Install Hamlib to load its supported radio models."; return }
        do {
            models = try await Task.detached {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                _ = FileManager.default.createFile(atPath: file.path, contents: nil)
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close(); try? FileManager.default.removeItem(at: file) }
                let child = Process(); child.executableURL = executable; child.arguments = ["-l"]
                child.standardOutput = handle; child.standardError = handle
                try child.run()
                defer { if child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit() } }
                let deadline = Date().addingTimeInterval(5)
                while child.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
                if child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit(); throw RadioError.invalid("Radio model lookup timed out.") }
                child.waitUntilExit()
                guard child.terminationStatus == 0 else { throw RadioError.invalid("Hamlib could not list radio models.") }
                let models = RadioModel.parse(String(decoding: try Data(contentsOf: file), as: UTF8.self))
                guard !models.isEmpty else { throw RadioError.invalid("Hamlib returned no recognizable radio models.") }
                return models
            }.value
            message = "\(models.count) models from installed Hamlib. Select the exact radio; support varies by driver."
        } catch { message = error.localizedDescription }
    }
}
