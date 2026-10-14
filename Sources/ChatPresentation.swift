import Foundation
import SwiftUI

enum ChatTone: Equatable { case own, automatic, received }
enum ChatPresentation {
    static func tone(_ entry: ChatEntry) -> ChatTone {
        if entry.automatic || (entry.text.hasPrefix("BEACON ") && entry.text.contains(" QSO73 v")) { return .automatic }
        return entry.direction.hasPrefix("You") ? .own : .received
    }
    static func timestamp(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "HH:mm:ss 'UTC'"; return f.string(from: date)
    }
    static func heading(_ entry: ChatEntry) -> String {
        let station = entry.source ?? (entry.direction.hasPrefix("You") ? "Local station" : entry.direction)
        return timestamp(entry.time) + " · " + station + (entry.destination.map { " → " + $0 } ?? "")
    }
    static func color(_ tone: ChatTone, dark: Bool) -> Color {
        switch (tone, dark) {
        case (.own, false): return Color(red: 7/255, green: 85/255, blue: 176/255)
        case (.automatic, false): return Color(red: 143/255, green: 57/255, blue: 0)
        case (.received, false): return Color(red: 0, green: 103/255, blue: 53/255)
        case (.own, true): return Color(red: 103/255, green: 182/255, blue: 1)
        case (.automatic, true): return Color(red: 1, green: 192/255, blue: 100/255)
        case (.received, true): return Color(red: 119/255, green: 230/255, blue: 163/255)
        }
    }
}
