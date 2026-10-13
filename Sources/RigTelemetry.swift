import Foundation

enum RigTelemetry {
    // Accept plain rigctld responses and extended responses terminated by RPRT.
    static func number(_ response: String) -> Double? {
        let lines = response.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if let result = lines.last(where: { $0.hasPrefix("RPRT") }), result != "RPRT 0" { return nil }
        for line in lines.reversed() where !line.hasPrefix("RPRT") {
            let candidate = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? line
            if let value = Double(candidate), value.isFinite { return value }
        }
        return nil
    }
    static func powerConversion(fraction: Double, frequency: String, mode: String) -> String? {
        guard (0...1).contains(fraction), let mhz = Double(frequency.split(separator: " ").first ?? ""),
              mhz.isFinite, mhz > 0, mhz < 10000, !mode.isEmpty,
              mode.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
        return "+\\power2mW \(fraction) \(Int((mhz * 1_000_000).rounded())) \(mode)"
    }
    static func display(_ value: Double) -> String { String(format: value == value.rounded() ? "%.0f" : "%.2f", value) }
}
