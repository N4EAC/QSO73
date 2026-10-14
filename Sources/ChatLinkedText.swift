import SwiftUI

struct ChatLinkedText: View {
    let text: String
    let color: Color
    @ObservedObject var safety: ChatLinkSafety
    private var linked: AttributedString {
        var value = AttributedString(text)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let url = match.url, let range = Range(match.range, in: text), let attributedRange = Range(range, in: value) else { continue }
                value[attributedRange].link = url
                value[attributedRange].foregroundColor = color
                value[attributedRange].underlineStyle = .single
            }
        }
        return value
    }
    var body: some View {
        Text(linked).textSelection(.enabled).foregroundStyle(color).tint(color)
            .environment(\.openURL, OpenURLAction { url in safety.open(url); return .handled })
    }
}
