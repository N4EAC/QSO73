import Foundation
import SwiftUI

enum RadioMacro: String, CaseIterable {
    case cq, report, goodbye, custom
    var label: String { switch self { case .cq: return "F1 · CQ"; case .report: return "F2 · SNR"; case .goodbye: return "F3 · 73"; case .custom: return "F4 · Custom" } }
    var shortcut: KeyEquivalent {
        let code: UInt32 = self == .cq ? 0xF704 : self == .report ? 0xF705 : self == .goodbye ? 0xF706 : 0xF707
        return KeyEquivalent(Character(UnicodeScalar(code)!))
    }
}
struct RadioMacroSettings: Codable, Equatable {
    var cq = "CQ CQ CQ de {call}. {name} {locator}. Calling CQ."
    var report = "{to} de {call}. Your signal report is SNR {snr}."
    var goodbye = "{to} de {call}. Thanks for the contact. 73!"
    var custom = ""
    init() {}
    private enum CodingKeys: String, CodingKey { case cq, report, goodbye, custom }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cq = try values.decode(String.self, forKey: .cq)
        report = try values.decode(String.self, forKey: .report)
        goodbye = try values.decode(String.self, forKey: .goodbye)
        custom = try values.decodeIfPresent(String.self, forKey: .custom) ?? ""
    }
    func message(_ kind: RadioMacro, station: StationSettings, target: String, snr: Double?) throws -> (destination: String, text: String) {
        try station.validate()
        let destination = kind == .cq ? "QST" : PacketAddress.canonical(target.trimmingCharacters(in: .whitespacesAndNewlines))
        guard kind == .cq || (kind == .custom && ["QST", "CQ", "ALL"].contains(destination)) || (StationSettings.validCallsign(destination) && !["QST", "CQ", "ALL"].contains(destination)) else {
            throw RadioError.invalid("Enter the other station's callsign in To before sending a report or 73.")
        }
        if kind == .report || (kind == .custom && custom.contains("{snr}")) {
            guard let snr, snr.isFinite else { throw RadioError.invalid("No recent measured SNR for this station. Receive a packet before sending a signal report.") }
            if kind == .report && !report.contains("{snr}") { throw RadioError.invalid("The signal-report template must include {snr}.") }
        }
        var text = kind == .cq ? cq : kind == .report ? report : kind == .goodbye ? goodbye : custom
        let replacements = ["{call}": PacketAddress.canonical(station.callsign), "{name}": station.name, "{qth}": station.qth, "{locator}": station.locator, "{to}": destination, "{snr}": snr.map { String(format: "%+.1f dB", $0) } ?? ""]
        // One pass: values containing braces are literal station data.
        let pattern = "\\{(?:call|name|qth|locator|to|snr)\\}"
        let regex = try NSRegularExpression(pattern: pattern)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            text.replaceSubrange(range, with: replacements[String(text[range])] ?? "")
        }
        text = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty, text.utf8.count <= RadioPacket.maxTextBytes else { throw RadioError.invalid("Macro messages must contain 1–\(RadioPacket.maxTextBytes) UTF-8 bytes after expanding station data.") }
        return (destination, text)
    }
}
