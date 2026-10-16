import Foundation
import AppKit
@MainActor enum ContactMap {
    static func html(_ records: [StationContact], theme: String, template: String) throws -> String {
        struct MapData: Encodable { let theme: String; let contacts: [StationContact] }
        let bytes = try JSONEncoder().encode(MapData(theme:theme,contacts:records))
        let json = String(decoding:bytes,as:UTF8.self).replacingOccurrences(of:"<",with:"\\u003c").replacingOccurrences(of:">",with:"\\u003e").replacingOccurrences(of:"&",with:"\\u0026")
        return template.replacingOccurrences(of:"__QSO73_DATA__",with:json)
    }
    static func open(_ records: [StationContact], theme: String) throws {
        guard let source = Bundle.main.url(forResource:"ContactMap",withExtension:"html") else { throw RadioError.invalid("Contact map resource is missing.") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("QSO73-Contact-Map.html")
        try html(records,theme:theme,template:String(contentsOf:source,encoding:.utf8)).write(to:output,atomically:true,encoding:.utf8)
        NSWorkspace.shared.open(output)
    }
}
