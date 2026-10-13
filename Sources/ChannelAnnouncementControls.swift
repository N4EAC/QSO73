import SwiftUI

struct ChannelAnnouncementControls: View {
    let room: String
    @ObservedObject var announcements: ChannelAnnouncements
    var reportError: (String) -> Void
    private var state: ChannelAnnouncementState { announcements.states[room] ?? ChannelAnnouncementState() }
    private func configure(enabled: Bool, minutes: Int) {
        do { try announcements.configure(room: room, enabled: enabled, intervalMinutes: minutes) }
        catch { reportError(error.localizedDescription) }
    }
    var body: some View {
        HStack(spacing: 10) {
            Toggle("Announce until another station is heard", isOn: Binding(get: { state.enabled }, set: { configure(enabled: $0, minutes: state.intervalMinutes) })).toggleStyle(.checkbox)
            Picker("Every", selection: Binding(get: { state.intervalMinutes }, set: { configure(enabled: state.enabled, minutes: $0) })) {
                ForEach(1...60, id: \.self) { Text("\($0) min").tag($0) }
            }.frame(width: 115)
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                Text(state.status + (state.nextDue.map { " · \(max(0, Int($0.timeIntervalSince(clock.date))))s" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .help("Broadcasts this channel and its topic to QST. Stops after another station's join or channel message. Silent joins cannot be detected. Off when QSO73 is restarted.")
    }
}
