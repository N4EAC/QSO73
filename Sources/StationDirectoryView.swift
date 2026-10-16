import SwiftUI
import AppKit

struct StationDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var directory: CallsignList
    let theme: String
    var embedded = false
    let select: (String) -> Void
    @State private var selected: String?
    @State private var grid = ""
    @State private var favorite = false
    @State private var message = ""
    @State private var clear = false
    @State private var reset = false
    @State private var deleting = false
    private var colors: QSOTheme { QSOTheme(name: theme) }
    private var otherContacts: [StationContact] { directory.records.filter { !$0.favorite }.sorted { $0.call < $1.call } }
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                heading
                Text("Received callsigns are saved between sessions. Stars mark favorites.").font(.callout)
                actions
                contactList
                editor
                Text(directory.error ?? message).font(.caption).foregroundStyle(.secondary)
                Text("Map pins use grid centers. Unknown locations stay listed. These controls manage the callsign directory; completed ADIF contacts remain in Contact Log.").font(.caption)
            }.padding(20).frame(width: geometry.size.width, height: geometry.size.height)
            .background(colors.custom ? colors.background : Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(colors.custom ? .dark : nil)
            .tint(colors.custom ? colors.accent : .accentColor)
            .confirmationDialog("Erase non-favorite contacts? Favorites will be kept.", isPresented: $clear) {
                Button("Clear contacts", role: .destructive) { directory.clear(); selected = nil }
            }
            .confirmationDialog("Erase the entire contact directory, including every favorite?", isPresented: $reset) {
                Button("Full reset", role: .destructive) { directory.reset(); selected = nil }
            }
            .confirmationDialog("Delete \(selected ?? "this contact") from contacts and favorites?", isPresented: $deleting) {
                Button("Delete contact", role: .destructive) { if let selected { directory.remove(selected) }; selected = nil }
            }
        }
    }
    private var heading: some View {
        HStack {
            Text("Contacts & Favorites").font(.title.bold())
            Spacer()
            if !embedded { Button("Done") { dismiss() } }
        }
    }
    private var actions: some View {
        HStack {
            Button("Contact Map") {
                do { try ContactMap.open(directory.records, theme: theme) }
                catch { message = error.localizedDescription }
            }
            Spacer()
            Button("Clear contacts…") { clear = true }
            Button("Full reset…", role: .destructive) { reset = true }
        }
    }
    private var contactList: some View {
        List(selection: $selected) {
            SwiftUI.Section("Favorites") { ForEach(directory.favorites) { row($0) } }
            SwiftUI.Section("Contacts") { ForEach(otherContacts) { row($0) } }
        }.frame(minHeight: 150)
        .onChange(of: selected) { value in
            guard let call = value, let contact = directory.records.first(where: { $0.call == call }) else { grid = ""; favorite = false; return }
            grid = contact.grid; favorite = contact.favorite
        }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selected ?? "Select a contact").font(.headline).frame(width: 150, alignment: .leading)
                TextField("Grid (optional)", text: $grid).frame(width: 130)
                Toggle("Favorite", isOn: $favorite)
                Button("Save") {
                    guard let selected else { return }
                    do { try directory.update(selected, grid: grid, favorite: favorite) }
                    catch { message = error.localizedDescription }
                }.disabled(selected == nil)
            }
            HStack {
                Button("Use callsign") { if let selected { select(selected); if !embedded { dismiss() } } }.disabled(selected == nil)
                Button("Delete selected…", role: .destructive) { deleting = true }.disabled(selected == nil)
            }
        }
    }
    private func row(_ contact: StationContact) -> some View {
        HStack {
            Text((contact.favorite ? "★ " : "") + contact.call).font(.headline)
            Text(contact.grid.isEmpty ? "Grid unknown" : contact.grid).foregroundStyle(.secondary)
            Spacer()
            if let heard = contact.lastHeard { Text(Contact.utc(heard,"yyyy-MM-dd HH:mm") + " UTC").font(.caption) }
        }.tag(contact.call)
    }
}
