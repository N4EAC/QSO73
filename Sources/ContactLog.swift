import Foundation
import Combine

struct Contact: Codable, Identifiable {
    var id = UUID()
    var call = "", station = "", grid = "", myGrid = "", frequency = "", sent = "", received = "", note = ""
    var start = Date(), end = Date()
    static let bands: [(String, Double, Double)] = [("2190m",0.1357,0.1378),("630m",0.472,0.479),("560m",0.501,0.504),("160m",1.8,2),("80m",3.5,4),("60m",5.06,5.45),("40m",7,7.3),("30m",10.1,10.15),("20m",14,14.35),("17m",18.068,18.168),("15m",21,21.45),("12m",24.89,24.99),("10m",28,29.7),("8m",40,45),("6m",50,54),("5m",54.000001,69.9),("4m",70,71),("2m",144,148),("1.25m",222,225),("70cm",420,450),("33cm",902,928),("23cm",1240,1300)]
    static func utc(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT:0); f.dateFormat = pattern; return f.string(from:date)
    }
    static func cleanCall(_ call: String) -> String { call.trimmingCharacters(in:.whitespacesAndNewlines).uppercased().replacingOccurrences(of:"-[0-9]{1,2}$", with:"", options:.regularExpression) }
    static func validCall(_ call: String) -> Bool {
        (3...32).contains(call.count) && call.range(of:"^[A-Z0-9]+(/[A-Z0-9]+)*$", options:.regularExpression) != nil && call.contains(where:{$0.isLetter}) && call.contains(where:{$0.isNumber})
    }
    static func validGrid(_ grid: String) -> Bool { grid.isEmpty || grid.range(of:"^[A-R]{2}[0-9]{2}([A-X]{2}([0-9]{2})?)?$",options:.regularExpression) != nil }
    var band: String? { guard let f = Double(frequency), f.isFinite else { return nil }; return Self.bands.first { f >= $0.1 && f <= $0.2 }?.0 }
    mutating func validate() throws {
        call = Self.cleanCall(call); station = Self.cleanCall(station); grid = grid.uppercased(); myGrid = myGrid.uppercased()
        guard Self.validCall(call), Self.validCall(station), call != station else { throw RadioError.invalid("Enter distinct valid contact and station callsigns.") }
        guard Self.validGrid(grid), Self.validGrid(myGrid), band != nil, start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, end >= start, (1900...2099).contains(Int(Self.utc(start,"yyyy")) ?? 0), (1900...2099).contains(Int(Self.utc(end,"yyyy")) ?? 0) else { throw RadioError.invalid("Check grids, amateur-band frequency in MHz and UTC start/end dates.") }
        guard [sent,received,note].allSatisfy({$0.utf8.count <= 512 && $0.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value <= 126 }}) else { throw RadioError.invalid("Use printable ASCII for reports and notes (up to 512 characters).") }
    }
    func adif() throws -> String {
        var c = self; try c.validate()
        func field(_ name: String, _ value: String) -> String { value.isEmpty ? "" : "<\(name):\(value.utf8.count)>\(value)" }
        let fields=[("CALL",c.call),("STATION_CALLSIGN",c.station),("OPERATOR",c.station),("QSO_DATE",Self.utc(c.start,"yyyyMMdd")),("TIME_ON",Self.utc(c.start,"HHmmss")),("QSO_DATE_OFF",Self.utc(c.end,"yyyyMMdd")),("TIME_OFF",Self.utc(c.end,"HHmmss")),("FREQ",String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),Double(c.frequency)!)),("BAND",c.band!),("MODE","PKT"),("GRIDSQUARE",c.grid),("MY_GRIDSQUARE",c.myGrid),("RST_SENT",c.sent),("RST_RCVD",c.received),("COMMENT",c.note)]
        return fields.map { field($0.0,$0.1) }.joined()+"<EOR>\n"
    }
    static func export(_ contacts: [Contact]) throws -> String { "QSO73 contact export\n<ADIF_VER:5>3.1.6<PROGRAMID:5>QSO73<PROGRAMVERSION:6>0.4.17<EOH>\n" + (try contacts.map {try $0.adif()}.joined()) }
}
@MainActor final class ContactLog: ObservableObject {
    @Published private(set) var contacts: [Contact] = []
    @Published var error: String?
    private let defaults: UserDefaults?
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey:"qso73.contacts.v1") {
            do {
                let saved = try JSONDecoder().decode([Contact].self,from:data)
                guard Set(saved.map(\.id)).count == saved.count else { throw RadioError.invalid("Duplicate contact IDs") }
                contacts = try saved.map { var c = $0; try c.validate(); return c }
            } catch { self.error = "Saved contacts could not be read; they have been preserved." }
        }
    }
    func save(_ record: Contact) throws {
        guard error == nil else { throw RadioError.invalid(error!) }
        var c = record; try c.validate(); var next = contacts
        if let index = next.firstIndex(where:{$0.id == c.id}) { next[index] = c } else { next.append(c) }
        let data = try JSONEncoder().encode(next); defaults?.set(data, forKey:"qso73.contacts.v1"); contacts = next
    }
}
