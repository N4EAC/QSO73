import SwiftUI
import AppKit
struct ContactLogView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var modem: Modem
    @ObservedObject var log: ContactLog
    @State private var record = Contact()
    @State private var message = ""
    var body: some View {
        VStack(alignment:.leading, spacing:12) {
            HStack { Text("Contact Log").font(.largeTitle.bold()); Spacer(); Button("New Contact",action:newContact); Button("Export ADIF…",action:export).disabled(log.contacts.isEmpty) }
            Text("Review and save completed contacts. Export .adi, then sign and upload using TQSL for LoTW.").font(.callout)
            Form {
                HStack { TextField("Contact callsign",text:$record.call); TextField("Station callsign",text:$record.station) }
                HStack { TextField("Contact grid (optional)",text:$record.grid); TextField("Station grid (optional)",text:$record.myGrid) }
                HStack { TextField("Frequency MHz",text:$record.frequency); Text("Mode: PKT · Band: \(record.band ?? "—")") }
                DatePicker("Start (UTC)",selection:$record.start).environment(\.timeZone,TimeZone(secondsFromGMT:0)!)
                DatePicker("End (UTC)",selection:$record.end).environment(\.timeZone,TimeZone(secondsFromGMT:0)!)
                HStack { TextField("Report sent (optional)",text:$record.sent); TextField("Report received (optional)",text:$record.received) }
                TextField("Notes (printable ASCII, optional)",text:$record.note)
                Button("Save Contact") { do { try log.save(record); message = "Contact saved. Select it below to review or edit." } catch { message = error.localizedDescription } }.buttonStyle(.borderedProminent)
            }.formStyle(.grouped).frame(maxHeight:340)
            Text(log.error ?? message).font(.caption)
            ScrollView {
                LazyVStack(alignment:.leading) {
                    ForEach(log.contacts.reversed()) { c in
                        Button { record = c; message = "Editing saved contact" } label: { Text("\(Contact.utc(c.start,"yyyy-MM-dd HH:mm:ss")) UTC · \(c.call) · \(c.frequency) MHz · PKT").frame(maxWidth:.infinity,alignment:.leading) }
                    }
                }
            }
        }.onAppear { if record.station.isEmpty { newContact() } }
    }
    private func newContact() {
        record = Contact(); record.station = workspace.settings.callsign; record.myGrid = workspace.settings.locator
        let target = modem.rooms.selected == "radio" ? workspace.chatTarget : modem.rooms.selected
        if target != "QST" && !target.hasPrefix("#") { record.call = target }
        record.frequency = modem.contactFrequency
        message = "Confirm the actual contact times and frequency before saving."
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "QSO73-contacts.adi"
        if panel.runModal() == .OK, let url = panel.url {
            do { try Contact.export(log.contacts).write(to:url,atomically:true,encoding:.ascii); message = "ADIF exported. Open it in TQSL to sign and upload to LoTW." } catch { message = error.localizedDescription }
        }
    }
}
