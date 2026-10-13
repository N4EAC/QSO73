import Foundation
@main struct PingTests {
 static func main() throws {
  let id="01234567-89ab-4cde-8123-456789abcdef", now=Date(timeIntervalSince1970:1000)
  let request=try PingMessage(k:"request",id:id).encoded()
  var a=PingSession(),b=PingSession(),disabled=PingSession()
  _=try a.receive(request,source:"N4EAC",destination:"K1ABC",own:"N4EAC",outgoing:true,enabled:false,now:now)
  _=try disabled.receive(request,source:"N4EAC",destination:"K1ABC",own:"K1ABC",outgoing:false,enabled:false,now:now)
  assert(disabled.pending.isEmpty)
  _=try b.receive(request,source:"N4EAC",destination:"K1ABC",own:"K1ABC",outgoing:false,enabled:true,now:now)
  let duplicate=try b.receive(request,source:"N4EAC",destination:"K1ABC",own:"K1ABC",outgoing:false,enabled:true,now:now);assert(duplicate==nil)
  let missing=try b.reply(own:"K1ABC",grid:"FN31",now:now.addingTimeInterval(2),snr:{_ in nil});assert(missing==nil)
  let reply=try b.reply(own:"K1ABC",grid:"FN31",now:now.addingTimeInterval(3),snr:{p in p.id==id ? -14.3:nil})!
  assert(reply.0=="N4EAC");let decoded=try PingMessage.decode(reply.1);assert(decoded.snr == -14.3 && decoded.grid=="FN31")
  let display=try a.receive(reply.1,source:"K1ABC",destination:"N4EAC",own:"N4EAC",outgoing:false,enabled:true,now:now.addingTimeInterval(4));assert(display?.contains("-14.3") == true && a.pending.isEmpty)
  let repeated=try a.receive(reply.1,source:"K1ABC",destination:"N4EAC",own:"N4EAC",outgoing:false,enabled:true,now:now.addingTimeInterval(5));assert(repeated==nil)
  let next=try PingMessage(k:"request",id:UUID().uuidString).encoded()
  _=try b.receive(next,source:"N4EAC",destination:"QST",own:"K1ABC",outgoing:false,enabled:true,now:now.addingTimeInterval(6));assert(b.pending.isEmpty)
  _=try b.receive(next,source:"W1AW",destination:"QST",own:"K1ABC",outgoing:false,enabled:true,now:now.addingTimeInterval(6));b.clearPending();assert(b.pending.isEmpty)
  if CommandLine.arguments.count>2 {
   let input=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8).split(separator:"\n");assert(input.count==2)
   for line in input {let p=try PingMessage.decode(String(line));assert(p.id==id)}
   try (request+"\n"+reply.1+"\n").write(toFile:CommandLine.arguments[2],atomically:true,encoding:.utf8)
  }
  print("PASS: Swift PING opt-in, deduplication, measured reply, no reply loops, rate limit and cancellation")
 }
}
