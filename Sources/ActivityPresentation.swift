import SwiftUI
import AppKit

@MainActor final class ActivityPresentation: NSObject, ObservableObject, NSWindowDelegate {
    @Published var dockedVisible = false
    @Published private(set) var isDetached = false
    @Published var keepOnTop = false {
        didSet { controller?.window?.level = keepOnTop ? .floating : .normal }
    }
    private var controller: NSWindowController?

    func undock(_ modem: Modem) {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "QSO73 — Modem Activity"
        window.identifier = NSUserInterfaceItemIdentifier("qso73.modemActivity")

        window.minSize = NSSize(width: 850, height: 540)
        window.isReleasedWhenClosed = false
        window.level = keepOnTop ? .floating : .normal
        window.delegate = self
        window.contentView = NSHostingView(rootView: ActivityPanel(modem: modem, presentation: self, detached: true))
        controller = NSWindowController(window: window)
        dockedVisible = false
        isDetached = true
        if !window.setFrameUsingName("QSO73ModemActivity") { window.center() }
        window.setFrameAutosaveName("QSO73ModemActivity")
        controller?.showWindow(nil)
    }
    func dock() {
        if let window = controller?.window { window.close() }
        else { isDetached = false; dockedVisible = true }
    }
    func windowWillClose(_ notification: Notification) {
        isDetached = false
        dockedVisible = true
        controller = nil
    }
}

struct ActivityPanel: View {
    @ObservedObject var modem: Modem
    @ObservedObject var presentation: ActivityPresentation
    let detached: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Modem Activity", systemImage: "waveform.path").font(.headline)
                Text(modem.activeMode + " · " + modem.channel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if detached {
                    Toggle("Keep on Top", isOn: $presentation.keepOnTop).toggleStyle(.checkbox)
                    Button("Dock") { presentation.dock() }
                        .help("Return activity to the panel below Radio Chat.")
                } else {
                    Button("Undock") { presentation.undock(modem) }
                        .help("Move activity to a separate window sharing this modem session.")
                    Button("Hide") { presentation.dockedVisible = false }
                }
            }
            ScrollView {
                ModemActivityView(modem: modem).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(detached ? 12 : 8)
    }
}

// A fixed two-line summary belongs inside Chat, keeping the transcript flexible.
struct CompactModemActivity: View {
    @ObservedObject var modem: Modem
    @ObservedObject var presentation: ActivityPresentation
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            HStack(spacing:12) {
                Label("Activity",systemImage:"waveform.path").font(.caption.bold())
                Text(modem.activeMode + " · " + modem.channel.uppercased())
                Text("SNR " + modem.snr)
                Spacer()
                Button("Full / Undock") { presentation.undock(modem) }
                Button("Hide") { presentation.dockedVisible = false }
            }
            HStack(spacing:16) {
                Text("RX " + (modem.rxAudioLevel.map { String(format:"%.0f dBFS",$0) } ?? "—"))
                Text("BER " + (modem.lastBER.map { String(format:"%.2f%%",$0) } ?? "—"))
                Text("CSMA " + modem.csmaDescription)
                Text("Queue \(modem.txQueue)")
                Spacer()
                Text("RX \(modem.rxCount) · TX \(modem.txCount)")
            }.foregroundStyle(.secondary)
        }.font(.caption).lineLimit(1).padding(8)
        .background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
        .fixedSize(horizontal:false,vertical:true)
    }
}
