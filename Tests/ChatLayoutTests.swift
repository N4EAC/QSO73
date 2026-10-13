import SwiftUI
import AppKit

@main struct ChatLayoutTests {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let workspace = Workspace(), modem = Modem(chatDefaults: nil), presentation = ActivityPresentation(), updates = EngineUpdates()
        workspace.settings.callsign = "N4EAC"
        let root = MainView().environmentObject(workspace).environmentObject(modem).environmentObject(modem.rooms).environmentObject(presentation).environmentObject(updates)
            .frame(minWidth: 1040, minHeight: 760)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        func capture(_ name: String) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            host.layoutSubtreeIfNeeded()
            guard host.fittingSize.height <= 761 else { fatalError("Chat layout exceeded window height in \(name): \(host.fittingSize)") }
            print("PASS: bounded chat/sidebar layout: \(name)")

        }
        capture("offline")
        modem.status = "Preparing CAT and selected USB radio audio devices…"
        capture("connecting")
        modem.attached = true; modem.audioConnected = true; modem.rigConnected = true; modem.status = "modem73 ready"
        modem.audioRoute = "USB Audio Device (device 44100 Hz, modem 48000 Hz; CoreAudio route verified)"
        modem.rxAudioLevel = -38; modem.activeMode = "RDM-600S"; modem.frequency = "7.105000 MHz"; modem.radioMode = "PKTUSB"
        capture("connected")
        modem.decoding = true
        capture("decoding")
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/qso73-decoding-layout.png"))
        }
        modem.audioRoute = String(repeating: "Long named radio device / route description ", count: 8)
        capture("long-route")
    }
}
