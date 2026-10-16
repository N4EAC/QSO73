import Foundation
import Combine

struct StationContact: Codable, Identifiable, Equatable {
    var call: String
    var grid = ""
    var favorite = false
    var lastHeard: Date? = nil
    var id: String { call }
}

@MainActor final class CallsignList: ObservableObject {
    @Published private(set) var records: [StationContact] = []
    @Published private(set) var error: String?
    private let defaults: UserDefaults?
    private let key = "qso73.stationDirectory.v1"
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        guard let data = defaults?.data(forKey: key) else { return }
        do {
            let saved = try JSONDecoder().decode([StationContact].self, from: data)
            guard Set(saved.map(\.call)).count == saved.count,
                  saved.allSatisfy({ StationSettings.validCallsign($0.call) && PacketAddress.canonical($0.call) == $0.call && ($0.grid.isEmpty || Self.validGrid($0.grid)) && ($0.lastHeard?.timeIntervalSince1970.isFinite ?? true) }) else { throw RadioError.invalid("Invalid contact directory") }
            records = saved
        } catch { self.error = "Saved directory could not be read. Full reset can erase it; the original is preserved until then." }
    }
    var callsigns: [String] { records.map(\.call) }
    var favorites: [StationContact] { records.filter(\.favorite).sorted { $0.call < $1.call } }
    var destinations: [String] { ["QST"] + favorites.map(\.call) + records.filter { !$0.favorite }.map(\.call).sorted() }
    func remember(_ value: String, excluding own: String = "", text: String = "", received: Bool = false, at date: Date = Date()) {
        let call = PacketAddress.canonical(value.trimmingCharacters(in: .whitespacesAndNewlines))
        guard error == nil, StationSettings.validCallsign(call), !["QST","CQ","ALL"].contains(call), call != PacketAddress.canonical(own) else { return }
        var contact = records.first { $0.call == call } ?? StationContact(call: call)
        if received { contact.lastHeard = date }
        if let grid = Self.reportedGrid(text, source: call) { contact.grid = grid }
        records.removeAll { $0.call == call }; records.append(contact); save()
    }
    static func validGrid(_ grid: String) -> Bool { grid.isEmpty || grid.range(of:"^[A-R]{2}[0-9]{2}([A-X]{2}([0-9]{2})?)?$",options:.regularExpression) != nil }
    static func reportedGrid(_ text: String, source: String) -> String? {
        let words = text.uppercased().split(separator: " ").map(String.init)
        if words.count >= 3, words[0] == "BEACON", words[1] == source, Self.validGrid(words[2]), !words[2].isEmpty { return words[2] }
        if text.hasPrefix("~Q73P:"), let json = try? JSONSerialization.jsonObject(with: Data(text.dropFirst(6).utf8)) as? [String:Any], json["k"] as? String == "reply", json["call"] as? String == source, let grid = json["grid"] as? String, Self.validGrid(grid), !grid.isEmpty { return grid }
        return nil
    }
    func update(_ call: String, grid: String, favorite: Bool) throws {
        guard error == nil else { throw RadioError.invalid(error!) }
        let grid = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.validGrid(grid), let i = records.firstIndex(where: { $0.call == call }) else { throw RadioError.invalid("Enter a valid 4, 6 or 8-character Maidenhead grid, or leave it blank.") }
        records[i].grid = grid; records[i].favorite = favorite; save()
    }
    func remove(_ call: String) { guard error == nil else { return }; records.removeAll { $0.call == call }; save() }
    func clear() { guard error == nil else { return }; records.removeAll { !$0.favorite }; save() }
    func reset() { error = nil; records = []; defaults?.removeObject(forKey: key) }
    private func save() { if let data = try? JSONEncoder().encode(records) { defaults?.set(data, forKey: key) } }
}
