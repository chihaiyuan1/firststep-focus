import Foundation
import FocusCore
import FocusAI

private struct Failure:Error {let message:String}
private func check(_ value: @autoclosure () -> Bool,_ message:String) throws {if !value() {throw Failure(message:message)}}
private actor Responder {
 var calls=0
 var received:[AIMessage]=[]
 var shouldFail=false
 var slow=false
 func set(fail:Bool=false,slow:Bool=false) {shouldFail=fail;self.slow=slow}
 func respond(account:String,model:String,instructions:String,messages:[AIMessage]) async throws -> String {
  calls+=1;received=messages
  let fail=shouldFail,delay=slow
  if delay {_ = await Task.detached {try? await Task.sleep(nanoseconds:120_000_000)}.value}
  if fail {throw Failure(message:"fixture failure")}
  return "这是完整的测试回答。"
 }
 func count()->Int {calls}
 func messages()->[AIMessage] {received}
}
@main struct ChatModelChecks {
 @MainActor static func main() async throws {
  let directory=FileManager.default.temporaryDirectory.appendingPathComponent("ChatModel-"+UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:directory)}
  let responder=Responder()
  let model=ChatModel(directory:directory,responder:{a,m,i,turns in try await responder.respond(account:a,model:m,instructions:i,messages:turns)})
  var state=FocusCore.FocusState();try state.apply(Command("addTask",title:"虚构今日行动"),now:Date().timeIntervalSince1970)
  model.draft="  我今天先做什么？  "
  model.send(state:state,entries:[],accountID:"fixture",modelID:"fixture-model")
  while model.busy {try await Task.sleep(nanoseconds:1_000_000)}
  try check(model.messages.count==2 && model.messages[0].content=="我今天先做什么？","completed exchange missing")
  try check(model.messages[0].context?.taskCount==1 && model.messages[1].context==nil,"context not tied to user turn")
  try check(model.conversations.count==1 && model.draft.isEmpty,"exchange not persisted")
  let oldID=model.selectedID!
  let sent=await responder.messages();try check(sent.count==2 && sent[0].content.contains("虚构今日行动"),"today context absent")
  model.draft="继续问一个问题"
  await responder.set(fail:true)
  model.send(state:state,entries:[],accountID:"fixture",modelID:"fixture-model")
  while model.busy {try await Task.sleep(nanoseconds:1_000_000)}
  try check(model.messages.count==2 && model.draft=="继续问一个问题" && model.error != nil,"failure must retain draft without duplicate turn")
  await responder.set()
  model.send(state:state,entries:[],accountID:"fixture",modelID:"fixture-model")
  while model.busy {try await Task.sleep(nanoseconds:1_000_000)}
  try check(model.messages.count==4 && model.conversations.first?.revision==2,"retry duplicated or lost turn")
  await responder.set(slow:true)
  model.draft="会被取消的问题";model.send(state:state,entries:[],accountID:"fixture",modelID:"fixture-model")
  model.cancel()
  try check(model.draft=="会被取消的问题" && !model.busy,"cancel discarded draft")
  model.newConversation()
  try await Task.sleep(nanoseconds:150_000_000)
  try check(model.messages.isEmpty && model.selectedID==nil && model.conversations.count==1,"late response polluted new conversation")
  model.open(oldID)
  try check(model.messages.count==4,"saved conversation failed to reopen")
  model.newConversation();try check(model.messages.isEmpty && model.draft.isEmpty,"new conversation did not clear context")
  let fresh=ChatModel(directory:directory,responder:{_,_,_,_ in "unused"})
  fresh.open(oldID);try check(fresh.messages.count==4,"restart lost local conversation")
  let file=directory.appendingPathComponent("ai-chats.json")
  let healthy=try Data(contentsOf:file)
  try Data("broken".utf8).write(to:file)
  await responder.set()
  fresh.draft="保存失败也要能看见完整回答";fresh.send(state:state,entries:[],accountID:"fixture",modelID:"fixture-model")
  while fresh.busy {try await Task.sleep(nanoseconds:1_000_000)}
  try check(fresh.messages.count==6 && fresh.needsSave && fresh.error != nil,"save failure hid completed answer")
  let broken=try String(contentsOf:file,encoding:.utf8)
  try check(broken=="broken","corrupted file overwritten")
  try healthy.write(to:file)
  fresh.retrySave()
  try check(!fresh.needsSave && fresh.conversations.first?.revision==3 && fresh.messages.count==6,"save retry failed after storage recovery")
  fresh.retrySave()
  try check(fresh.conversations.first?.messages.count==6,"save retry duplicated a pair")
  let routingDir=directory.appendingPathComponent("routing")
  let assistant=AIModel(directory:routingDir,chatResponder:{a,m,i,turns in try await responder.respond(account:a,model:m,instructions:i,messages:turns)})
  await responder.set(slow:true)
  for route in ["tab","account","model"] {
   assistant.chat.newConversation();assistant.chat.draft="切换前的问题"
   assistant.chat.send(state:state,entries:[],accountID:"fixture",modelID:"fixture-model")
   if route=="tab" {assistant.reset()} else if route=="account" {assistant.switchAccount()} else {assistant.modelSelectionChanged()}
   try await Task.sleep(nanoseconds:150_000_000)
   try check(assistant.chat.messages.isEmpty && !assistant.chat.busy && assistant.chat.draft=="切换前的问题","AIModel route allowed stale reply: \(route)")
  }
  print("PASS: ChatModel send/context, retry, cancellation, stale reply, new/history/restart, save failure")
 }
}
