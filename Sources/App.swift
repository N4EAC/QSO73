import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class Workspace: ObservableObject {
    @Published var settings = StationSettings()
    @Published var modemSettings = Modem73Settings()
    @Published var rigSettings = RigSettings()
    @Published var chatDraft = ""
    @Published var chatTarget = "QST"
    private var draftRoom = "radio"
    private var roomDrafts: [String: String] = [:]
    func selectDraftRoom(_ room: String) {
        guard room != draftRoom else { return }
        roomDrafts[draftRoom] = chatDraft
        chatDraft = roomDrafts[room] ?? ""
        draftRoom = room
    }
    @Published var frequencyInput = ""
    @Published var showModemEvents = false
    @Published var radioMacros = RadioMacroSettings()
    @Published var macroStatus = ""
    @Published var beaconSettings = BeaconSettings()
    private var lastMacroTime = Date.distantPast
    @Published var error: String?
    private let settingsKey = "stationSettings.v1"
    init() {
        if let bytes = UserDefaults.standard.data(forKey: "beaconSettings.v1"), let value = try? JSONDecoder().decode(BeaconSettings.self, from: bytes) { beaconSettings = value }
        if let bytes = UserDefaults.standard.data(forKey: "radioMacros.v1"), let value = try? JSONDecoder().decode(RadioMacroSettings.self, from: bytes) { radioMacros = value }
        if let bytes = UserDefaults.standard.data(forKey: settingsKey), let s = try? JSONDecoder().decode(StationSettings.self, from: bytes) { settings = s }
        if let bytes = UserDefaults.standard.data(forKey: "modem73Settings.v1"), let s = try? JSONDecoder().decode(Modem73Settings.self, from: bytes) { modemSettings = s }
        if let bytes = UserDefaults.standard.data(forKey: "rigSettings.v1"), let value = try? JSONDecoder().decode(RigSettings.self, from: bytes) { rigSettings = value }
    }
    @discardableResult func save() -> Bool {
        do {
            try modemSettings.validate(station: settings)
            try beaconSettings.validate(station: settings)
            UserDefaults.standard.set(try JSONEncoder().encode(settings), forKey: settingsKey)
            UserDefaults.standard.set(try JSONEncoder().encode(modemSettings), forKey: "modem73Settings.v1")
            UserDefaults.standard.set(try JSONEncoder().encode(rigSettings), forKey: "rigSettings.v1")
            UserDefaults.standard.set(try JSONEncoder().encode(radioMacros), forKey: "radioMacros.v1")
            UserDefaults.standard.set(try JSONEncoder().encode(beaconSettings), forKey: "beaconSettings.v1")
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func importSettings() {
        let panel = NSOpenPanel(); panel.title = "Import QSO73 Settings"; panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = try QSO73SettingsProfile.decoded(Data(contentsOf: url))
            settings = profile.station; modemSettings = profile.modem; rigSettings = profile.radio
            if let macros = profile.macros { radioMacros = macros }
            if let beacon = profile.beacon { beaconSettings = beacon }
            save()
        } catch { self.error = error.localizedDescription }
    }
    func exportSettings() {
        let panel = NSSavePanel(); panel.title = "Export QSO73 Settings"; panel.nameFieldStringValue = "QSO73-settings.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try QSO73SettingsProfile(station: settings, modem: modemSettings, radio: rigSettings, macros: radioMacros, beacon: beaconSettings).encoded().write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func applyBeacon(to modem: Modem) {
        do {
            try modem.configureBeacon(beaconSettings, station: settings, softwareVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")
            UserDefaults.standard.set(try JSONEncoder().encode(beaconSettings), forKey: "beaconSettings.v1")
        } catch { beaconSettings.enabled = false; self.error = error.localizedDescription }
    }
    func transmitMacro(_ kind: RadioMacro, modem: Modem) {
        guard Date().timeIntervalSince(lastMacroTime) >= 1 else { return }
        do {
            guard modem.attached, modem.audioConnected else { throw RadioError.invalid("Start the modem and connect radio audio before transmitting a macro.") }
            let snr = modem.signalReport(for: chatTarget)
            let message = try radioMacros.message(kind, station: settings, target: chatTarget, snr: snr)
            modem.error = nil
            modem.send(message.text, to: message.destination)
            guard modem.error == nil else { return }
            lastMacroTime = Date()
            macroStatus = kind.label + " submitted to " + message.destination
        } catch { self.error = error.localizedDescription }
    }
    func exportChat(_ entries: [ChatEntry]) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "QSO73-chat.txt"; panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try entries.map { "[\($0.time.ISO8601Format())] \($0.direction): \($0.text)" }.joined(separator: "\n\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
}

@main struct QSO73App: App {
    @StateObject private var workspace = Workspace()
    @StateObject private var modem = Modem()
    @StateObject private var activityPresentation = ActivityPresentation()
    @StateObject private var engineUpdates = EngineUpdates()
    var body: some Scene {
        WindowGroup("QSO73") {
            MainView().environmentObject(workspace).environmentObject(modem).environmentObject(modem.rooms).environmentObject(activityPresentation).environmentObject(engineUpdates)
                .frame(minWidth: 1040, minHeight: 760)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in modem.shutdownForQuit() }
        }
        .commands {
            CommandMenu("Radio") {
                ForEach(RadioMacro.allCases, id: \.self) { kind in
                    Button(kind.label) { workspace.transmitMacro(kind, modem: modem) }
                        .keyboardShortcut(kind.shortcut, modifiers: [])
                        .disabled(!modem.attached || !modem.audioConnected || engineUpdates.busy || (kind == .custom && workspace.radioMacros.custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            CommandGroup(after: .newItem) {
                Button("Import QSO73 Settings…", action: workspace.importSettings).disabled(modem.attached || modem.connecting || engineUpdates.busy)
                Button("Export QSO73 Settings…", action: workspace.exportSettings)
                Button("Export Chat…") { workspace.exportChat(modem.entries) }
                Button("Undock Modem Activity") { activityPresentation.undock(modem) }
                Button("Dock Modem Activity") { activityPresentation.dock() }
            }
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case chat = "Radio Chat", activity = "Modem Activity", settings = "Station Settings"
    var id: Self { self }
    var icon: String {
        switch self {
        case .chat: return "antenna.radiowaves.left.and.right"
        case .activity: return "waveform.path"
        case .settings: return "gearshape"
        }
    }
}
struct MainView: View {
    @EnvironmentObject var activityPresentation: ActivityPresentation
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var modem: Modem
    @State private var selection: Section? = .chat
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                            Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                        }
                        Text("QSO73").font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    Text("POWERED BY MODEM73").font(.caption).tracking(2).foregroundStyle(.secondary)
                }.padding(.horizontal).padding(.top, 20)
                List(Section.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Text("TX audio: " + modem.audioRoute).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                        .frame(width: 188, height: 32, alignment: .topLeading)
                        .help("TX audio: " + modem.audioRoute)
                    HStack(spacing: 6) {
                        Text("RX audio").font(.caption)
                        Text(modem.rxAudioLevel.map { String(format: "%.0f dBFS", $0) } ?? "—")
                            .font(.caption).monospacedDigit()
                    }.foregroundStyle(.secondary)
                    ProgressView(value: (modem.rxAudioLevel ?? -100) + 100, total: 100)
                        .progressViewStyle(.linear).frame(width: 188, height: 8)
                        .help("Audio level from the selected input, refreshed every two seconds. A changing level confirms audio activity; a decoded packet confirms modem reception.")
                    Text(modem.statusDetails["recent_tx_frames_available"] == "1" ? "Decoded packets: \(modem.rxCount)" : "Engine RX reported: \(modem.rxCount)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Divider().padding(.vertical, 4)
                    Label(modem.status, systemImage: modem.attached ? "circle.fill" : "circle")
                        .foregroundStyle(modem.attached ? .green : .secondary)
                        .lineLimit(1).help(modem.status)
                    Text(workspace.settings.callsign.isEmpty ? "Configure your station" : workspace.settings.callsign).font(.headline)
                    Text("modem73 · 0.4.9").font(.caption).foregroundStyle(.secondary)
                }.frame(width: 188, alignment: .leading).padding().layoutPriority(1)
            }.navigationSplitViewColumnWidth(220)
        } detail: {
            Group {
                switch selection ?? .chat {
                case .chat:
                    if activityPresentation.dockedVisible && !activityPresentation.isDetached {
                        VSplitView {
                            ChatView().frame(minHeight: 420)
                            ActivityPanel(modem: modem, presentation: activityPresentation, detached: false)
                                .frame(minHeight: 160, idealHeight: 240)
                        }
                    } else { ChatView() }
                case .activity:
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Modem Activity").font(.largeTitle.bold())
                            Spacer()
                            Button(activityPresentation.isDetached ? "Show Activity Window" : "Undock") { activityPresentation.undock(modem); selection = .chat }
                            Button("Dock with Chat") { activityPresentation.dock(); selection = .chat }
                        }
                        ScrollView { ModemActivityView(modem: modem).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                case .settings: SettingsView()
                }
            }.padding(24)
        }
        .alert("QSO73", isPresented: Binding(get: { workspace.error != nil || modem.error != nil }, set: { if !$0 { workspace.error = nil; modem.error = nil } })) {
            Button("OK") { workspace.error = nil; modem.error = nil }
        } message: { Text(workspace.error ?? modem.error ?? "") }
    }
}
struct ChatView: View {
    @EnvironmentObject var rooms: ChatRooms
    @EnvironmentObject var engineUpdates: EngineUpdates
    @EnvironmentObject var activityPresentation: ActivityPresentation
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var modem: Modem
    private var visibleEntries: [ChatEntry] { modem.entries.filter { $0.conversation == rooms.selected } }
    private var canSendDraft: Bool {
        if rooms.selected == "radio" { return !workspace.chatDraft.isEmpty && workspace.chatDraft.utf8.count <= RadioPacket.maxTextBytes }
        return (try? RoomEnvelope(kind: "msg", room: rooms.selected, text: workspace.chatDraft).encoded()) != nil && (!rooms.selected.hasPrefix("#") || rooms.joined.contains(rooms.selected))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Radio Chat").font(.largeTitle.bold())
                    Text(workspace.modemSettings.embedded ? "Native modem73 · audio on this Mac" : "External modem73 · KISS packet chat").foregroundStyle(.secondary)
                }
                Spacer()
                Button(activityPresentation.isDetached ? "Activity Window" : "Modem Activity") {
                    if activityPresentation.isDetached { activityPresentation.undock(modem) }
                    else { activityPresentation.dockedVisible.toggle() }
                }
                Button(modem.attached || modem.connecting ? "Stop Modem" : (workspace.modemSettings.embedded ? "Start Modem" : "Connect Modem")) {
                    if modem.attached || modem.connecting { modem.detach() }
                    else if workspace.save() {
                        let station = workspace.settings, config = workspace.modemSettings, rig = workspace.rigSettings
                        Task {
                            workspace.applyBeacon(to: modem)
                            await modem.attach(station, modem: config, rig: rig)
                        }
                    }
                }.buttonStyle(.borderedProminent).disabled(engineUpdates.busy)
            }
            ChatRoomControls(workspace: workspace, modem: modem, rooms: rooms)
            HStack(spacing: 12) {
                if rooms.selected == "radio" {
                RecipientControls(workspace: workspace, callsigns: modem.callsigns)
                } else {
                    Text(rooms.selected.hasPrefix("#") ? "Channel: \(rooms.selected)" : "Direct: \(rooms.selected)")
                    Text("Shared radio airtime · messages are readable over the air").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(modem.activeMode) · SNR \(modem.snr)").font(.system(.caption, design: .monospaced))
            }
            HStack(spacing: 16) {
                Label(modem.audioConnected ? "Audio ready" : "Audio offline", systemImage: "waveform")
                Text("RX \(modem.rxCount) · TX \(modem.txCount)")
                Text("Decoding")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(modem.decoding && modem.attached ? Color.white : Color.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(modem.decoding && modem.attached ? Color.green.opacity(0.8) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    .help("Green while modem73 is receiving a frame for decoding. Gray when idle. A green indication does not guarantee a successfully decoded message.")

                Spacer()
                Label(modem.frequency + " · " + modem.radioMode, systemImage: "radio")
                if workspace.modemSettings.catEnabled {
                    TextField("MHz", text: $workspace.frequencyInput).frame(width: 95).textFieldStyle(.roundedBorder)
                        .help("Enter MHz, for example 7.104. Sets the radio dial using CAT.")
                    Button("Set Frequency") { modem.tune(workspace.frequencyInput) }.disabled(!modem.attached || !modem.rigConnected || modem.channel != "idle")
                        .help("Changes the radio dial frequency. Available when the modem is idle and CAT is connected.")
                }
            }.font(.caption).foregroundStyle(.secondary)
            if !modem.frequencyFeedback.isEmpty { Text(modem.frequencyFeedback).font(.caption).foregroundStyle(.secondary) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(visibleEntries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.direction).font(.caption.bold()).foregroundStyle(entry.direction.hasPrefix("You") ? .teal : .secondary)
                                    Spacer()
                                    Text(entry.time, style: .time).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(entry.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 10)).id(entry.id)
                        }
                    }.padding()
                }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: modem.entries.count) { _ in if let last = visibleEntries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    .onChange(of: rooms.selected) { value in
                        workspace.selectDraftRoom(value)
                        if value == "radio" { workspace.chatTarget = "QST" }
                        if !value.hasPrefix("#") && value != "radio" { workspace.chatTarget = value }
                        if let last = visibleEntries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
            }
            HStack {
                Button("PING") { modem.sendPing(to: rooms.selected.hasPrefix("#") ? "QST" : rooms.selected == "radio" ? workspace.chatTarget : rooms.selected) }.disabled(!modem.attached || !modem.audioConnected)
                    .help("Requests an automatic SNR/callsign/grid reply from the selected station, or from listening stations when To is QST.")
                Toggle("Auto PING replies", isOn: $modem.autoPingReply).toggleStyle(.checkbox)
                Text("Replies use measured SNR and your saved grid").font(.caption).foregroundStyle(.secondary)
            }
            BeaconControls(workspace: workspace, modem: modem, beacon: modem.beacon)
            HStack(spacing: 10) {
                ForEach(RadioMacro.allCases, id: \.self) { kind in
                    Button { workspace.transmitMacro(kind, modem: modem) } label: {
                        Text(kind.label).frame(width: 80, height: 22)
                    }
                        .buttonStyle(.bordered)
                        .disabled(!modem.attached || !modem.audioConnected || engineUpdates.busy || (kind == .custom && workspace.radioMacros.custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
                Text(workspace.macroStatus.isEmpty ? "F keys transmit immediately · Mac keyboards may require Fn" : workspace.macroStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom) {
                TextEditor(text: $workspace.chatDraft).font(.body).frame(height: 85).padding(6).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                Button("Send Packet") {
                    modem.error = nil
                    if rooms.selected == "radio" { modem.send(workspace.chatDraft, to: workspace.chatTarget) }
                    else { modem.sendRoom(workspace.chatDraft, room: rooms.selected) }
                    if modem.error == nil { workspace.chatDraft = "" }
                }
                    .keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent)
                    .disabled(!modem.attached || !modem.audioConnected || !canSendDraft)
            }
            HStack {
                Toggle("Modem events", isOn: $workspace.showModemEvents).toggleStyle(.checkbox)
                Text(rooms.selected == "radio" ? "\(workspace.chatDraft.utf8.count)/200 bytes · unacknowledged packets" : "\(workspace.chatDraft.utf8.count) text bytes · routing included in 200-byte packet limit\(canSendDraft || workspace.chatDraft.isEmpty ? "" : " · shorten message")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Export Chat…") { workspace.exportChat(modem.entries) }.disabled(modem.entries.isEmpty)
            }
            if workspace.showModemEvents {
                ScrollView { Text(modem.events.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 120)
            }
        }
    }
}
struct SettingsView: View {
    @StateObject private var radioModels = RadioModelCatalog()
    @State private var modelSearch = ""
    @EnvironmentObject var engineUpdates: EngineUpdates
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var modem: Modem
    @State private var saved = false
    @State private var listing = false
    @State private var inputs = ["default"]
    @State private var outputs = ["default"]
    @State private var serialDevices = RigSettings.serialDevices
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Station Settings").font(.largeTitle.bold())
            Form {
                stationSection
                engineSection
                audioSection
                modeSection
                pttSection
                macroSection
                beaconSection
            }.formStyle(.grouped).disabled(modem.attached || modem.connecting || engineUpdates.busy)
            HStack {
                Button("Import Settings…") { workspace.importSettings() }.disabled(modem.attached || modem.connecting)
                Button("Export Settings…") { workspace.exportSettings() }
                Button("Save") { saved = workspace.save() }.buttonStyle(.borderedProminent).disabled(modem.attached || modem.connecting)
                if saved { Text("Saved").foregroundStyle(.secondary) }
            }
            Text("The local engine uses radio audio on this Mac. CAT/PTT via rigctld can address a local or remote radio; a remote radio also needs an audio path to this Mac, or modem73 running at that station.").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: workspace.modemSettings.ptt) { value in
            if workspace.modemSettings.embedded && value != "rigctl" { workspace.modemSettings.catEnabled = false }
        }
        .onChange(of: workspace.modemSettings.embedded) { local in
            if local && workspace.modemSettings.ptt != "rigctl" { workspace.modemSettings.catEnabled = false }
        }
        .task { await radioModels.refresh() }
    }
    private var beaconSection: some View {
        SwiftUI.Section("Station beacon") {
            Toggle("Enable periodic beacon while connected", isOn: $workspace.beaconSettings.enabled)
            Stepper("Interval: \(workspace.beaconSettings.intervalMinutes) minutes", value: $workspace.beaconSettings.intervalMinutes, in: 1...60)
            Text("Broadcasts callsign, grid and QSO73 version to QST. First beacon follows one full interval; transmission waits for idle audio and an empty TX queue. Disconnecting stops the timer.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var macroSection: some View {
        SwiftUI.Section("Radio macros · transmit immediately") {
            TextField("F1 · CQ", text: $workspace.radioMacros.cq)
            TextField("F2 · SNR report", text: $workspace.radioMacros.report)
            TextField("F3 · 73", text: $workspace.radioMacros.goodbye)
            TextField("F4 · Custom message", text: $workspace.radioMacros.custom)
            Text("F4 sends to To, including QST broadcasts. Leave it blank to disable. All F keys submit plain Radio Chat packets immediately.").font(.caption).foregroundStyle(.secondary)
            Text("Tokens: {call}, {name}, {qth}, {locator}, {to}, {snr}. F1 broadcasts to QST; F2/F3 use To. Reports require a packet from that station in the last 10 minutes. Expanded messages are limited to 200 UTF-8 bytes.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var stationSection: some View {
        SwiftUI.Section("Station") {
            TextField("Callsign / SSID", text: $workspace.settings.callsign)
            TextField("Operator name", text: $workspace.settings.name)
            TextField("QTH", text: $workspace.settings.qth)
            TextField("Locator", text: $workspace.settings.locator)
        }
    }
    private var engineSection: some View {
        SwiftUI.Section("modem73 engine") {
            Toggle("Run local native modem on this Mac", isOn: $workspace.modemSettings.embedded)
            if workspace.modemSettings.embedded {
                Text(engineUpdates.selectionLabel).font(.caption)
                HStack {
                    Button("Check Updates") { Task { await engineUpdates.check() } }
                    Link("Upstream Releases", destination: URL(string: "https://github.com/RFnexus/modem73/releases")!)
                    Button("Install Local Engine…") {
                        let panel = NSOpenPanel(); panel.title = "Select modem73 from an unpacked macOS package"; panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url { Task { await engineUpdates.install(url) } }
                    }
                }.disabled(engineUpdates.busy)
                HStack {
                    Button("Use Bundled Engine") { engineUpdates.useBundled() }.disabled(engineUpdates.installed == nil || engineUpdates.busy)
                    Button("Use Previous Engine") { engineUpdates.rollback() }.disabled(engineUpdates.previous == nil || engineUpdates.busy)
                }
                if !engineUpdates.message.isEmpty { Text(engineUpdates.message).font(.caption).textSelection(.enabled) }
                Text("Install Local Engine selects a downloaded package and remains available even when up to date. Engine updates are stored outside QSO73. Install while the modem is stopped. Compatible upstream engines may provide fewer activity diagnostics than the QSO73 bundled build.").font(.caption).foregroundStyle(.secondary)
            }
            if !workspace.modemSettings.embedded {
                TextField("Remote modem host", text: $workspace.modemSettings.host)
                TextField("KISS port", value: $workspace.modemSettings.kissPort, formatter: portFormatter)
                TextField("Control port", value: $workspace.modemSettings.controlPort, formatter: portFormatter)
            }
            Text(workspace.modemSettings.embedded ? "The selected local engine listens on localhost only. It starts when you press Start Modem." : "The external modem must expose its KISS and JSON control sockets on a trusted reachable network.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var audioSection: some View {
        if workspace.modemSettings.embedded {
            SwiftUI.Section("Radio audio · automatic sample-rate conversion") {
                Picker("Input / radio receive", selection: $workspace.modemSettings.inputDevice) {
                    ForEach(deviceOptions(inputs, selected: workspace.modemSettings.inputDevice), id: \.self) { Text($0 == "default" ? "System default" : $0).tag($0) }
                }
                Picker("Output / radio transmit", selection: $workspace.modemSettings.outputDevice) {
                    ForEach(deviceOptions(outputs, selected: workspace.modemSettings.outputDevice), id: \.self) { Text($0 == "default" ? "System default" : $0).tag($0) }
                }
                Button(listing ? "Listing devices…" : "Refresh Audio Devices") {
                    listing = true
                    Task {
                        do { let devices = try await EmbeddedEngine.audioDevices(); inputs = devices.input; outputs = devices.output }
                        catch { workspace.error = error.localizedDescription }
                        listing = false
                    }
                }.disabled(listing)
                Text("Choose the radio USB device for both directions. System default may send TX audio to the Mac speakers. Stop and restart the modem after changing devices.").font(.caption).foregroundStyle(.secondary)
                Stepper("TX output level: \(workspace.modemSettings.txLevel)%", value: $workspace.modemSettings.txLevel, in: 5...100, step: 5)
            }
        }
    }
    @ViewBuilder private var modeSection: some View {
        if workspace.modemSettings.embedded {
            SwiftUI.Section("Modem mode") {
                Picker("Family", selection: $workspace.modemSettings.family) {
                    Text("ROBUST · fading HF").tag("robust")
                    Text("OFDM").tag("ofdm")
                    Text("MFSK · weak signals").tag("mfsk")
                }
                if workspace.modemSettings.family == "robust" {
                    Picker("ROBUST mode", selection: $workspace.modemSettings.robustMode) {
                        ForEach(["RDM-1200", "RDM-800", "RDM-600", "RDM-300", "RDMN-300", "RDMN-150", "RDM-1200S", "RDM-600S", "RDM-300S", "RDMN-300S", "RDMN-150S"], id: \.self) { Text($0).tag($0) }
                    }
                } else if workspace.modemSettings.family == "mfsk" {
                    Picker("MFSK mode", selection: $workspace.modemSettings.mfskMode) {
                        ForEach(["MFSK-8", "MFSK-16", "MFSK-32", "MFSK-32R"], id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    Picker("OFDM modulation · rate 1/2", selection: $workspace.modemSettings.modulation) {
                        ForEach(["BPSK", "QPSK", "8PSK", "QAM16"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Text("Fragmentation and sync-based carrier sensing are enabled. Changes apply on the next engine start.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var pttSection: some View {
        SwiftUI.Section("Radio PTT and CAT") {
            if workspace.modemSettings.embedded {
                Picker("PTT method", selection: $workspace.modemSettings.ptt) {
                    Text("None / audio bench").tag("none")
                    Text("rigctld (default)").tag("rigctl")
                    Text("VOX").tag("vox")
                    Text("Serial DTR/RTS").tag("com")
                }
                if workspace.modemSettings.ptt == "com" {
                    TextField("Serial device", text: $workspace.modemSettings.serialPort)
                    Picker("Serial line", selection: $workspace.modemSettings.serialLine) {
                        Text("RTS").tag("rts"); Text("DTR").tag("dtr"); Text("Both").tag("both")
                    }
                }
            }
            if workspace.modemSettings.ptt == "rigctl" || !workspace.modemSettings.embedded {
                Toggle("Read CAT frequency/mode and enable tuning", isOn: $workspace.modemSettings.catEnabled)
                if workspace.modemSettings.embedded {
                    TextField("rigctld host", text: $workspace.settings.rigHost)
                    TextField("rigctld port", value: $workspace.settings.rigPort, formatter: portFormatter)
                }
                if workspace.modemSettings.embedded {
                    Toggle("Start rigctld automatically", isOn: $workspace.rigSettings.automatic)
                    if workspace.rigSettings.automatic {
                        TextField("Find radio by brand, model or number", text: $modelSearch)
                        Picker("Radio model", selection: $workspace.rigSettings.model) {
                            if !radioModels.models.contains(where: { $0.id == workspace.rigSettings.model }) {
                                Text("\(workspace.rigSettings.model) · Saved model (not in current catalog)").tag(workspace.rigSettings.model)
                            }
                            ForEach(radioModels.models.filter { modelSearch.isEmpty || $0.id == workspace.rigSettings.model || $0.label.localizedCaseInsensitiveContains(modelSearch) }) { model in
                                Text(model.label).tag(model.id)
                            }
                        }
                        Button(radioModels.busy ? "Loading models…" : "Refresh Radio Models") { Task { await radioModels.refresh() } }.disabled(radioModels.busy)
                        Text(radioModels.message).font(.caption).foregroundStyle(.secondary)
                        Picker("CAT serial device", selection: $workspace.rigSettings.device) {
                            Text("Select a CAT serial device").tag("")
                            ForEach(deviceOptions(serialDevices, selected: workspace.rigSettings.device).filter { !$0.isEmpty }, id: \.self) { Text($0).tag($0) }
                        }
                        Button("Refresh Serial Devices") { serialDevices = RigSettings.serialDevices }
                        Picker("CAT baud rate", selection: $workspace.rigSettings.baud) {
                            ForEach([4800,9600,19200,38400,57600,115200], id: \.self) { Text(String($0)).tag($0) }
                        }
                    }
                }
                Text("An existing rigctld is reused. Otherwise QSO73 starts it for the selected serial port and matching radio baud rate. Hamlib must be installed. External modems manage their own rigctld.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func deviceOptions(_ devices: [String], selected: String) -> [String] { devices.contains(selected) ? devices : devices + [selected] }
    private var portFormatter: NumberFormatter { let f = NumberFormatter(); f.numberStyle = .none; f.allowsFloats = false; return f }
}

