import SwiftUI
struct QSOTheme {
    let name: String
    var custom: Bool { name != "Default" }
    var background: Color { name == "Crimson" ? Color(red:0.09,green:0.02,blue:0.035) : Color(red:0.035,green:0.035,blue:0.09) }
    var panel: Color { name == "Crimson" ? Color(red:0.17,green:0.04,blue:0.065) : Color(red:0.07,green:0.055,blue:0.16) }
    var accent: Color { name == "Crimson" ? Color(red:1,green:0.4,blue:0.48) : .cyan }
    var outline: Color { name == "Crimson" ? Color(red:0.9,green:0.13,blue:0.27) : .pink }
}
