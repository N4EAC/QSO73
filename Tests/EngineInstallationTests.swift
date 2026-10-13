import Foundation

@main struct InstallationTests {
    static func main() async throws {
        guard EngineReleaseStatus.message(latest: "v2.4.2", current: "2.4.2").hasPrefix("Up to date"),
              EngineReleaseStatus.message(latest: "v2.10.0", current: "2.4.2").hasPrefix("Update available"),
              EngineReleaseStatus.message(latest: "v2.4.2", current: "2.5.0").hasPrefix("Up to date"),
              EngineReleaseStatus.message(latest: "v2.4.2", current: nil).contains("could not be compared"),
              EngineReleaseStatus.message(latest: "v2.5.0-rc1", current: "2.4.2").contains("could not be compared"),
              EngineReleaseStatus.version(in: "MODEM73 v2.4.2\nUsage:") == "2.4.2",
              EngineReleaseStatus.version(in: "MODEM73 build Oct 12 2026") == nil else { fatalError("Release version comparison failed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "qso73-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: domain) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = EngineStore(root: root.appendingPathComponent("store"), defaults: defaults)
        let bad = root.appendingPathComponent("bad-engine")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bad)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bad.path)
        do { _ = try await store.install(bad); fatalError("Non-native engine accepted") } catch {}
        guard store.selected == nil else { fatalError("Rejected install changed the selection") }
        let original = URL(fileURLWithPath: CommandLine.arguments[1])
        let originalBytes = try Data(contentsOf: original)
        let first = try await store.install(original)
        let selected = try store.executable(for: first)
        guard selected.path.hasPrefix(root.path), try Data(contentsOf: selected) == originalBytes,
              store.selected == first else { fatalError("Engine install not isolated") }
        do { _ = try await store.install(bad); fatalError("Invalid replacement accepted") } catch {}
        guard store.selected == first else { fatalError("Failed replacement lost the working engine") }
        let second = try await store.install(original)
        guard second.folder != first.folder else { fatalError("Engine replaced in place") }
        try store.restore(first)
        guard store.selected == first else { fatalError("Rollback failed") }
        var changed = try Data(contentsOf: selected); changed.append(0)
        try changed.write(to: selected)
        do { _ = try store.executable(for: first); fatalError("Modified engine accepted") } catch {}
        store.useBundled()
        guard store.selected == nil, try Data(contentsOf: original) == originalBytes else { fatalError("Bundled fallback or original engine changed") }
        print("PASS: isolated engine installation, native-file guard, failed-update preservation, versioned slots, rollback, integrity and bundled fallback")
    }
}
