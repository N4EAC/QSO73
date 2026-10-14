import Foundation
@main struct ContactLogTests {
 @MainActor static func main() throws {
  var c=Contact();c.call="k1abc/p";c.station="n4eac-7";c.grid="FN42";c.myGrid="EL87";c.frequency="7.105";c.note="A<B> & test"
  c.start=ISO8601DateFormatter().date(from:"2026-10-14T23:59:50Z")!;c.end=c.start.addingTimeInterval(15)
  try c.validate();let data=try Contact.export([c]);try data.write(toFile:"/tmp/qso73-contact-mac.adi",atomically:true,encoding:.ascii)
  guard data.contains("<CALL:7>K1ABC/P"), data.contains("<STATION_CALLSIGN:5>N4EAC"), data.contains("<QSO_DATE_OFF:8>20261015"),data.contains("<BAND:3>40m"),data.contains("<MODE:3>PKT") else {fatalError("ADIF fields")}
  for frequency in ["nan","7.1MHz","0","27.5"] {var bad=c;bad.frequency=frequency;guard (try? bad.adif())==nil else {fatalError("Invalid frequency accepted")}}
  var bad=c;bad.end=c.start.addingTimeInterval(-1);guard (try? bad.adif())==nil else{fatalError("Time order")}
  bad=c;bad.grid="ZZ99";guard (try? bad.adif())==nil else{fatalError("Grid")}
  let name="qso73-contact-test-"+UUID().uuidString;let defaults=UserDefaults(suiteName:name)!;defer{defaults.removePersistentDomain(forName:name)}
  let log=ContactLog(defaults:defaults);try log.save(c);c.note="Edited";try log.save(c);guard log.contacts.count==1,ContactLog(defaults:defaults).contacts.first?.note=="Edited" else{fatalError("Persistence/edit")}
  defaults.set(Data("bad".utf8),forKey:"qso73.contacts.v1");let corrupt=ContactLog(defaults:defaults);guard (try? corrupt.save(c))==nil,defaults.data(forKey:"qso73.contacts.v1")==Data("bad".utf8) else{fatalError("Corrupt file preservation")}
  var old=Modem73Settings();let bytes=try JSONEncoder().encode(old);old.rxGain=20;old.txGain=6;var station=StationSettings();station.callsign="N4EAC";let args=try old.arguments(station:station);guard args.contains("--rx-gain-db"),args.contains("20.0"),try JSONDecoder().decode(Modem73Settings.self,from:bytes).rxGain==0 else{fatalError("Gain settings/migration")}
  print("PASS: ADIF UTC rollover/fields/validation, contact persistence/edit, corruption preservation and gain migration")
 }
}
