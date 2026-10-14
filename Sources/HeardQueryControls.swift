import SwiftUI

struct HeardQueryForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var modem: Modem
    let target: String
    @State private var query = ""
    @State private var specific = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Heard query to \(target)").font(.title2.bold())
            Picker("Ask for", selection: $specific) {
                Text("Recent callsigns").tag(false)
                Text("A specific callsign").tag(true)
            }.pickerStyle(.segmented)
            if specific { TextField("Callsign, for example K1ABC or K1ABC-7", text: $query).textFieldStyle(.roundedBorder) }
            Text("Checks the receiving stations’ history from the last hour of their current modem session. Recent replies list up to three other callsigns, reception ages and available SNR. Stations must enable Auto Heard replies.").font(.callout)
            Text("QST asks all listening stations. Replies are addressed to you, wait for a clear channel, and are not guaranteed. Allow one minute between queries.").font(.caption).foregroundStyle(.secondary)
            if let error = modem.error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Send query") { if modem.sendHeardQuery(to: target, query: specific ? query : "") { dismiss() } }.buttonStyle(.borderedProminent).disabled(specific && !StationSettings.validCallsign(query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())) }
        }.padding(22).frame(width: 470)
    }
}
