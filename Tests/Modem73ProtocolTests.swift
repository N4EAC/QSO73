import Foundation
import SwiftUI

@main struct ProtocolTests {
    static func main() throws {
        var count = 0
        func check(_ value: Bool, _ label: String) { count += 1; if !value { fatalError(label) } }
        func rejects(_ label: String, _ body: () throws -> Void) {
            do { try body(); fatalError("Expected rejection: \(label)") } catch { count += 1 }
        }
        for call in ["N4EAC", "TEST1-0", "TEST1-15", "QST"] { check(PacketAddress.isValid(call), "Valid address \(call)") }
        for call in ["", "TOOLONG1", "TEST1-16", "TEST1-", "TEST1\rT 1", "TEST/1"] { check(!PacketAddress.isValid(call), "Invalid address \(call)") }
        check(PacketAddress.canonical("test1-0") == "TEST1", "SSID zero address normalization")
        let p = RadioPacket(source: "TEST1-15", destination: "TEST2", text: "café 👋")
        let bytes = try p.encode()
        check(try RadioPacket.decode(bytes) == p, "AX.25 Unicode round trip")
        check(bytes[0] == UInt8(Character("T").asciiValue! << 1) && bytes[13] == 0x7F && bytes[14] == 3 && bytes[15] == 0xF0, "AX.25 wire addresses, SSID, control and PID")
        let raw = Data([0, 0xC0, 0xDB, 255, 12])
        let frame = KISSFramer.encode(raw)
        check(frame.contains(0xDC) && frame.contains(0xDD), "KISS escaping")
        for cut in 0...frame.count {
            var parser = KISSFramer()
            let a = try parser.feed(Data(frame.prefix(cut)))
            let b = try parser.feed(Data(frame.dropFirst(cut)))
            check(a + b == [raw], "Split KISS frame \(cut)")
        }
        var parser = KISSFramer()
        check(try parser.feed(frame + KISSFramer.encode(bytes)) == [raw, bytes], "Coalesced KISS frames")
        var controls = KISSFramer()
        check(try controls.feed(Data([0xC0, 0x01, 0x32, 0xC0])).isEmpty, "Ignore non-data KISS commands")
        rejects("invalid escape") { var f = KISSFramer(); _ = try f.feed(Data([0xC0, 0, 0xDB, 0x01])) }
        rejects("oversized KISS") { var f = KISSFramer(); _ = try f.feed(Data([0xC0, 0]) + Data(repeating: 1, count: 65536)) }
        rejects("invalid packet") { _ = try RadioPacket.decode(Data(repeating: 0, count: 16)) }
        rejects("message limit") { _ = try RadioPacket(source: "TEST1", destination: "QST", text: String(repeating: "é", count: 101)).encode() }
        let object: [String: Any] = ["cmd": "rigctl", "command": "f"]
        let control = try JSONControlFramer.encode(object)
        for cut in 0...control.count {
            var f = JSONControlFramer()
            let a = try f.feed(Data(control.prefix(cut)))
            let b = try f.feed(Data(control.dropFirst(cut)))
            check((a+b).count == 1 && (a+b)[0]["command"] as? String == "f", "Split control frame \(cut)")
        }
        rejects("control allocation limit") { var f = JSONControlFramer(); _ = try f.feed(Data([0x7F, 255, 255, 255])) }
        rejects("zero control size") { var f = JSONControlFramer(); _ = try f.feed(Data([0,0,0,0])) }
        var station = StationSettings(); station.callsign = "TEST1-15"; station.name = "Alice"; station.rigHost = "192.0.2.1"
        let profile = QSO73SettingsProfile(station: station, modem: Modem73Settings(), radio: RigSettings())
        check(try QSO73SettingsProfile.decoded(profile.encoded()) == profile, "Native QSO73 settings round trip")
        let macros = RadioMacroSettings()
        let cq = try macros.message(.cq, station: station, target: "TEST2", snr: nil)
        check(cq.destination == "QST" && cq.text.contains("TEST1-15"), "CQ broadcast and source expansion")
        let report = try macros.message(.report, station: station, target: "test2-0", snr: -8.4)
        check(report.destination == "TEST2" && report.text.contains("SNR -8.4 dB"), "Addressed measured negative report")
        check(try macros.message(.report, station: station, target: "TEST2", snr: 12).text.contains("+12.0 dB"), "Positive report sign")
        check(try macros.message(.goodbye, station: station, target: "TEST2", snr: nil).text.contains("73!"), "End-of-contact macro")
        var customMacro = macros; customMacro.custom = "Hello from {call} in {qth}."
        check(try customMacro.message(.custom, station: station, target: "QST", snr: nil).destination == "QST", "Custom macro broadcast")
        check(try customMacro.message(.custom, station: station, target: "test2-0", snr: nil).destination == "TEST2", "Custom macro addressed destination")
        rejects("blank custom macro") { _ = try macros.message(.custom, station: station, target: "QST", snr: nil) }
        customMacro.custom = "SNR {snr}"
        rejects("custom SNR without measurement") { _ = try customMacro.message(.custom, station: station, target: "TEST2", snr: nil) }
        let oldMacros = Data(#"{"cq":"old CQ","report":"old {snr}","goodbye":"old 73"}"#.utf8)
        check(try JSONDecoder().decode(RadioMacroSettings.self, from: oldMacros).custom.isEmpty, "Existing macro settings decode with F4 disabled")
        check(RadioMacro.custom.shortcut == KeyEquivalent(Character(UnicodeScalar(0xF707)!)), "F4 shortcut")
        rejects("report without measurement") { _ = try macros.message(.report, station: station, target: "TEST2", snr: nil) }
        rejects("nonfinite report") { _ = try macros.message(.report, station: station, target: "TEST2", snr: .nan) }
        rejects("broadcast report") { _ = try macros.message(.report, station: station, target: "QST", snr: 5) }
        var longMacro = macros; longMacro.cq = String(repeating: "é", count: 101)
        rejects("macro UTF8 limit") { _ = try longMacro.message(.cq, station: station, target: "QST", snr: nil) }
        var withMacros = profile; withMacros.macros = macros
        check(try QSO73SettingsProfile.decoded(withMacros.encoded()) == withMacros, "Macro settings profile round trip")
        var beaconProfile = profile
        beaconProfile.station.locator = "FM18FW"
        var beaconSettings = BeaconSettings(); beaconSettings.enabled = true; beaconSettings.intervalMinutes = 10
        beaconProfile.beacon = beaconSettings
        check(try QSO73SettingsProfile.decoded(beaconProfile.encoded()) == beaconProfile, "Beacon settings profile round trip")
        var future = profile; future.version = 999
        rejects("unsupported profile version") { _ = try future.encoded() }
        var invalid = profile; invalid.radio.baud = 123
        rejects("invalid profile radio") { _ = try invalid.encoded() }
        var settings = Modem73Settings()
        check(settings.ptt == "rigctl", "rigctld is the fresh-setup PTT default")
        let arguments = try settings.arguments(station: station)
        check(arguments.contains("/dev/null") && arguments.contains("--frag") && arguments.contains("--control-bind"), "Explicit config and localhost engine options")
        check(!arguments.contains("TEST1-15") && arguments.contains("TEST1"), "PHY callsign omits AX.25 SSID")
        settings.kissPort = settings.controlPort
        settings.host = ""
        check(try settings.arguments(station: station).contains("8001") && settings.connectionControlPort == 8073, "Internal ports ignore previously saved connection settings")
        settings.embedded = false; settings.host = "127.0.0.1"
        rejects("port conflict") { try settings.validate(station: station) }
        settings.kissPort = 9001; settings.controlPort = 9073
        check(settings.connectionKISSPort == 9001 && settings.connectionControlPort == 9073, "External ports remain configurable")
        settings = Modem73Settings(); settings.ptt = "rigctl"; settings.catEnabled = true
        check(try settings.arguments(station: station).contains("192.0.2.1:4532"), "rigctld arguments")
        settings.ptt = "com"; settings.catEnabled = false; settings.serialPort = "/dev/cu.radio name"
        let serial = try settings.arguments(station: station)
        check(serial.contains("/dev/cu.radio name"), "Process arguments preserve spaces without shell interpretation")
        station.callsign = "TEST1\nABORT"
        rejects("invalid source") { try station.validate() }
        print("PASS: \(count) modem73 packet, control, settings and validation checks")
    }
}
