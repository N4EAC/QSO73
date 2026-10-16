import Foundation
@main struct StationDirectoryTests {
 @MainActor static func main() throws {
  let name="qso73-directory-tests-"+UUID().uuidString
  let defaults=UserDefaults(suiteName:name)!
  defer { defaults.removePersistentDomain(forName:name) }
  let directory=CallsignList(defaults:defaults),date=Date(timeIntervalSince1970:1792100000)
  directory.remember("test1",excluding:"N0CALL",text:"BEACON TEST1 FN42 QSO73 v1.1.0",received:true,at:date)
  directory.remember("TEST2",text:"BEACON TEST2 JN58AB QSO73 v1.1.0",received:true,at:date)
  directory.remember("QST");directory.remember("N0CALL",excluding:"N0CALL")
  precondition(directory.records.count==2)
  try directory.update("TEST1",grid:"FN42",favorite:true)
  let loaded=CallsignList(defaults:defaults)
  precondition(loaded.records==directory.records && loaded.favorites.count==1 && loaded.records.first?.lastHeard==date)
  precondition(loaded.destinations==["QST","TEST1","TEST2"])
  loaded.clear();precondition(loaded.callsigns==["TEST1"])
  precondition(CallsignList(defaults:defaults).callsigns==["TEST1"])
  loaded.remove("TEST1");precondition(CallsignList(defaults:defaults).records.isEmpty)
  loaded.remember("TEST3",text:"~Q73P:{\"k\":\"reply\",\"call\":\"TEST3\",\"grid\":\"AA00AA00\"}",received:true)
  precondition(loaded.records.first?.grid=="AA00AA00")
  loaded.remember("TEST3",text:"BEACON TEST9 ZZ99 QSO73 v1.1.0")
  precondition(loaded.records.first?.grid=="AA00AA00")
  loaded.reset();precondition(CallsignList(defaults:defaults).records.isEmpty)
  defaults.set(Data("bad".utf8),forKey:"qso73.stationDirectory.v1")
  let bad=CallsignList(defaults:defaults);bad.remember("TEST4")
  precondition(bad.error != nil && defaults.data(forKey:"qso73.stationDirectory.v1")==Data("bad".utf8))
  bad.reset();precondition(CallsignList(defaults:defaults).error==nil)
  print("PASS: persisted callsigns/grids/favorites, favorite-preserving clear, individual delete, full reset and corrupt-file preservation")
 }
}
