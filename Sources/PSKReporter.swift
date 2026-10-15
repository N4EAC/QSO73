import Foundation
import Network
import Combine

struct PSKReception: Equatable {
    let call: String
    let frequency: UInt64
    let snr: Int8
    let time: UInt32
}

struct PSKReportQueue {
    var reports: [PSKReception] = []
    private var seen: [String: Date] = [:]
    private(set) var due = Date.distantFuture
    mutating func clear(now: Date, delay: Double = 315) {
        reports = []; seen = [:]; due = now.addingTimeInterval(delay)
    }
    static func reportCall(_ text: String) -> String { PacketAddress.canonical(text).components(separatedBy: "-").first ?? "" }
    static func grid(_ text: String) -> Bool {
        text.range(of: "^[A-R]{2}[0-9]{2}([A-X]{2}([0-9]{2})?)?$", options: .regularExpression) != nil
    }
    static func rfFrequency(dial: Double, mode: String) -> UInt64? {
        guard dial.isFinite, dial > 0 else { return nil }
        let offset: Double
        switch mode.uppercased() {
        case "USB", "PKTUSB", "DATAUSB": offset = 1500
        case "LSB", "PKTLSB", "DATALSB": offset = -1500
        case "FM", "PKTFM", "DATAFM": offset = 0
        default: return nil
        }
        let rf = (dial + offset).rounded()
        guard rf > 0, rf < 1_099_511_627_776 else { return nil }
        return UInt64(rf)
    }
    mutating func add(call: String, own: String, frequency: UInt64, snr: Double, received: Date, since: Date, now: Date) -> Bool {
        let who = Self.reportCall(call)
        guard StationSettings.validCallsign(call), who != Self.reportCall(own),
              frequency > 0, frequency < 1_099_511_627_776, snr.isFinite,
              received >= since, now.timeIntervalSince(received) >= -5,
              now.timeIntervalSince(received) <= 30, received.timeIntervalSince1970 >= 0,
              received.timeIntervalSince1970 <= Double(UInt32.max), reports.count < 56 else { return false }
        seen = seen.filter { now.timeIntervalSince($0.value) < 300 }
        let key = "\(who):\(frequency)"
        guard seen[key] == nil else { return false }
        if seen.count >= 512, let oldest = seen.min(by: { $0.value < $1.value })?.key { seen[oldest] = nil }
        seen[key] = now
        reports.append(PSKReception(call: who, frequency: frequency, snr: Int8(max(-128, min(127, snr.rounded()))), time: UInt32(received.timeIntervalSince1970)))
        return true
    }
    var full: Bool { reports.count >= 56 }
    mutating func submitted(now: Date) { reports = []; due = now.addingTimeInterval(315) }
    mutating func retry(now: Date) { due = now.addingTimeInterval(315) }
    mutating func expire(now: Date) { reports.removeAll { now.timeIntervalSince1970 - Double($0.time) > 900 } }
    static func encode(receiver: String, grid: String, software: String, reports: [PSKReception], sequence: UInt32, domain: UInt32, time: UInt32) throws -> Data {
        guard StationSettings.validCallsign(receiver), Self.grid(grid), !reports.isEmpty else { throw RadioError.invalid("PSK Reporter needs a valid callsign, grid and reception.") }
        func number(_ n: UInt64, _ count: Int) -> [UInt8] { (0..<count).reversed().map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) } }
        func variable(_ s: String) throws -> [UInt8] { let bytes = Array(s.utf8); guard bytes.count <= 254 else { throw RadioError.invalid("PSK Reporter field too long.") }; return [UInt8(bytes.count)] + bytes }
        func set(_ id: UInt16, _ payload: [UInt8]) -> [UInt8] { let padding = (4 - (payload.count + 4) % 4) % 4; return number(UInt64(id), 2) + number(UInt64(payload.count + 4 + padding), 2) + payload + Array(repeating: 0, count: padding) }
        func field(_ id: UInt16, _ length: UInt16) -> [UInt8] { number(UInt64(id | 0x8000), 2) + number(UInt64(length), 2) + number(30351, 4) }
        let receiverTemplate = set(3, number(0x9992, 2) + number(3, 2) + number(1, 2) + field(2, 65535) + field(4, 65535) + field(8, 65535))
        let senderTemplate = set(2, number(0x9995, 2) + number(6, 2) + field(1, 65535) + field(5, 5) + field(6, 1) + field(10, 65535) + field(11, 1) + number(150, 2) + number(4, 2))
        let receiverData = try set(0x9992, variable(Self.reportCall(receiver)) + variable(grid) + variable(software))
        var sender: [UInt8] = []
        for report in reports {
            guard StationSettings.validCallsign(report.call), report.frequency > 0, report.frequency < 1_099_511_627_776 else { throw RadioError.invalid("Invalid PSK Reporter reception.") }
            sender += try variable(report.call)
            sender += number(report.frequency, 5) + [UInt8(bitPattern: report.snr)]
            sender += try variable("PKT")
            sender += [1] + number(UInt64(report.time), 4)
        }
        let body = receiverTemplate + senderTemplate + receiverData + set(0x9995, sender)
        guard body.count + 16 <= 1400 else { throw RadioError.invalid("PSK Reporter datagram exceeds 1400 bytes.") }
        return Data(number(10, 2) + number(UInt64(body.count + 16), 2) + number(UInt64(time), 4) + number(UInt64(sequence), 4) + number(UInt64(domain), 4) + body)
    }
}

@MainActor final class PSKReporter: ObservableObject {
    @Published var enabled: Bool { didSet { defaults?.set(enabled, forKey: "qso73.pskReporter.v1"); if !enabled { let session = started; stop(); started = session; status = "Off" } else { reset() } } }
    @Published private(set) var status = "Off"
    private let defaults: UserDefaults?
    private let destinationHost: String
    private let destinationPort: UInt16
    private var queue = PSKReportQueue()
    private var connection: NWConnection?
    private var generation = UUID()
    private var sending = false
    private var own = "", grid = ""
    private var started = Date.distantFuture
    private var sequence: UInt32 = 0
    private var domain = UInt32.random(in: 1...UInt32.max)
    private var timer: Task<Void, Never>?
    private var uploadTimeout: Task<Void, Never>?
    init(defaults: UserDefaults?, destinationHost: String = "report.pskreporter.info", destinationPort: UInt16 = 4739) { self.destinationHost = destinationHost; self.destinationPort = destinationPort; self.defaults = defaults; enabled = defaults?.bool(forKey: "qso73.pskReporter.v1") ?? false; status = enabled ? "Waiting for modem" : "Off" }
    func begin(call: String, grid: String) {
        stop(); own = PacketAddress.canonical(call); self.grid = grid.uppercased(); started = Date(); reset()
    }
    private func reset() {
        queue.clear(now: Date(), delay: Double.random(in: 300...330))
        guard enabled, started != .distantFuture else { status = enabled ? "Waiting for modem" : "Off"; return }
        guard StationSettings.validCallsign(own), PSKReportQueue.grid(grid) else { status = "Set a valid callsign and grid"; return }
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self?.flush()
            }
        }
        status = "Waiting for decoded stations and fresh CAT"
    }
    func stop() {
        generation = UUID(); uploadTimeout?.cancel(); uploadTimeout = nil; timer?.cancel(); timer = nil; connection?.cancel(); connection = nil
        sending = false; queue.clear(now: Date()); started = .distantFuture
        status = enabled ? "Waiting for modem" : "Off"
    }
    func receive(call: String, source: String, snr: Double, time: Date, frequency: UInt64?, catTime: Date) {
        guard enabled, PSKReportQueue.grid(grid), source == "ax25", let frequency,
              Date().timeIntervalSince(catTime) >= 0, Date().timeIntervalSince(catTime) <= 30 else { return }
        if queue.add(call: call, own: own, frequency: frequency, snr: snr, received: time, since: started, now: Date()) {
            status = "\(queue.reports.count) queued · sends about every 5 min"
            flush()
        }
    }
    func flush(now: Date = Date()) {
        guard enabled, !sending, started != .distantFuture else { return }
        queue.expire(now: now)
        guard !queue.reports.isEmpty, now >= queue.due else { return }
        do {
            let reports = queue.reports
            let bytes = try PSKReportQueue.encode(receiver: own, grid: grid, software: "QSO73 0.4.15 / modem73 2.4.2", reports: reports, sequence: sequence, domain: domain, time: UInt32(now.timeIntervalSince1970))
            if connection == nil {
                let c = NWConnection(host: NWEndpoint.Host(destinationHost), port: NWEndpoint.Port(rawValue: destinationPort)!, using: .udp)
                connection = c; c.start(queue: DispatchQueue(label: "org.qso73.psk-reporter"))
            }
            guard let connection else { return }
            sending = true; let token = generation
            uploadTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self, self.generation == token, self.sending else { return }
                self.generation = UUID(); self.connection?.cancel(); self.connection = nil; self.sending = false
                self.queue.retry(now: Date()); self.status = "Internet timeout · retry in 5 min"
            }
            connection.send(content: bytes, completion: .contentProcessed { [weak self] failure in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.enabled else { return }
                    self.uploadTimeout?.cancel(); self.uploadTimeout = nil
                    self.sending = false
                    if let failure { self.connection?.cancel(); self.connection = nil; self.queue.retry(now: Date()); self.status = "UDP error: \(failure.localizedDescription)" }
                    else {
                        self.sequence &+= UInt32(reports.count)
                        // Keep any receptions that arrived while the UDP write was pending.
                        self.queue.reports.removeAll { reports.contains($0) }
                        self.queue.retry(now: Date())
                        self.status = "\(reports.count) submitted via UDP · delivery unconfirmed"
                    }
                }
            })
        } catch { status = error.localizedDescription; queue.retry(now: now) }
    }
}
