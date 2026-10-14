import Foundation

enum RadioError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

struct StationSettings: Codable, Equatable {
    var callsign = ""
    var name = ""
    var qth = ""
    var locator = ""
    var rigHost = "127.0.0.1"
    var rigPort = 4532
    static func validCallsign(_ text: String) -> Bool {
        PacketAddress.isValid(text) && text.contains(where: { $0.isNumber }) && text.contains(where: { $0.isLetter })
    }
    func validate() throws {
        guard Self.validCallsign(callsign) else { throw RadioError.invalid("Use an AX.25 callsign of up to six letters/numbers, with an optional SSID from 0 to 15.") }
    }

}

struct Modem73Settings: Codable, Equatable {
    var embedded = true
    var host = "127.0.0.1"
    var kissPort = 8001
    var controlPort = 8073
    var connectionKISSPort: Int { embedded ? 8001 : kissPort }
    var connectionControlPort: Int { embedded ? 8073 : controlPort }
    var inputDevice = "default"
    var outputDevice = "default"
    var family = "robust"
    var robustMode = "RDM-600"
    var mfskMode = "MFSK-16"
    var modulation = "QPSK"
    var rate = "1/2"
    var rxGainDB: Double? = nil
    var txGainDB: Double? = nil
    var rxGain: Double { get { rxGainDB ?? 0 } set { rxGainDB = newValue } }
    var txGain: Double { get { txGainDB ?? 0 } set { txGainDB = newValue } }
    var txLevel = 25
    var ptt = "rigctl"
    var serialPort = "/dev/cu.usbserial"
    var serialLine = "rts"
    var catEnabled = false
    func validate(station: StationSettings) throws {
        try station.validate()
        guard rxGain.isFinite, txGain.isFinite, (-20...20).contains(rxGain), (-20...20).contains(txGain) else { throw RadioError.invalid("Audio gain must be −20 to +20 dB.") }
        if !embedded {
            guard (1...65535).contains(kissPort), (1...65535).contains(controlPort), kissPort != controlPort,
                  !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RadioError.invalid("Enter two distinct TCP ports from 1 to 65535 and a modem host.") }
        }
        guard ["ofdm", "robust", "mfsk"].contains(family), ["none", "rigctl", "vox", "com"].contains(ptt), (5...100).contains(txLevel) else { throw RadioError.invalid("Invalid modem mode, PTT type, or output level.") }
        if ptt == "rigctl" || catEnabled {
            guard !station.rigHost.isEmpty, (1...65535).contains(station.rigPort), !station.rigHost.contains(":"), !station.rigHost.contains(where: { $0.isWhitespace }) else { throw RadioError.invalid("Use a rigctld hostname or IPv4 address and a port from 1 to 65535.") }
            if embedded && ptt != "rigctl" { throw RadioError.invalid("Select rigctld PTT to enable the bundled modem's CAT passthrough.") }
        }
        guard ["dtr", "rts", "both"].contains(serialLine) else { throw RadioError.invalid("Invalid serial PTT line.") }
        guard ["RDM-1200", "RDM-800", "RDM-600", "RDM-300", "RDMN-300", "RDMN-150", "RDM-1200S", "RDM-600S", "RDM-300S", "RDMN-300S", "RDMN-150S"].contains(robustMode),
              ["MFSK-8", "MFSK-16", "MFSK-32", "MFSK-32R"].contains(mfskMode),
              ["BPSK", "QPSK", "8PSK", "QAM16"].contains(modulation), rate == "1/2" else { throw RadioError.invalid("Unsupported mode selection.") }
    }
    func arguments(station: StationSettings) throws -> [String] {
        try validate(station: station)
        // Explicit empty config prevents inherited ~/.config/modem73 settings.
        var a = ["--config", "/dev/null", "--bind", "127.0.0.1", "--control-bind", "127.0.0.1",
                 "--port", String(connectionKISSPort), "--control-port", String(connectionControlPort), "--callsign", String(station.callsign.uppercased().split(separator: "-")[0]),
                 "--input-device", inputDevice, "--output-device", outputDevice, "--tx-level", String(txLevel),
                 "--frag", "--csma-mode", "sync", "--csma-band", "hf", "--modem", family]
        if rxGain != 0 || txGain != 0 { a += ["--rx-gain-db", String(rxGain), "--tx-gain-db", String(txGain)] }
        if family == "robust" { a += ["--robust-mode", robustMode] }
        else if family == "mfsk" { a += ["--mfsk-mode", mfskMode] }
        else { a += ["--modulation", modulation, "--rate", rate, "--normal"] }
        a += ["--ptt", ptt]
        if ptt == "rigctl" { a += ["--rigctl", "\(station.rigHost):\(station.rigPort)"] }
        if ptt == "com" { a += ["--com-port", serialPort, "--com-line", serialLine] }
        return a
    }
}

struct PacketAddress {
    static func canonical(_ text: String) -> String {
        let value = text.uppercased()
        if value.hasSuffix("-0") { return String(value.dropLast(2)) }
        return value
    }
    static func isValid(_ text: String) -> Bool {
        let parts = text.uppercased().split(separator: "-", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts[0].range(of: "^[A-Z0-9]{1,6}$", options: .regularExpression) != nil else { return false }
        if parts.count == 2 { return !parts[1].isEmpty && parts[1].allSatisfy({ $0.isASCII && $0.isNumber }) && (0...15).contains(Int(parts[1]) ?? -1) }
        return true
    }
    static func encode(_ text: String, last: Bool) throws -> [UInt8] {
        guard isValid(text) else { throw RadioError.invalid("Invalid packet callsign: \(text)") }
        let parts = text.uppercased().split(separator: "-")
        let call = Array(parts[0].utf8)
        return (call + Array(repeating: UInt8(32), count: 6 - call.count)).map { $0 << 1 } + [0x60 | UInt8(Int(parts.count == 2 ? String(parts[1]) : "0")!) << 1 | (last ? 1 : 0)]
    }
    static func decode(_ bytes: ArraySlice<UInt8>) throws -> String {
        guard bytes.count == 7 else { throw RadioError.invalid("Truncated AX.25 address.") }
        let b = Array(bytes)
        guard b.prefix(6).allSatisfy({ $0 & 1 == 0 }) else { throw RadioError.invalid("Malformed AX.25 address.") }
        let call = String(bytes: b.prefix(6).map { $0 >> 1 }, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        let ssid = (b[6] >> 1) & 15
        let result = call + (ssid == 0 ? "" : "-\(ssid)")
        guard isValid(result) else { throw RadioError.invalid("Malformed AX.25 callsign.") }
        return result
    }
}
struct RadioPacket: Equatable {
    let source: String
    let destination: String
    let text: String
    static let maxTextBytes = 200
    func encode() throws -> Data {
        let body = Data(text.utf8)
        guard !body.isEmpty, body.count <= Self.maxTextBytes else { throw RadioError.invalid("Packet chat allows 1–200 UTF-8 bytes per message.") }
        return Data(try PacketAddress.encode(destination, last: false) + PacketAddress.encode(source, last: true) + [0x03, 0xF0]) + body
    }
    static func decode(_ data: Data) throws -> RadioPacket {
        let bytes = Array(data)
        guard bytes.count >= 17 else { throw RadioError.invalid("Packet is too short for AX.25 chat.") }
        let destination = try PacketAddress.decode(bytes[0..<7])
        let source = try PacketAddress.decode(bytes[7..<14])
        var position = 14
        var last = bytes[13] & 1 != 0
        var addresses = 2
        while !last {
            guard position + 7 <= bytes.count, addresses < 10 else { throw RadioError.invalid("Invalid AX.25 repeater path.") }
            _ = try PacketAddress.decode(bytes[position..<position+7])
            last = bytes[position+6] & 1 != 0
            position += 7; addresses += 1
        }
        guard bytes[6] & 1 == 0, position + 2 < bytes.count,
              bytes[position] & 0xEF == 0x03, bytes[position+1] == 0xF0,
              let text = String(bytes: bytes[(position+2)...], encoding: .utf8) else { throw RadioError.invalid("Not a UTF-8 AX.25 UI chat packet.") }
        return RadioPacket(source: source, destination: destination, text: text)
    }
}
struct KISSFramer {
    private var frame: [UInt8] = []
    private var inside = false
    private var escaped = false
    static func encode(_ payload: Data) -> Data {
        var result: [UInt8] = [0xC0, 0x00]
        for byte in payload {
            switch byte {
            case 0xC0: result += [0xDB, 0xDC]
            case 0xDB: result += [0xDB, 0xDD]
            default: result.append(byte)
            }
        }
        result.append(0xC0)
        return Data(result)
    }
    mutating func reset() { frame.removeAll(); inside = false; escaped = false }
    mutating func feed(_ bytes: Data) throws -> [Data] {
        var result: [Data] = []
        for byte in bytes {
            if byte == 0xC0 {
                if escaped { reset(); throw RadioError.invalid("Incomplete KISS escape.") }
                if !frame.isEmpty, frame[0] & 0x0F == 0 { result.append(Data(frame.dropFirst())) }
                frame.removeAll(keepingCapacity: true); inside = true
                continue
            }
            guard inside else { continue }
            if escaped {
                guard byte == 0xDC || byte == 0xDD else { reset(); throw RadioError.invalid("Invalid KISS escape.") }
                frame.append(byte == 0xDC ? 0xC0 : 0xDB); escaped = false
            } else if byte == 0xDB { escaped = true }
            else { frame.append(byte) }
            guard frame.count <= 65536 else { reset(); throw RadioError.invalid("KISS frame exceeds 64 KiB.") }
        }
        return result
    }
}
struct JSONControlFramer {
    private var buffer = Data()
    mutating func reset() { buffer.removeAll() }
    static func encode(_ object: [String: Any]) throws -> Data {
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard bytes.count <= 1_048_576 else { throw RadioError.invalid("Control message is too large.") }
        let n = UInt32(bytes.count)
        return Data([UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)]) + bytes
    }
    mutating func feed(_ data: Data) throws -> [[String: Any]] {
        buffer.append(data)
        var messages: [[String: Any]] = []
        while buffer.count >= 4 {
            let h = Array(buffer.prefix(4))
            let count = h.reduce(0) { ($0 << 8) | Int($1) }
            guard count > 0, count <= 1_048_576 else { throw RadioError.invalid("Invalid modem73 control frame size.") }
            guard buffer.count >= count + 4 else { break }
            let payload = Data(buffer.dropFirst(4).prefix(count))
            guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw RadioError.invalid("Expected a control JSON object.") }
            messages.append(object)
            buffer.removeFirst(count + 4)
        }
        return messages
    }
}
