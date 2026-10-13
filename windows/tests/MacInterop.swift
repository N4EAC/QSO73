import Foundation
@main struct MacInterop {
 @MainActor static func main() throws {
  let id="01234567-89ab-4cde-8123-456789abcdef"
  let rows=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8).split(separator:"\n")
  guard rows.count==6 else {fatalError("Missing Windows fixtures")}
  for row in rows {
   let chars=Array(row);var data=Data();for i in stride(from:0,to:chars.count,by:2){data.append(UInt8(String(chars[i...i+1]),radix:16)!)}
   let p=try RadioPacket.decode(data);let e=try RoomEnvelope.decode(p.text)
   guard p.source=="N4EAC-15",e.id==id else {fatalError("Wire mismatch")}
   let rooms=ChatRooms(defaults:nil);try rooms.join("#hfchat")
   let routed=try rooms.route(ChatEntry(direction:"RX",text:p.text,source:p.source,destination:p.destination),local:"K1ABC-7",outgoing:false)
   guard routed != nil else {fatalError("Mac rejected Windows event")}
  }
  var lines:[String]=[]
  for k in ["msg","join","leave","topic","announce"] {
   let e=RoomEnvelope(kind:k,room:"#hfchat",text:["join","leave"].contains(k) ? "":"Hello from Mac 👋",id:id)
   lines.append(try RadioPacket(source:"K1ABC-7",destination:"QST",text:e.encoded()).encode().map{String(format:"%02x",$0)}.joined())
  }
  let e=RoomEnvelope(kind:"msg",room:"N4EAC",text:"Private from Mac",id:id)
  lines.append(try RadioPacket(source:"K1ABC-7",destination:"N4EAC",text:e.encoded()).encode().map{String(format:"%02x",$0)}.joined())
  try (lines.joined(separator:"\n")+"\n").write(toFile:CommandLine.arguments[2],atomically:true,encoding:.utf8)
  print("PASS: Swift/Mac decodes and routes six Windows channel/direct event fixtures")
 }
}
