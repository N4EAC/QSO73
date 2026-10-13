import SwiftUI

struct PSKReportingControls: View {
    @ObservedObject var reporter: PSKReporter
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("PSK Reporter reception reporting", isOn: $reporter.enabled)
            Text(reporter.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Text("Optional Internet uploads: received callsigns, frequency, SNR and time; your callsign/grid and QSO73 version. No chat text. Reports use PKT mode and require fresh CAT frequency/mode. USB/LSB reports include the modem’s 1500 Hz center offset.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
