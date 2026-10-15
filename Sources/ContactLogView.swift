import SwiftUI
import AppKit
struct ContactLogView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var modem: Modem
    @ObservedObject var log: ContactLog
    @State private var record = Contact()
    @State private var message = ""
    var body: some View {
        // NavigationSplitView probes ideal sizes before supplying finite bounds.
        // Bound the expanding editor/list to the actual detail viewport.
        GeometryReader { geometry in
            VStack(alignment:.leading, spacing:12) {
                HStack { Text("Contact Log").font(.largeTitle.bold()); Spacer(); Button("New Contact",action:newContact); Button("Export ADIF…",action:export).disabled(log.contacts.isEmpty) }
                Text("Review and save completed contacts. Export .adi, then sign and upload using TQSL for LoTW.").font(.callout)
                // Use the editor's natural height rather than a scrolling grouped
                // Form capped at 340 points. Saved contacts get the remaining space.
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 20) {
                            field("Contact callsign", text: $record.call)
                            field("Station callsign", text: $record.station)
                        }
                        HStack(spacing: 20) {
                            field("Contact grid (optional)", text: $record.grid)
                            field("Station grid (optional)", text: $record.myGrid)
                        }
                        HStack(spacing: 20) {
                            field("Frequency MHz", text: $record.frequency)
                            Text("Mode: PKT · Band: \(record.band ?? "—")")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(spacing: 20) {
                            DatePicker("Start (UTC)", selection: $record.start)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            DatePicker("End (UTC)", selection: $record.end)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                        HStack(spacing: 20) {
                            field("Report sent (optional)", text: $record.sent)
                            field("Report received (optional)", text: $record.received)
                        }
                        field("Notes (printable ASCII, optional)", text: $record.note)
                        Button("Save Contact") {
                            do {
                                try log.save(record)
                                message = "Contact saved. Select it below to review or edit."
                            } catch { message = error.localizedDescription }
                        }.buttonStyle(.borderedProminent)
                    }.textFieldStyle(.roundedBorder).padding(12)
                }.fixedSize(horizontal: false, vertical: true)
                Text(log.error ?? message).font(.caption)
                if log.contacts.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    Text("Saved contacts").font(.headline)
                    ScrollView {
                        LazyVStack(alignment:.leading) {
                            ForEach(log.contacts.reversed()) { c in
                                Button { record = c; message = "Editing saved contact" } label: { Text("\(Contact.utc(c.start,"yyyy-MM-dd HH:mm:ss")) UTC · \(c.call) · \(c.frequency) MHz · PKT").frame(maxWidth:.infinity,alignment:.leading) }
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .onAppear { if record.station.isEmpty { newContact() } }
        }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text).labelsHidden()
        }.frame(maxWidth: .infinity, alignment: .leading)
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
