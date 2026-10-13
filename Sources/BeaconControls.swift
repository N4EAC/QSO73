import SwiftUI

struct BeaconControls: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var modem: Modem
    @ObservedObject var beacon: BeaconController
    var body: some View {
        HStack(spacing: 12) {
            Toggle("Beacon", isOn: $workspace.beaconSettings.enabled).toggleStyle(.checkbox)
            Picker("Interval", selection: $workspace.beaconSettings.intervalMinutes) {
                ForEach(1...60, id: \.self) { Text("\($0) min").tag($0) }
            }.frame(width: 130)
            Button("Beacon Now") { beacon.sendNow() }.disabled(!beacon.enabled || !modem.attached || !modem.audioConnected)
            TimelineView(.periodic(from: .now, by: 1)) { time in
                if let due = beacon.nextDue {
                    Text(beacon.status + " · next in \(max(0, Int(due.timeIntervalSince(time.date))))s")
                } else { Text(beacon.status) }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: workspace.beaconSettings.enabled) { _ in workspace.applyBeacon(to: modem) }
        .onChange(of: workspace.beaconSettings.intervalMinutes) { _ in workspace.applyBeacon(to: modem) }
    }
}
