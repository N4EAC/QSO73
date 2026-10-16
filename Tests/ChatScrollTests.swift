import SwiftUI
import AppKit
@MainActor final class Navigation: ObservableObject { @Published var showChat = true }
struct TestChatNavigation: View {
 @ObservedObject var navigation: Navigation
 let height: CGFloat = 760
 var body: some View {
  Group {
   if navigation.showChat { ChatView() } else { Text("Contact Log") }
  }.frame(width:1000,height:height)
 }
}
@main struct ChatScrollTests {
 @MainActor static func main() {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let navigation=Navigation(), workspace=Workspace(contactDefaults:nil,themeDefaults:nil), modem=Modem(chatDefaults:nil), activity=ActivityPresentation()
  workspace.settings.callsign="N4EAC"
  modem.entries=(0..<70).map { ChatEntry(direction:"TEST1 → QST",text:"Message \($0) — testing chat position after changing tabs.",source:"TEST1",destination:"QST") }
  let root=TestChatNavigation(navigation:navigation).environmentObject(workspace).environmentObject(modem).environmentObject(modem.rooms).environmentObject(activity).environmentObject(EngineUpdates())
  let host=NSHostingView(rootView:root)
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:760),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
  window.contentView=host;window.orderFront(nil)
  func pump(){RunLoop.main.run(until:Date().addingTimeInterval(0.5));host.layoutSubtreeIfNeeded()}
  func scrollViews(_ view:NSView)->[NSScrollView] { (view as? NSScrollView).map{[$0]} ?? view.subviews.flatMap{scrollViews($0)} }
  func check(_ name:String){
   pump()
   let views=scrollViews(host)
   guard let transcript=views.first, let document=transcript.documentView else { fatalError("Missing transcript") }
   let distance=document.frame.maxY-transcript.contentView.bounds.maxY
   precondition(distance <= 20, "Transcript did not reach latest message in \(name): \(distance)")
   print("PASS: latest message visible — \(name)")
   if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {host.cacheDisplay(in:host.bounds,to:bitmap);try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/qso73-chat-scroll-\(name).png"))}
  }
  check("initial")
  // Simulate reading old history before leaving; no new messages arrive.
  scrollViews(host).first!.contentView.scroll(to:.zero)
  pump()
  navigation.showChat=false;pump();navigation.showChat=true
  check("return")
  modem.entries.append(ChatEntry(direction:"TEST1 → QST",text:"New incoming message",source:"TEST1",destination:"QST"))
  check("incoming")
  modem.entries += (0..<40).map { ChatEntry(direction:"TEST2",text:"Direct message \($0)",conversation:"TEST2",source:"TEST2",destination:"N4EAC") }
  modem.rooms.selected="TEST2";check("direct")
  modem.rooms.selected="radio";check("radio")
  activity.dockedVisible=true;check("compact-activity")
  precondition(scrollViews(host).first!.contentView.bounds.height >= 170,"Docked activity collapsed the transcript")
  activity.dockedVisible=false;check("hidden-activity")
  modem.clearMessages(in:"radio");pump()
  precondition(modem.entries.allSatisfy{$0.conversation != "radio"})
  precondition(modem.entries.count == 40,"Clear affected another conversation")
  navigation.showChat=false;pump();navigation.showChat=true;pump()
  print("PASS: cleared conversation stays empty after returning")
  window.orderOut(nil)
 }
}
