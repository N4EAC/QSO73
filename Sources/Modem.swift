import Foundation
import Network
import Combine

struct ActivitySample: Identifiable {
    let id = UUID()
    let level: Double
    let state: String
    let occupancy: Double
}
struct RecentModemFrame: Identifiable {
    let id: UInt64
    let time: Date
    let size: Int
    let mode: String
    let callsign: String
    let snr: Double
    let ber: Double
    let metadata: [String: String]
}

@MainActor final class Modem: ObservableObject {
    let reporter: PSKReporter
    private var reportedDial: Double?
    private var reportedCATTime = Date.distantPast
    private var reportedModeTime = Date.distantPast
    private var heard = HeardSession()
    private var heardBook = HeardBook()
    private var lastHeardQuery = Date.distantPast
    @Published var autoHeardReply = false { didSet { pingDefaults?.set(autoHeardReply, forKey: "qso73.autoHeardReply.v1"); if !autoHeardReply { heard.clearPending() } } }
    @discardableResult func sendHeardQuery(to target: String, query: String) -> Bool {
        guard attached, audioConnected else { error = "Connect modem audio before querying."; return false }
        guard Date().timeIntervalSince(lastHeardQuery) >= 60 else { error = "Wait one minute between Heard queries."; return false }
        let target = PacketAddress.canonical(target), query = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard target == "QST" || StationSettings.validCallsign(target) else { error = "Select QST or a station callsign."; return false }
        do {
            error = nil; send(try HeardMessage(k: "request", id: UUID().uuidString, q: query.isEmpty ? nil : query).encoded(), to: target, automatic: true)
            if error == nil { lastHeardQuery = Date(); return true }
        } catch { self.error = error.localizedDescription }
        return false
    }
    private func sendHeardReply() {
        guard autoHeardReply, automaticTransmissionReady else { return }
        do { if let reply = try heard.reply(now: Date(), history: heardBook) { send(reply.1, to: reply.0, automatic: true); lastAutomaticSubmission = Date() } }
        catch { log("Heard reply skipped: " + error.localizedDescription); heard.clearPending() }
    }
    private var ping = PingSession()
    private var pingDefaults: UserDefaults?
    @Published var autoPingReply = false { didSet { pingDefaults?.set(autoPingReply, forKey: "qso73.autoPingReply.v1"); if !autoPingReply { ping.clearPending() } } }
    func sendPing(to target: String) {
        guard attached, audioConnected else { error = "Connect modem audio before sending PING."; return }
        let target = PacketAddress.canonical(target)
        guard target == "QST" || StationSettings.validCallsign(target) else { error = "Select QST or a station callsign for PING."; return }
        do { send(try PingMessage(k: "request", id: UUID().uuidString).encoded(), to: target, automatic: true) }
        catch { self.error = error.localizedDescription }
    }
    private func sendPingReply() {
        guard autoPingReply, automaticTransmissionReady else { return }
        let frames = recentFrames
        do {
            if let reply = try ping.reply(own: PacketAddress.canonical(station.callsign), grid: station.locator, now: Date(), snr: { request in
                frames.first { $0.callsign == request.source && $0.metadata["application_id"] == request.id && abs($0.time.timeIntervalSince(request.received)) <= 5 && $0.metadata["snr"].flatMap(Double.init)?.isFinite == true && $0.snr.isFinite }?.snr
            }) { send(reply.1, to: reply.0, automatic: true); lastAutomaticSubmission = Date() }
        } catch { log("PING reply skipped: " + error.localizedDescription); ping.clearPending() }
    }
    let beacon = BeaconController()
    let rooms: ChatRooms
    let callsigns = CallsignList()
    let channelAnnouncements = ChannelAnnouncements()
    private var lastAutomaticSubmission = Date.distantPast
    private var automaticTransmissionReady: Bool {
        attached && configLoaded && audioConnected && channel == "idle" && txQueue == 0 && Date().timeIntervalSince(lastAutomaticSubmission) >= 5
    }
    @Published var status = "Offline"
    @Published var attached = false
    @Published var connecting = false
    @Published var snr = "—"
    @Published var channel = "idle"
    @Published var audioConnected = false
    @Published var rxAudioLevel: Double?
    @Published var rigConnected = false
    @Published var frequency = "—"
    @Published var frequencyFeedback = ""
    private var requestedFrequency: Int64?
    @Published var radioMode = "—"
    @Published var activeMode = "—"
    @Published var activity: [ActivitySample] = []
    @Published var recentFrames: [RecentModemFrame] = []
    @Published var statusDetails: [String: String] = [:]
    @Published var configDetails: [String: String] = [:]
    @Published var rigMeters: [String: String] = [:]
    @Published private(set) var radioPTT: Bool?
    private var radioPTTTime = Date.distantPast
    private var transmitMeterTimes: [String: Date] = [:]
    private let transmitMeters = ["RFPOWER_METER_WATTS", "SWR", "ALC"]
    @Published var recentTX: [RecentModemFrame] = []
    @Published var snrHistory: [Double] = []
    @Published var decoding = false
    private var decoderStateTime = Date.distantPast
    @Published var dcdActive = false
    @Published var pttOn = false
    @Published var txQueue = 0
    private var rigMeterIndex = 0
    private let meterCommands = ["STRENGTH", "TEMP_METER", "TUNER"]
    @Published var rxErrors = 0
    @Published var occupancy = 0
    @Published var clients = 0
    @Published var lastBER: Double?
    @Published var carrierThreshold: Double?
    @Published var csmaDescription = "—"
    private var lastFrameSequence: UInt64 = 0
    @Published var rxCount = 0
    @Published var txCount = 0
    @Published var entries: [ChatEntry] = []
    @Published var events: [String] = []
    @Published var error: String?
    private var control: NWConnection?
    private var kiss: NWConnection?
    private var ready = Set<String>()
    private var generation = UUID()
    private var timeout: Task<Void, Never>?
    private var polling: Task<Void, Never>?
    private var requestTimeout: Task<Void, Never>?
    private var kissFramer = KISSFramer()
    private var controlFramer = JSONControlFramer()
    private var station = StationSettings()
    private var config = Modem73Settings()
    private var mtu = 0
    private var fragmentation = false
    private var configLoaded = false
    private let engine = EmbeddedEngine()
    private let rigController = RigController()
    @Published var audioRoute = "Audio not opened"
    @Published var captureRoute = "Audio not opened"
    private let queue = DispatchQueue(label: "org.qso73.modem73.network")
    private struct Request { let object: [String: Any]; let purpose: String }
    private var requests: [Request] = []
    private var pending: Request?

    init(chatDefaults: UserDefaults? = .standard) {
        autoHeardReply = chatDefaults?.bool(forKey: "qso73.autoHeardReply.v1") ?? false
        reporter = PSKReporter(defaults: chatDefaults)
        rooms = ChatRooms(defaults: chatDefaults)
        pingDefaults = chatDefaults; autoPingReply = chatDefaults?.bool(forKey: "qso73.autoPingReply.v1") ?? false
        beacon.canSend = { [weak self] in
            guard let self else { return false }
            return self.automaticTransmissionReady
        }
        beacon.transmit = { [weak self] message in
            guard let self else { throw RadioError.invalid("Modem unavailable.") }
            self.error = nil
            self.send(message, to: "QST", automatic: true)
            if let error = self.error { throw RadioError.invalid(error) }
            self.lastAutomaticSubmission = Date()
        }
        channelAnnouncements.canSend = { [weak self] in self?.automaticTransmissionReady == true }
        channelAnnouncements.hasParticipant = { [weak self] room, now in self?.rooms.hasParticipant(in: room, now: now) == true }
        channelAnnouncements.transmit = { [weak self] room in
            guard let self, self.rooms.joined.contains(room) else { throw RadioError.invalid("Join the channel before announcing it.") }
            var topic = self.rooms.topics[room] ?? ""
            while (try? RoomEnvelope(kind: "announce", room: room, text: topic).encoded()) == nil && !topic.isEmpty { topic.removeLast() }
            self.error = nil; self.sendRoom(topic, room: room, kind: "announce")
            if let error = self.error { throw RadioError.invalid(error) }
            self.lastAutomaticSubmission = Date()
        }
        rooms.onParticipantHeard = { [weak self] room in self?.channelAnnouncements.participantHeard(in: room) }
        rooms.onLeave = { [weak self] room in self?.channelAnnouncements.left(room) }
        engine.onLog = { [weak self] text in
            self?.log("Engine: \(text)")
            for line in text.components(separatedBy: .newlines) {
                if line.hasPrefix("Playback: ") { self?.audioRoute = String(line.dropFirst("Playback: ".count)) }
                if line.hasPrefix("Capture: ") { self?.captureRoute = String(line.dropFirst("Capture: ".count)) }
            }
        }
        rigController.onLog = { [weak self] in self?.log($0) }
        rigController.onExit = { [weak self] code in
            guard let self, self.attached || self.connecting else { return }
            self.fail("Managed rigctld exited (status \(code)).")
        }
        engine.onExit = { [weak self] code in
            guard let self else { return }
            if !self.attached && !self.connecting { self.rigController.stop(); return }
            guard self.config.embedded else { return }
            self.fail("modem73 exited (status \(code)). Check the modem events and audio/PTT settings.")
        }
    }
    func log(_ message: String) {
        events.append("\(Date().formatted(date: .omitted, time: .standard))  \(message)")
        if events.count > 1000 { events.removeFirst(events.count - 1000) }
    }
    func attach(_ station: StationSettings, modem settings: Modem73Settings, rig: RigSettings = RigSettings()) async {
        do { try settings.validate(station: station) } catch { self.error = error.localizedDescription; return }
        guard !attached, !connecting else { return }
        guard !engine.isRunning else { error = "The modem is still stopping. Wait before restarting."; return }
        detach(); error = nil
        self.station = station; self.station.callsign = PacketAddress.canonical(station.callsign); config = settings
        connecting = true
        let current = generation
        if settings.embedded {
            status = "Checking microphone permission…"
            log("Microphone authorization check started.")
            guard await EmbeddedEngine.audioPermission() else {
                if generation == current { fail("Microphone access is needed for radio audio. Enable it for QSO73 in System Settings → Privacy & Security → Microphone.") }
                return
            }
            guard generation == current else { return }
            log("Microphone permission granted.")
            status = "Preparing CAT and radio audio…"
            do {
                if settings.ptt == "rigctl" {
                    log("Checking rigctld at \(station.rigHost):\(station.rigPort)…")
                    try await rigController.prepare(rig, station: station)
                    guard generation == current else { return }
                }
                let devices = try await EmbeddedEngine.audioDevices()
                guard generation == current else { return }
                guard devices.input.contains(settings.inputDevice), devices.output.contains(settings.outputDevice) else {
                    throw RadioError.invalid("The selected radio audio device is unavailable. Refresh Audio Devices and select its input and output.")
                }
                try engine.launch(station: station, settings: settings)
            }
            catch { if generation == current { fail(error.localizedDescription) }; return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard generation == current, engine.isRunning else { return }
        }
        openSockets(generation: current)
    }
    // External mode is also used by the loopback tests without opening audio devices.
    func attachExternal(_ station: StationSettings, modem settings: Modem73Settings) {
        var settings = settings
        settings.embedded = false
        do { try settings.validate(station: station) } catch { self.error = error.localizedDescription; return }
        guard !attached, !connecting else { return }
        detach(); error = nil
        self.station = station; self.station.callsign = PacketAddress.canonical(station.callsign); config = settings; config.embedded = false
        connecting = true
        openSockets(generation: generation)
    }
    private func openSockets(generation current: UUID) {
        let host = config.embedded ? "127.0.0.1" : config.host
        status = "Connecting to modem73…"
        control = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(config.connectionControlPort))!, using: .tcp)
        kiss = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(config.connectionKISSPort))!, using: .tcp)
        start(control!, channel: "control", generation: current)
        start(kiss!, channel: "KISS", generation: current)
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, self.generation == current, !self.attached else { return }
            self.fail("modem73 connection timed out. Check the engine, host, ports, and audio devices.")
        }
    }
    private func start(_ connection: NWConnection, channel: String, generation current: UUID) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                switch state {
                case .ready:
                    self.ready.insert(channel)
                    self.receive(connection, channel: channel, generation: current)
                    if self.ready.count == 2 {
                        self.timeout?.cancel(); self.attached = true; self.connecting = false; self.status = "modem73 ready"
                        self.log("KISS and JSON control channels connected.")
                        self.heardBook.begin(own: self.station.callsign, now: Date())
                        self.reporter.begin(call: self.station.callsign, grid: self.station.locator)
                        self.beacon.start()
                        self.channelAnnouncements.start()
                        self.request(["cmd": "get_config"], purpose: "config")
                        self.request(["cmd": "get_status"], purpose: "status")
                        self.request(["cmd": "rx_frame_history", "limit": 8], purpose: "history")
                        self.polling = Task { [weak self] in
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                guard !Task.isCancelled, let self, self.generation == current else { return }
                                if Date().timeIntervalSince(self.decoderStateTime) > 3 { self.decoding = false }
                                self.sendPingReply()
                                self.sendHeardReply()
                                if self.pending == nil && self.requests.isEmpty {
                                    self.request(["cmd": "get_status"], purpose: "status")
                                    if self.config.catEnabled {
                                        self.request(["cmd": "rigctl", "command": "+t"], purpose: "radioPTT")
                                        self.request(["cmd": "rigctl", "command": "f"], purpose: "frequency")
                                        self.request(["cmd": "rigctl", "command": "m"], purpose: "mode")
                                        if self.rigConnected {
                                            self.request(["cmd": "rigctl", "command": "+l RFPOWER"], purpose: "meter:RFPOWER")
                                            let meter = self.meterCommands[self.rigMeterIndex % self.meterCommands.count]
                                            self.rigMeterIndex += 1
                                            self.request(["cmd": "rigctl", "command": (meter == "TUNER" ? "u " : "l ") + meter], purpose: "meter:" + meter)
                                        }
                                    }
                                }
                            }
                        }
                    }
                case .failed(let e): self.fail("\(channel) channel: \(e.localizedDescription)")
                case .waiting(let e): self.log("\(channel) waiting: \(e.localizedDescription)")
                default: break
                }
            }
        }
        connection.start(queue: queue)
    }
    private func receive(_ connection: NWConnection, channel: String, generation current: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] bytes, _, complete, failure in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                do {
                    if let bytes, !bytes.isEmpty {
                        if channel == "control" {
                            for object in try self.controlFramer.feed(bytes) { self.handleControl(object) }
                        } else {
                            for frame in try self.kissFramer.feed(bytes) {
                                do {
                                    let packet = try RadioPacket.decode(frame)
                                    self.heardBook.observe(call: packet.source, snr: nil, time: Date(), now: Date(), packetFallback: true)
                                    let destination = packet.destination.uppercased()
                                    guard destination == self.station.callsign || ["QST", "CQ", "ALL"].contains(destination) else { continue }
                                    self.append(ChatEntry(direction: "\(packet.source) → \(packet.destination)", text: packet.text, source: packet.source, destination: packet.destination))
                                } catch { self.log("Received \(frame.count) bytes of non-chat KISS data.") }
                            }
                        }
                    }
                    if let failure { self.fail(failure.localizedDescription) }
                    else if complete { self.fail("modem73 closed its \(channel) channel.") }
                    else if self.generation == current { self.receive(connection, channel: channel, generation: current) }
                } catch { self.fail(error.localizedDescription) }
            }
        }
    }
    private func append(_ original: ChatEntry) {
        var entry = original
        do {
            if entry.text.hasPrefix(HeardMessage.prefix) {
                guard let readable = try heard.receive(entry.text, source: PacketAddress.canonical(entry.source ?? ""), destination: PacketAddress.canonical(entry.destination ?? ""), own: PacketAddress.canonical(station.callsign), outgoing: entry.direction.hasPrefix("You"), enabled: autoHeardReply, now: entry.time, delay: Double.random(in: 4...24)) else { return }
                entry.text = readable; entry.automatic = true
            }
            if entry.text.hasPrefix(PingMessage.prefix) {
                guard let readable = try ping.receive(entry.text, source: PacketAddress.canonical(entry.source ?? ""), destination: PacketAddress.canonical(entry.destination ?? ""), own: PacketAddress.canonical(station.callsign), outgoing: entry.direction.hasPrefix("You"), enabled: autoPingReply, now: entry.time) else { return }
                entry.text = readable; entry.automatic = true
            }
            guard let routed = try rooms.route(entry, local: station.callsign, outgoing: entry.direction.hasPrefix("You")) else { return }
            let other = entry.direction.hasPrefix("You") ? entry.destination : entry.source
            if let other { callsigns.remember(other, excluding: station.callsign) }
            entries.append(routed)
        } catch { log("Ignored invalid QSO73 conversation packet: \(error.localizedDescription)") }
        if entries.count > 2000 { entries.removeFirst(entries.count - 2000) }
    }
    private func request(_ object: [String: Any], purpose: String) {
        guard attached, requests.count < 20 else { return }
        requests.append(Request(object: object, purpose: purpose)); pumpRequests()
    }
    private func pumpRequests() {
        guard attached, pending == nil, !requests.isEmpty, let control else { return }
        let request = requests.removeFirst(); pending = request
        let current = generation
        do {
            let bytes = try JSONControlFramer.encode(request.object)
            control.send(content: bytes, completion: .contentProcessed { [weak self] failure in
                if let failure { Task { @MainActor [weak self] in
                    guard let self, self.generation == current else { return }
                    self.fail(failure.localizedDescription)
                } }
            })
            requestTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled, let self, self.generation == current, self.pending != nil else { return }
                // No request IDs: reconnect rather than matching a late response to another request.
                self.fail("modem73 control request timed out (\(request.purpose)).")
            }
        } catch { fail(error.localizedDescription) }
    }
    private func handleControl(_ object: [String: Any]) {
        if let event = object["event"] as? String {
            if event == "decoder_state" {
                decoding = object["decoding"] as? Bool ?? false
                decoderStateTime = Date()
            }
            if event == "rx_frame" { recordFrame(object) }
            if event == "config_changed" { request(["cmd": "get_config"], purpose: "config") }
            return
        }
        guard let request = pending else { log("Ignoring an unsolicited control response."); return }
        pending = nil; requestTimeout?.cancel(); requestTimeout = nil
        defer { pumpRequests() }
        if object["ok"] as? Bool == false {
            if request.purpose == "tune" || request.purpose == "tuneReadback" { requestedFrequency = nil; frequencyFeedback = "Frequency change failed" }
            error = "modem73 rejected \(request.purpose): \(object["error"] ?? "unknown error")"; return
        }
        if request.purpose.hasPrefix("meter:") {
            let key = String(request.purpose.dropFirst(6))
            let response = (object["response"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if transmitMeters.contains(key) && radioPTT != true { rigMeters[key] = nil; return }
            if let value = RigTelemetry.number(response) {
                rigMeters[key] = RigTelemetry.display(value)
                if transmitMeters.contains(key) { transmitMeterTimes[key] = Date() }
                if key == "RFPOWER" {
                    rigMeters["RFPOWER_SET_WATTS"] = nil
                    if let command = RigTelemetry.powerConversion(fraction: value, frequency: frequency, mode: radioMode) {
                        self.request(["cmd": "rigctl", "command": command], purpose: "powerSettingWatts")
                    }
                }
            } else { rigMeters[key] = "Unavailable" }
            return
        }
        switch request.purpose {
        case "radioPTT", "radioPTTVerify":
            let value = RigTelemetry.number(object["response"] as? String ?? "")
            radioPTT = value == 0 ? false : [1.0, 2.0, 3.0].contains(value ?? -1) ? true : nil
            radioPTTTime = Date()
            if radioPTT != true {
                for key in transmitMeters { rigMeters[key] = nil }
                transmitMeterTimes = [:]
            } else if request.purpose == "radioPTT", requests.count <= 16 {
                // Read the TX meters before slower frequency/mode polling, then
                // recheck PTT so an ended transmission cannot leave idle readings.
                let reads = transmitMeters.map { Request(object: ["cmd": "rigctl", "command": "+l " + $0], purpose: "meter:" + $0) }
                requests.insert(contentsOf: reads + [Request(object: ["cmd": "rigctl", "command": "+t"], purpose: "radioPTTVerify")], at: 0)
            }
        case "powerSettingWatts":
            if let milliwatts = RigTelemetry.number(object["response"] as? String ?? ""), milliwatts >= 0 {
                rigMeters["RFPOWER_SET_WATTS"] = RigTelemetry.display(milliwatts / 1000)
            } else { rigMeters["RFPOWER_SET_WATTS"] = nil }
        case "status":
            statusDetails = Self.scalarDetails(object)
            statusDetails["recent_tx_frames_available"] = object["recent_tx_frames"] is [[String: Any]] ? "1" : "0"
            if Date().timeIntervalSince(decoderStateTime) > 3 { decoding = false }
            dcdActive = object["dcd_active"] as? Bool ?? false
            pttOn = object["ptt_on"] as? Bool ?? false
            if let frames = object["recent_tx_frames"] as? [[String: Any]] {
                recentTX = frames.compactMap { frame in
                    guard let seq = (frame["seq"] as? NSNumber)?.uint64Value else { return nil }
                    return RecentModemFrame(id: seq,
                        time: Date(timeIntervalSince1970: (frame["time"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970),
                        size: (frame["size"] as? NSNumber)?.intValue ?? 0,
                        mode: frame["mode"] as? String ?? "—", callsign: station.callsign, snr: 0, ber: -1,
                        metadata: Self.scalarDetails(frame))
                }
            }
            channel = object["channel_state"] as? String ?? "idle"
            audioConnected = object["audio_connected"] as? Bool ?? false
            if audioConnected, let level = (object["rx_audio_level_db"] as? NSNumber)?.doubleValue, level.isFinite {
                rxAudioLevel = min(0, max(-100, level))
            } else { rxAudioLevel = nil }
            rigConnected = object["rigctl_connected"] as? Bool ?? false
            txQueue = (object["tx_queue"] as? NSNumber)?.intValue ?? 0
            rxErrors = (object["rx_error_count"] as? NSNumber)?.intValue ?? 0
            occupancy = (object["occupancy_pct"] as? NSNumber)?.intValue ?? 0
            clients = (object["client_count"] as? NSNumber)?.intValue ?? 0
            if let ber = (object["last_ber"] as? NSNumber)?.doubleValue, ber.isFinite, ber >= 0 { lastBER = ber * 100 } else { lastBER = nil }
            if let level = rxAudioLevel {
                activity.append(ActivitySample(level: level, state: channel, occupancy: Double((object["occupancy_total_pct"] as? NSNumber)?.intValue ?? occupancy)))
                if activity.count > 90 { activity.removeFirst(activity.count - 90) }
            }
            rxCount = (object["rx_frame_count"] as? NSNumber)?.intValue ?? 0
            txCount = (object["tx_frame_count"] as? NSNumber)?.intValue ?? 0
            if let frame = recentFrames.first { snr = String(format: "%.1f dB", frame.snr) }
            else if rxCount > 0, let n = object["last_snr"] as? NSNumber { snr = String(format: "%.1f dB", n.doubleValue) }
            status = audioConnected ? "modem73 · \(channel)" : "modem73 · audio unavailable"
        case "config":
            configDetails = Self.scalarDetails(object)
            mtu = max(0, ((object["payload_size"] as? NSNumber)?.intValue ?? 0) - 2)
            fragmentation = object["fragmentation_enabled"] as? Bool ?? false
            activeMode = object["modulation"] as? String ?? "—"
            configLoaded = true
            carrierThreshold = (object["carrier_threshold_db"] as? NSNumber)?.doubleValue
            csmaDescription = object["csma_enabled"] as? Bool == true ? (object["csma_sync_only"] as? Bool == true ? "ON · sync" : "ON · level") : "OFF"
            if let call = object["callsign"] as? String, call.uppercased() != String(station.callsign.split(separator: "-")[0]) {
                log("Modem callsign \(call) differs from chat source \(station.callsign). Configure the modem station identity before transmitting.")
            }
        case "history":
            if let frames = object["frames"] as? [[String: Any]] {
                for frame in frames.reversed() { recordFrame(frame) }
            }
        case "frequency", "tuneReadback":
            let response = object["response"] as? String ?? ""
            if let hz = Double(response.trimmingCharacters(in: .whitespacesAndNewlines)), hz.isFinite, hz > 0 {
                reportedDial = hz; reportedCATTime = Date()
                frequency = String(format: "%.6f MHz", hz / 1_000_000)
                if request.purpose == "tuneReadback", let expected = requestedFrequency {
                    if abs(hz - Double(expected)) <= 1 { frequencyFeedback = "Radio confirmed \(frequency)" }
                    else { frequencyFeedback = "Radio readback: \(frequency)"; error = "Requested \(String(format: "%.6f", Double(expected) / 1_000_000)) MHz, but the radio reports \(frequency)." }
                    requestedFrequency = nil
                }
            } else {
                reportedDial = nil; reportedCATTime = .distantPast
                frequency = "Unavailable"
                if request.purpose == "tuneReadback" { frequencyFeedback = "Frequency readback failed"; requestedFrequency = nil; error = "Cannot confirm the radio frequency: \(response)" }
            }
        case "mode":
            reportedModeTime = Date()
            let response = object["response"] as? String ?? ""
            let modeLines = response.components(separatedBy: .newlines)
            rigMeters["BANDWIDTH"] = modeLines.count > 1 && Int(modeLines[1]) != nil ? modeLines[1] : "Unavailable"
            radioMode = response.hasPrefix("ERR") || response.hasPrefix("RPRT") ? "Unavailable" : response.components(separatedBy: .newlines).first ?? "—"
        case "tune":
            let response = object["response"] as? String ?? ""
            if !response.contains("RPRT 0") { frequencyFeedback = "Frequency change failed"; requestedFrequency = nil; error = "Radio rejected frequency change: \(response)" }
            else { self.request(["cmd": "rigctl", "command": "f"], purpose: "tuneReadback") }
        default: break
        }
    }
    static func scalarDetails(_ object: [String: Any]) -> [String: String] {
        var details: [String: String] = [:]
        for (key, value) in object where key != "ok" && key != "event" {
            if let number = value as? NSNumber { details[key] = number.stringValue }
            else if let string = value as? String { details[key] = string }
        }
        return details
    }
    func transmitMeter(_ key: String, now: Date = Date()) -> String? {
        guard rigConnected, radioPTT == true, now.timeIntervalSince(radioPTTTime) <= 6,
              let time = transmitMeterTimes[key], now.timeIntervalSince(time) <= 6,
              let value = rigMeters[key], value != "Unavailable" else { return nil }
        return value
    }
    private func recordFrame(_ object: [String: Any]) {
        guard let seq = (object["seq"] as? NSNumber)?.uint64Value, seq > lastFrameSequence else { return }
        lastFrameSequence = seq
        let signal = (object["snr"] as? NSNumber)?.doubleValue ?? 0
        let ber = (object["ber_pct"] as? NSNumber)?.doubleValue ?? -1
        snr = String(format: "%.1f dB", signal)
        snrHistory.append(signal)
        if snrHistory.count > 32 { snrHistory.removeFirst() }
        recentFrames.insert(RecentModemFrame(id: seq,
            time: Date(timeIntervalSince1970: (object["time"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970),
            size: (object["size"] as? NSNumber)?.intValue ?? 0,
            mode: object["mode"] as? String ?? "—", callsign: object["callsign"] as? String ?? "",
            snr: signal, ber: ber, metadata: Self.scalarDetails(object)), at: 0)
        if recentFrames.count > 8 { recentFrames.removeLast() }
        if object["callsign_source"] as? String == "ax25", let received = (object["time"] as? NSNumber)?.doubleValue, received.isFinite {
            heardBook.observe(call: object["callsign"] as? String ?? "", snr: (object["snr"] as? NSNumber)?.doubleValue, time: Date(timeIntervalSince1970: received), now: Date())
        }

        if audioConnected, rigConnected, config.catEnabled,
           config.embedded || configDetails["center_freq"].flatMap(Double.init) == 1500,
           let measured = (object["snr"] as? NSNumber)?.doubleValue,
           let received = (object["time"] as? NSNumber)?.doubleValue,
           let dial = reportedDial, Date().timeIntervalSince(reportedModeTime) <= 30 {
            reporter.receive(call: object["callsign"] as? String ?? "", source: object["callsign_source"] as? String ?? "",
                             snr: measured, time: Date(timeIntervalSince1970: received),
                             frequency: PSKReportQueue.rfFrequency(dial: dial, mode: radioMode), catTime: reportedCATTime)
        }

    }
    func configureBeacon(_ settings: BeaconSettings, station: StationSettings, softwareVersion: String) throws {
        try beacon.configure(settings, station: station, softwareVersion: softwareVersion)
        if attached { beacon.start() }
    }
    func signalReport(for target: String, now: Date = Date()) -> Double? {
        let call = PacketAddress.canonical(target.trimmingCharacters(in: .whitespacesAndNewlines))
        return recentFrames.first { frame in
            PacketAddress.canonical(frame.callsign) == call && frame.snr.isFinite &&
            frame.metadata["snr"].flatMap(Double.init)?.isFinite == true &&
            now.timeIntervalSince(frame.time) >= -5 && now.timeIntervalSince(frame.time) <= 600
        }?.snr
    }
    func send(_ message: String, to destination: String, automatic: Bool = false) {
        guard attached, let kiss, configLoaded else { error = "Wait for the modem configuration before sending."; return }
        guard audioConnected else { error = "The modem's audio device is unavailable."; return }
        do {
            let target = destination.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let packet = try RadioPacket(source: station.callsign, destination: target, text: message).encode()
            guard fragmentation || packet.count <= mtu else { throw RadioError.invalid("This packet needs \(packet.count) bytes but the active mode allows \(mtu). Shorten it or enable fragmentation in modem73.") }
            let current = generation
            kiss.send(content: KISSFramer.encode(packet), completion: .contentProcessed { [weak self] failure in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == current else { return }
                    if let failure { self.fail(failure.localizedDescription) }
                    else {
                        self.append(ChatEntry(direction: "You → \(target) · submitted", text: message, source: self.station.callsign, destination: target, automatic: automatic))
                        self.log("Submitted AX.25 UI packet (\(packet.count) bytes); packet chat has no delivery acknowledgment.")
                    }
                }
            })
        } catch { self.error = error.localizedDescription }
    }
    func sendRoom(_ text: String, room: String, kind: String = "msg") {
        do {
            if room.hasPrefix("#") && !rooms.joined.contains(room) { throw RadioError.invalid("Join this channel before transmitting to it.") }
            let wire = try RoomEnvelope(kind: kind, room: room, text: text).encoded()
            send(wire, to: room.hasPrefix("#") ? "QST" : room)
        } catch { self.error = error.localizedDescription }
    }
    func tune(_ mhz: String) {
        guard attached, config.catEnabled, rigConnected else { error = "Start the modem with CAT enabled and connected before setting frequency."; return }
        guard let value = Double(mhz.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite, value > 0, value < 10_000 else { error = "Enter a frequency in MHz, for example 7.104 or 14.105."; return }
        guard channel == "idle" else { error = "Wait until the channel is idle before changing frequency."; return }
        guard requestedFrequency == nil else { error = "Wait for the current frequency change to finish."; return }
        let hz = Int64((value * 1_000_000).rounded())
        requestedFrequency = hz; frequencyFeedback = "Setting \(String(format: "%.6f", value)) MHz…"
        request(["cmd": "rigctl", "command": "F \(hz)"], purpose: "tune")
    }
    func detach() {
        channelAnnouncements.stop()
        heard.reset(); heardBook.clear(); lastHeardQuery = .distantPast
        ping.clearPending()
        beacon.stop()
        generation = UUID(); timeout?.cancel(); polling?.cancel(); requestTimeout?.cancel()
        timeout = nil; polling = nil; requestTimeout = nil
        control?.cancel(); kiss?.cancel(); control = nil; kiss = nil
        ready.removeAll(); kissFramer.reset(); controlFramer.reset(); requests.removeAll(); pending = nil
        rigController.cancelStartup()
        engine.stop()
        if !engine.isRunning { rigController.stop() }
        audioRoute = "Audio not opened"
        attached = false; connecting = false; channel = "idle"; audioConnected = false; rigConnected = false
        reporter.stop(); reportedDial = nil; reportedCATTime = .distantPast; reportedModeTime = .distantPast
        frequency = "—"; radioMode = "—"; snr = "—"; status = "Offline"; activeMode = "—"
        mtu = 0; configLoaded = false; fragmentation = false; rxCount = 0; txCount = 0
        rxAudioLevel = nil
        requestedFrequency = nil; frequencyFeedback = ""
        activity = []; recentFrames = []; recentTX = []; snrHistory = []; lastFrameSequence = 0
        statusDetails = [:]; configDetails = [:]; rigMeters = [:]; rigMeterIndex = 0; dcdActive = false; pttOn = false; decoding = false; decoderStateTime = .distantPast
        radioPTT = nil; radioPTTTime = .distantPast; transmitMeterTimes = [:]
        txQueue = 0; rxErrors = 0; occupancy = 0; clients = 0; lastBER = nil
        carrierThreshold = nil; csmaDescription = "—"; captureRoute = "Audio not opened"; audioRoute = "Audio not opened"
    }
    func shutdownForQuit() {
        detach()
        let deadline = Date().addingTimeInterval(5)
        while engine.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if !engine.isRunning { rigController.stop() }
    }
    private func fail(_ message: String) { detach(); error = message; log(message) }
}
