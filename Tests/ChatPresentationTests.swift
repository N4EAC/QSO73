import Foundation
import AppKit
import SwiftUI
@main struct ChatPresentationTests {
    @MainActor static func main() {
        let own = ChatEntry(time: Date(timeIntervalSince1970: 0), direction: "You → QST", text: "Hello", source: "N4EAC", destination: "QST")
        guard ChatPresentation.heading(own) == "00:00:00 UTC · N4EAC → QST", ChatPresentation.tone(own) == .own else { fatalError("UTC/own classification") }
        var automatic = own; automatic.automatic = true
        guard ChatPresentation.tone(automatic) == .automatic else { fatalError("Automatic has priority over own") }
        let received = ChatEntry(direction: "K1ABC → QST", text: "Hello", source: "K1ABC")
        guard ChatPresentation.tone(received) == .received else { fatalError("Operator classification") }
        func luminance(_ rgb: [Double]) -> Double {
            let v=rgb.map { $0 <= 0.04045 ? $0/12.92 : pow(($0+0.055)/1.055,2.4) }
            return v[0]*0.2126+v[1]*0.7152+v[2]*0.0722
        }
        for dark in [false, true] {
            let background=luminance(dark ? [0.13,0.14,0.16] : [0.965,0.97,0.98])
            for tone: ChatTone in [.own,.automatic,.received] {
                let color=NSColor(ChatPresentation.color(tone,dark:dark)).usingColorSpace(.sRGB)!
                let foreground=luminance([color.redComponent,color.greenComponent,color.blueComponent])
                let contrast=(max(background,foreground)+0.05)/(min(background,foreground)+0.05)
                guard contrast>=4.5, color.alphaComponent==1 else { fatalError("Message contrast/opacity: \(contrast)") }
            }
        }
        print("PASS: UTC replaces You prefix; automatic/own/operator categories and opaque light/dark colors exceed 4.5:1 contrast")
    }
}
