import Foundation
@main struct AudioVUTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 100)
        var levels = AudioLevels()
        guard levels.reading(tx: false, connected: true, now: now) == nil else { fatalError("Initial availability") }
        levels.update(["rx_audio_available": true, "rx_audio_rms_dbfs": -32.5, "rx_audio_peak_dbfs": -18.0, "tx_audio_available": true, "tx_audio_rms_dbfs": -100.0, "tx_audio_peak_dbfs": -100.0], now: now)
        guard levels.reading(tx: false, connected: true, now: now)?.rms == -32.5,
              levels.reading(tx: true, connected: true, now: now)?.rms == -100,
              levels.reading(tx: false, connected: true, now: now.addingTimeInterval(1.01)) == nil,
              levels.reading(tx: true, connected: false, now: now) == nil else { fatalError("Availability and freshness") }
        levels.update(["rx_audio_available": false, "rx_audio_rms_dbfs": -3.0, "rx_audio_peak_dbfs": -1.0, "tx_audio_available": true, "tx_audio_rms_dbfs": Double.nan, "tx_audio_peak_dbfs": -1.0], now: now)
        guard levels.rx == nil, levels.tx == nil, AudioVUReading.fraction(-100) == 0, AudioVUReading.fraction(-30) == 0.5, AudioVUReading.fraction(3) == 1 else { fatalError("Invalid values/scale") }
        print("PASS: VU telemetry freshness, unavailable/invalid input, independent RX/TX and dBFS scale")
    }
}
