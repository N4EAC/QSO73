import SwiftUI

struct RecipientControls: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var callsigns: CallsignList
    @State private var showAdd = false
    @State private var newCall = ""
    @State private var error = ""
    private var options: [String] {
        let values = callsigns.destinations
        return values.contains(workspace.chatTarget) ? values : values + [workspace.chatTarget]
    }
    var body: some View {
        HStack(spacing: 10) {
            Picker("To", selection: $workspace.chatTarget) {
                ForEach(options, id: \.self) { call in Text(call == "QST" ? "QST · Broadcast" : call).tag(call) }
            }.frame(width: 180)
            Button("Add Callsign…") { newCall = ""; error = ""; showAdd = true }
            Button("Clear Callsigns") { callsigns.clear(); workspace.chatTarget = "QST" }
                .disabled(callsigns.callsigns.isEmpty)
                .help("Clears this session's destination list and selects QST. Chat history and direct conversations are kept. New traffic can add callsigns again.")
        }
        .sheet(isPresented: $showAdd) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add a destination callsign").font(.headline)
                TextField("Callsign / optional SSID", text: $newCall).textFieldStyle(.roundedBorder)
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Button("Cancel") { showAdd = false }
                    Spacer()
                    Button("Select Callsign") {
                        let call = PacketAddress.canonical(newCall.trimmingCharacters(in: .whitespacesAndNewlines))
                        guard StationSettings.validCallsign(call) else { error = "Enter a valid callsign with optional SSID 0–15."; return }
                        callsigns.remember(call); workspace.chatTarget = call; showAdd = false
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 360)
        }
    }
}
