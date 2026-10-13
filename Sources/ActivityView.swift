import SwiftUI

struct ModemActivityView: View {
    @ObservedObject var modem: Modem
    private let green = Color(red: 0.35, green: 0.9, blue: 0.55)
    private func status(_ key: String, _ suffix: String = "") -> String { modem.statusDetails[key].map { $0 + suffix } ?? "—" }
    private func config(_ key: String, _ suffix: String = "") -> String { modem.configDetails[key].map { $0 + suffix } ?? "—" }
    private var transmitState: String {
        if !modem.attached { return "Offline" }
        if modem.channel == "tx" { return "Sending" }
        switch modem.statusDetails["csma_phase"] {
        case "1": return "Deferring (RX)"
        case "2": return "Quiet \(status("csma_wait_ms"))/\(status("csma_wait_need_ms")) ms"
        case "3":
            if let rank = Int(status("csma_rank")), rank >= 0 {
                return (rank >= (Int(status("csma_rank_n")) ?? 0) ? "Yielding" : "Turn \(rank + 1)") + "/\(status("csma_rank_n")) · \(status("csma_wait_ms", " ms"))"
            }
            return "Contending · \(status("csma_wait_ms", " ms"))"
        default: return modem.txQueue > 0 ? "Queued" : "Idle"
        }
    }
    private var heard: String {
        guard let frame = modem.recentFrames.first else { return "—" }
        return "\(frame.mode) \(frame.callsign.isEmpty ? "—" : frame.callsign) · \(Int(frame.snr)) dB"
    }
    @State private var showDetails = false
    @State private var detailsTitle = ""
    @State private var detailsText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    heading("SIGNAL")
                    metric("Carrier", modem.rxAudioLevel.map { String(format: "%.1f dBFS", $0) } ?? "—")
                    ProgressView(value: (modem.rxAudioLevel ?? -100) + 100, total: 100)
                    metric("Threshold", modem.carrierThreshold.map { String(format: "%.0f dBFS", $0) } ?? "—")
                    metric("SNR", modem.snr)
                    HistoryBars(values: modem.snrHistory, slots: 32, range: -20...40, color: green).help("SNR history: last 32 decoded frames")
                    metric("BER", modem.lastBER.map { String(format: "%.2f%%", $0) } ?? "—")
                    metric("BER avg", Double(status("ber_ema")).flatMap { $0 >= 0 ? String(format: "%.2f%%", $0 * 100) : nil } ?? "—")
                    Text("Heard: " + heard).lineLimit(1).help(heard)
                    if let frame = modem.recentFrames.first { HStack { Text("Age").foregroundStyle(.secondary); Spacer(); Text(frame.time, style: .relative) } }
                    Divider().padding(.vertical, 3)
                    heading("RADIO")
                    metric("CAT", modem.rigConnected ? "Connected" : "Offline")
                    metric("Frequency", modem.rigConnected ? modem.frequency : "—")
                    metric("Mode", modem.rigConnected ? modem.radioMode : "—")
                    metric("Bandwidth", meter("BANDWIDTH", " Hz"))
                    metric("S-meter", meter("STRENGTH", " dB"))
                    metric("SWR (TX)", modem.transmitMeter("SWR") ?? "—")
                        .help("Actual CAT SWR meter, shown only during confirmed radio TX with a fresh reading. RX meter values do not measure antenna SWR.")
                    metric("RF output (TX)", modem.transmitMeter("RFPOWER_METER_WATTS").map { $0 + " W" } ?? "—")
                        .help("Actual CAT output-power meter during confirmed TX. This differs from the configured power setting and can reflect drive/ALC and driver calibration.")
                    metric("ALC (TX)", modem.transmitMeter("ALC") ?? "—")
                    metric("Temp", meter("TEMP_METER", " °C"))
                    metric("Power setting", modem.rigConnected ? (modem.rigMeters["RFPOWER_SET_WATTS"].map { $0 + " W" } ?? (Double(meter("RFPOWER")).map { String(format: "%.0f%%", $0 * 100) } ?? "—")) : "—")
                        .help("CAT power-control setting, converted to watts using Hamlib's frequency/mode-specific power2mW conversion. Percent is shown if conversion is unavailable.")
                    metric("Tuner", meter("TUNER") == "1" ? "ON" : (meter("TUNER") == "0" ? "OFF" : "—"))
                }.frame(width: 205)
                VStack(alignment: .leading, spacing: 5) {
                    heading("CSMA")
                    metric("Status", modem.csmaDescription)
                    metric("Busy", modem.attached ? ((modem.dcdActive || modem.channel == "rx") ? "YES · sync" : ((modem.csmaDescription.contains("level") && (modem.rxAudioLevel ?? -100) > (modem.carrierThreshold ?? 0)) ? "YES · level" : "NO")) : "—")
                    metric("Occupancy", status("occupancy_total_pct", "%"))
                        .help("Total channel occupancy, averaged over 30 seconds")
                    metric("Other", modem.attached ? "\(modem.occupancy)%" : "—")
                    HistoryBars(values: modem.activity.map(\.occupancy), slots: 90, range: 0...100, color: .orange).help("Occupancy history")
                    metric("Quiet", status("csma_quiet_ms", " ms") + (modem.configDetails["csma_quiet_ms"] == "0" ? " auto" : ""))
                    metric("Window", windowDescription)
                    metric("Slot", config("slot_time_ms", " ms"))
                    metric("Rank / pop", status("csma_rank") + " / " + status("csma_rank_n"))
                    metric("Stations", status("population"))
                    metric("TX", transmitState)
                    Divider().padding(.vertical, 3)
                    heading("AUDIO / PTT")
                    metric("Audio", modem.audioConnected ? "Connected" : "Offline")
                    metric("PTT", modem.attached ? (modem.pttOn ? "ON" : "OFF") : "—")
                    Text("RX: " + modem.captureRoute).lineLimit(2).help(modem.captureRoute)
                    Text("TX: " + modem.audioRoute).lineLimit(2).help(modem.audioRoute)
                    Button("Audio details") {
                        present("Audio routes", "Capture: " + modem.captureRoute + "\nPlayback: " + modem.audioRoute)
                    }.buttonStyle(.link)
                }.frame(width: 200)
                VStack(alignment: .leading, spacing: 6) {
                    HStack { heading("ACTIVITY"); Spacer(); Text("Idle").foregroundStyle(.teal); Text("RX").foregroundStyle(green); Text("TX").foregroundStyle(.pink) }
                    HStack(alignment: .bottom, spacing: 1) {
                        ForEach(0..<90, id: \.self) { index in
                            let offset = index - (90 - modem.activity.count)
                            let sample = offset >= 0 ? modem.activity[offset] : nil
                            let height = max(1, max(0, min(1, ((sample?.level ?? -100) + 100) / 100)) * 44)
                            Rectangle().fill(sample == nil ? Color.clear : (sample?.state == "tx" ? .pink : (sample?.state == "rx" ? green : .teal.opacity(0.55))))
                                .frame(maxWidth: .infinity).frame(height: height)
                        }
                    }.frame(height: 44, alignment: .bottom).background(Color.black.opacity(0.25))
                    heading("STATS")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 5) {
                        metric(modem.statusDetails["recent_tx_frames_available"] == "1" ? "RX decoded" : "RX reported", modem.attached ? "\(modem.rxCount)" : "—")
                        metric("TX encoded", modem.statusDetails["recent_tx_frames_available"] == "1" && modem.attached ? "\(modem.txCount)" : "—")
                        metric("Syncs", status("sync_count"))
                        metric("RX errors", status("rx_error_count"))
                        metric("Failed/sync", errorRatio)
                        metric("Queued time", queuedAirtime)
                        metric("Preamble", status("preamble_errors"))
                        metric("Symbol", status("symbol_errors"))
                        metric("Erased", status("erased_symbols"))
                        metric("CRC", status("crc_errors"))
                        metric("Queue", status("tx_queue"))
                        metric("Clients", status("client_count"))
                        metric("Net est.", status("net_bps_estimate", " bps"))
                        metric("Airtime", status("airtime_seconds", " s"))
                        metric("MTU", status("mtu_bytes", " B"))
                    }
                    heading("RECENT RX / TX · click for details")
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        VStack(alignment: .leading, spacing: 3) {
                            if recent.isEmpty { Text("Waiting for frames…").foregroundStyle(.secondary) }
                            ForEach(recent, id: \.key) { item in
                                Button {
                                    present(item.direction + " frame", formatted(item.frame.metadata))
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(item.direction).foregroundStyle(item.direction == "RX" ? green : .pink)
                                        Text("\(item.frame.size) B · \(item.frame.mode)").lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text(age(item.frame.time, now: timeline.date)).foregroundStyle(.secondary)
                                        if item.direction == "RX" { Text(String(format: "%.0f dB", item.frame.snr)); if item.frame.ber >= 0 { Text(String(format: "%.1f%%", item.frame.ber)) } }
                                    }
                                }.buttonStyle(.plain).frame(height: 16)
                            }
                        }.frame(height: 150, alignment: .top)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("All status") { present("All modem status fields", formatted(modem.statusDetails)) }
                Button("Configuration") { present("All modem configuration fields", formatted(modem.configDetails)) }
                Button("Event log") { present("Modem event log", modem.events.joined(separator: "\n")) }
                Spacer()
                Text("— unavailable").foregroundStyle(.secondary)
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                    .help("Activity/occupancy sampled about every 2 s. SNR history updates on decoded frames. Decoder errors/BER are for the selected mode. TX encoded does not confirm RF delivery. Unsupported/disconnected CAT meters are unavailable. An unmodified upstream engine can expose fewer diagnostics and estimated RX counts.")
            }
        }.font(.system(size: 11, design: .monospaced))
            .padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .sheet(isPresented: $showDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(detailsTitle).font(.headline); Spacer(); Button("Done") { showDetails = false } }
                    ScrollView { Text(detailsText.isEmpty ? "Unavailable until the modem is connected." : detailsText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }.padding(20).frame(minWidth: 600, minHeight: 400)
            }
    }
    private func present(_ title: String, _ text: String) { detailsTitle = title; detailsText = text; showDetails = true }
    private func formatted(_ values: [String: String]) -> String { values.keys.sorted().map { "\($0): \(values[$0] ?? "—")" }.joined(separator: "\n") }
    private var windowDescription: String {
        guard let window = Int(status("csma_window_ms")), let slot = Int(config("slot_time_ms")), slot > 0 else { return "—" }
        return "\(window / slot) slots (\(window) ms)"
    }
    private var errorRatio: String {
        guard let errors = Double(status("rx_error_count")), let syncs = Double(status("sync_count")) else { return "—" }
        return String(format: "%.0f/%.0f (%.1f%%)", errors, syncs, syncs > 0 ? errors * 100 / syncs : 0)
    }
    private var queuedAirtime: String {
        guard let airtime = Double(status("airtime_seconds")) else { return "—" }
        return String(format: "~%.1f s", Double(modem.txQueue) * airtime)
    }
    private var recent: [(key: String, direction: String, frame: RecentModemFrame)] {
        (modem.recentFrames.map { (key: "rx-\($0.id)", direction: "RX", frame: $0) } + modem.recentTX.map { (key: "tx-\($0.id)", direction: "TX", frame: $0) })
            .sorted { $0.frame.time > $1.frame.time }.prefix(8).map { $0 }
    }
    private func age(_ date: Date, now: Date) -> String { let seconds = max(0, Int(now.timeIntervalSince(date))); return seconds < 60 ? "\(seconds)s" : seconds < 3600 ? "\(seconds / 60)m" : "\(seconds / 3600)h" }
    private func meter(_ key: String, _ unit: String = "") -> String {
        guard modem.rigConnected, let value = modem.rigMeters[key], value != "Unavailable" else { return "—" }
        return value + unit
    }
    private func heading(_ text: String) -> some View { Text(text).fontWeight(.semibold).foregroundStyle(.secondary) }
    private func metric(_ label: String, _ value: String) -> some View { HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).foregroundStyle(green).lineLimit(1).multilineTextAlignment(.trailing).help(value) } }
    private func detailRows(_ values: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if values.isEmpty { Text("Unavailable until the modem is connected.").foregroundStyle(.secondary) }
            ForEach(values.keys.sorted(), id: \.self) { key in
                HStack(alignment: .top) { Text(key).foregroundStyle(.secondary).frame(width: 210, alignment: .leading); Text(values[key] ?? "—").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }.padding(.vertical, 8)
    }
}
private struct HistoryBars: View {
    let values: [Double]
    let slots: Int
    let range: ClosedRange<Double>
    let color: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(0..<slots, id: \.self) { index in
                let offset = index - (slots - values.count)
                let value = offset >= 0 ? values[offset] : range.lowerBound
                let height = max(1, min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound))) * 14)
                Rectangle().fill(offset >= 0 ? color : .clear).frame(maxWidth: .infinity).frame(height: height)
            }
        }.frame(height: 14, alignment: .bottom).background(Color.black.opacity(0.2))
    }
}
