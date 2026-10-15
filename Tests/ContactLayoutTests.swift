import SwiftUI
import AppKit
@main struct ContactLayoutTests {
 @MainActor static func main() {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let workspace = Workspace(contactDefaults:nil), modem = Modem(chatDefaults:nil)
  workspace.settings.callsign = "N4EAC"; workspace.settings.locator = "FM18FW"
  let sizes:[(String,CGFloat,CGFloat)] = [("compact",1040,760),("large",1300,900)]
  for (name,width,height) in sizes {
   for dark in [true,false] {
    let root = MainView(initialSection:.logbook).environmentObject(workspace).environmentObject(modem).environmentObject(modem.rooms).environmentObject(ActivityPresentation()).environmentObject(EngineUpdates())
     .padding(24).background(dark ? Color(red:0.035,green:0.035,blue:0.09) : Color(nsColor:.windowBackgroundColor))
     .environment(\.colorScheme,dark ? .dark : .light).tint(dark ? Color.cyan : Color.accentColor).frame(width:width,height:height)
    let host = NSHostingView(rootView:root)
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.contentView = host
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.orderFront(nil)
    RunLoop.main.run(until:Date().addingTimeInterval(1.0));host.layoutSubtreeIfNeeded()
    if let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) {
     host.cacheDisplay(in:host.bounds,to:bitmap)
     // The failed NavigationSplitView render contained only flat backgrounds.
     // Require actual text/control drawing, rather than checking fittingSize alone.
     var colors = Set<UInt32>()
     for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
      for x in stride(from: bitmap.pixelsWide / 3, to: bitmap.pixelsWide, by: 3) {
       if let color = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) {
        colors.insert(UInt32(color.redComponent*255)<<16 | UInt32(color.greenComponent*255)<<8 | UInt32(color.blueComponent*255))
       }
      }
     }
     precondition(colors.count > 64, "Contact navigation rendered blank: \(name), \(colors.count) colors")
     try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/qso73-contact-\(name)-\(dark ? "CP" : "Default").png"))
    }
    window.orderOut(nil)
    print("PASS: full navigation contact editor \(name) \(dark ? "CP" : "Default"): \(host.fittingSize)")
   }
  }
 }
}
