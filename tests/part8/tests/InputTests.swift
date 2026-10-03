import Foundation
@main struct InputTests {
 @MainActor static func main() throws {
  let t=TestLog()
  func run(_ name:String,_ body:(InputHarness)throws->Void)throws{t.begin(name);let h=try InputHarness();try body(h);h.host.stop();t.end()}
  try run("INPUT01 discovery does not enable or install") {h in t.check(h.bridge.installed.isEmpty,"no installed test callback");h.tap("a");t.check(h.chosen.isEmpty,"nothing selected")}
  try run("INPUT02 explicit enable and fresh release") {h in t.check(h.enable(),"enabled");h.tap("a");t.check(h.chosen == ["a"],"current actual id once")}
  try run("INPUT03 held A before enable must become neutral") {h in _=h.enable();h.bridge.raw(h.id,"a",true);h.releaseA();t.check(h.chosen.isEmpty,"held key not accepted");h.tap("a");t.check(h.chosen == ["a"],"fresh press accepted")}
  try run("INPUT04 navigation uses stable item") {h in _=h.enable();h.tap("down");h.tap("a");t.check(h.chosen == ["b"],"selected b not a")}
  try run("INPUT05 previous at beginning is not failure") {h in _=h.enable();h.tap("up");t.check(h.active,"still enabled");t.check(h.sink.input.selection.selectedID == "a","no wrap")}
  try run("INPUT06 next at end is not failure") {h in _=h.enable();for _ in 0..<4{h.tap("down")};t.check(h.active,"not disabled at edge");t.check(h.sink.input.selection.selectedID == "c","last row")}
  try run("INPUT07 hold A then navigate does not activate new row") {h in _=h.enable();h.holdA();h.tap("down");h.releaseA();t.check(h.chosen.isEmpty,"no retarget");t.check(!h.active,"stale prepared intent rejected")}
  try run("INPUT08 mouse change invalidates pending A") {h in _=h.enable();h.holdA();_=h.sink.input.select("c");h.releaseA();t.check(h.chosen.isEmpty,"no mouse-key race")}
  try run("INPUT09 same-row click invalidates pending A") {h in _=h.enable();h.holdA();_=h.sink.input.select("a");h.releaseA();t.check(h.chosen.isEmpty,"same id still cancels")}
  try run("INPUT10 list reorder revokes context") {h in _=h.enable();h.holdA();try h.sink.input.replace([.init(id:"c",enabled:true),.init(id:"b",enabled:true),.init(id:"a",enabled:true)],selectedID:"a");h.host.environmentChanged();h.releaseA();t.check(h.chosen.isEmpty,"no stale activation");t.check(!h.active,"new revision requires enable")}
  try run("INPUT11 page lease change cancels") {h in _=h.enable();h.holdA();h.lease=UUID();h.host.environmentChanged();h.releaseA();t.check(h.chosen.isEmpty && !h.active,"no old page action")}
  try run("INPUT12 backend epoch change cancels") {h in _=h.enable();h.holdA();h.backend=UUID();h.host.environmentChanged();h.releaseA();t.check(h.chosen.isEmpty && !h.active,"old backend refused")}
  try run("INPUT13 lock revokes without auto reenabling") {h in _=h.enable();h.holdA();h.unlocked=false;h.host.environmentChanged();h.unlocked=true;h.host.environmentChanged();h.releaseA();t.check(h.chosen.isEmpty && !h.active,"unlock not resume")}
  try run("INPUT14 foreground loss revokes") {h in _=h.enable();h.holdA();h.frontBlocked=true;h.host.environmentChanged();h.frontBlocked=false;h.releaseA();t.check(h.chosen.isEmpty && !h.active,"no background action")}
  try run("INPUT15 sink unavailable or IME guard revokes") {h in _=h.enable();h.holdA();h.sink.input.ready=false;h.host.environmentChanged();h.releaseA();t.check(h.chosen.isEmpty && !h.active,"input unavailable")}
  try run("INPUT16 approvals cannot reuse list device") {h in _=h.enable();h.holdA();h.domain = .review;h.host.environmentChanged();h.releaseA();t.check(h.chosen.isEmpty && !h.active,"review never accepted");t.check(!h.enable(),"cannot enable review")}
  try run("INPUT17 detach invalidates pending target") {h in _=h.enable();h.holdA();h.bridge.detach(h.id);h.bridge.emit(.button(attachment:h.id,name:"a",outcome:.ended(1)));t.check(h.chosen.isEmpty,"late release discarded")}
  try run("INPUT18 identical label is not attachment identity") {h in _=h.enable();let other=UUID();h.bridge.attach(other);h.bridge.tap(other,"a");t.check(h.chosen.isEmpty,"same label no admission");t.check(!h.bridge.installed.contains(other),"no handler")}
  try run("INPUT19 enabling second device disables first") {h in _=h.enable();h.holdA();let other=UUID();h.bridge.attach(other);t.check(h.enable(other),"new local enable");h.releaseA();h.bridge.tap(other,"a");t.check(h.chosen == ["a"],"only new input");t.check(h.bridge.installed == [other],"one owner")}
  try run("INPUT20 replayed end cannot select twice") {h in _=h.enable();h.tap("a");h.bridge.emit(.button(attachment:h.id,name:"a",outcome:.ended(1)));t.check(h.chosen.count == 1,"single consume")}
  try run("INPUT21 repeated down does not duplicate") {h in _=h.enable();h.holdA();h.bridge.raw(h.id,"a",true);h.releaseA();t.check(h.chosen.count == 1,"debounced physical press")}
  try run("INPUT22 unknown controls cannot activate") {h in _=h.enable();h.tap("x");h.tap("leftShoulder");t.check(h.chosen.isEmpty && h.active,"unknown buttons no action")}
  try run("INPUT23 cancel opens no model") {h in _=h.enable();h.tap("b");t.check(h.cancelled == 1 && h.chosen.isEmpty,"one navigation cancel")}
  try run("INPUT24 mismatched release control fails closed") {h in _=h.enable();h.holdA();h.bridge.emit(.button(attachment:h.id,name:"b",outcome:.ended(1)));t.check(h.chosen.isEmpty && h.cancelled == 0 && !h.active,"do not reinterpret down")}
  try run("INPUT25 stop releases all resources") {h in _=h.enable();h.holdA();h.host.stop();h.bridge.emit(.button(attachment:h.id,name:"a",outcome:.ended(1)));t.check(h.bridge.installed.isEmpty && !h.bridge.started,"stopped");t.check(h.chosen.isEmpty,"no late action")}
  try run("INPUT26 reentrant model action may stop host") {h in _=h.enable();h.sink.input.onActivate={id in h.chosen.append(id);h.host.stop();return true};h.tap("a");t.check(h.chosen == ["a"] && !h.bridge.started,"safe stop inside sink")}
  try run("INPUT27 duplicate ids revoke selection") {h in _=h.enable();h.holdA();do{try h.sink.input.replace([.init(id:"a",enabled:true),.init(id:"a",enabled:true)],selectedID:"a");t.check(false,"must throw")}catch{t.check(true,"duplicate rejected")};h.host.environmentChanged();h.releaseA();t.check(h.chosen.isEmpty,"no retained activation")}
  try run("INPUT28 disabled rows skipped") {h in try h.sink.input.replace([.init(id:"a",enabled:true),.init(id:"b",enabled:false),.init(id:"c",enabled:true)],selectedID:"a");_=h.enable();h.tap("down");h.tap("a");t.check(h.chosen == ["c"],"disabled row not chosen")}
  try run("INPUT29 absent attachment cannot enable") {h in t.check(!h.enable(UUID()),"unknown denied");t.check(h.bridge.installed.isEmpty,"not installed")}
  try run("INPUT30 cancelled press cannot activate") {h in _=h.enable();h.holdA();h.bridge.emit(.cancel(attachment:h.id,presses:[1]));h.releaseA();t.check(h.chosen.isEmpty,"cancelled down discarded")}
  try run("INPUT31 armed indication tracks captured target") {h in var indicated:[String?]=[];h.sink.input.onArmed={indicated.append($0)};_=h.enable();h.holdA();t.check(indicated.last! == "a","armed actual target");h.tap("down");t.check(indicated.last! == nil,"navigation clears indication");h.releaseA();t.check(h.chosen.isEmpty,"cannot retarget")}
  try run("INPUT32 reentrant revoke while preparing is safe") {h in _=h.enable();h.sink.input.onArmed={id in if id != nil { h.host.stop() }};h.holdA();h.releaseA();t.check(h.chosen.isEmpty && !h.bridge.started,"prepare callback cannot resurrect host")}
  try run("INPUT33 chosen model invalidation during prepare fails closed") {h in _=h.enable();h.sink.input.onArmed={id in if id != nil { _=h.sink.input.select("b") }};h.holdA();h.releaseA();t.check(h.chosen.isEmpty,"target changed during reservation rejected")}
  try t.save(URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
