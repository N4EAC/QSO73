import Foundation
import Combine

@MainActor final class CallsignList: ObservableObject {
    @Published private(set) var callsigns: [String] = []
    var destinations: [String] { ["QST"] + callsigns.sorted() }
    func remember(_ value: String, excluding own: String = "") {
        let call = PacketAddress.canonical(value.trimmingCharacters(in: .whitespacesAndNewlines))
        guard StationSettings.validCallsign(call), call != PacketAddress.canonical(own) else { return }
        callsigns.removeAll { $0 == call }
        callsigns.append(call)
        if callsigns.count > 200 { callsigns.removeFirst(callsigns.count - 200) }
    }
    func clear() { callsigns = [] }
}
