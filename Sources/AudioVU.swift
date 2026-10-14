import Foundation
import SwiftUI

struct AudioVUReading {
    let rms: Double
    let peak: Double
    init?(_ object: [String: Any], prefix: String) {
        guard object[prefix + "_audio_available"] as? Bool == true,
              let rms = (object[prefix + "_audio_rms_dbfs"] as? NSNumber)?.doubleValue,
              let peak = (object[prefix + "_audio_peak_dbfs"] as? NSNumber)?.doubleValue,
              rms.isFinite, peak.isFinite else { return nil }
        self.rms = min(0, max(-100, rms)); self.peak = min(0, max(-100, peak))
    }
    static func fraction(_ db: Double) -> Double { min(1, max(0, (db + 60) / 60)) }
}
struct AudioLevels {
    var rx: AudioVUReading?
    var tx: AudioVUReading?
    var time = Date.distantPast
    mutating func update(_ object: [String: Any], now: Date = Date()) {
        rx = AudioVUReading(object, prefix: "rx"); tx = AudioVUReading(object, prefix: "tx"); time = now
    }
    func reading(tx: Bool, connected: Bool, now: Date = Date()) -> AudioVUReading? {
        guard connected, now.timeIntervalSince(time) >= 0, now.timeIntervalSince(time) <= 1 else { return nil }
        return tx ? self.tx : rx
    }
}
struct AudioVU: View {
    let title: String
    let reading: AudioVUReading?
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Text(reading.map { String(format: "%.0f dBFS", $0.rms) } ?? "—")
                    .font(.system(.caption, design: .monospaced)).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.2))
                    LinearGradient(stops: [.init(color: .green, location: 0), .init(color: .green, location: 0.79), .init(color: .yellow, location: 0.80), .init(color: .yellow, location: 0.94), .init(color: .red, location: 0.95), .init(color: .red, location: 1)], startPoint: .leading, endPoint: .trailing)
                        .mask(alignment: .leading) { Rectangle().frame(width: geometry.size.width * AudioVUReading.fraction(reading?.rms ?? -100)) }
                    if let reading {
                        Rectangle().fill(reading.peak >= -3 ? Color.red : Color.primary)
                            .frame(width: 2).offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * AudioVUReading.fraction(reading.peak))))
                    }
                }
            }.frame(height: 8)
        }.help("\(title): RMS audio level with a peak marker, refreshed about five times per second. Scale −60 to 0 dBFS; red indicates little digital headroom. TX measures samples delivered to the selected output after modem gain; it is not RF power or radio ALC. — means unavailable or stale.")
    }
}
