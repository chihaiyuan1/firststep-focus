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
  let fixtureNow=TimeGrid.date(for:TimeGrid.dayKey(Date()))!.addingTimeInterval(10*3600)
  let focusStart=fixtureNow.timeIntervalSince1970-3600
  var reflectionState=FocusCore.FocusState()
  try reflectionState.apply(Command("addTask",title:"本轮原始主任务"),now:focusStart)
  let parentID=reflectionState.tasks[0].id
  try reflectionState.apply(Command("appendSubtasks",taskID:parentID,subtaskTitles:["本轮原始小任务"],expectedTaskVersion:reflectionState.tasks[0].editVersion),now:focusStart)
  try reflectionState.apply(Command("start",taskID:parentID,minutes:15,subtaskID:reflectionState.tasks[0].steps[0].id),now:focusStart)
  reflectionState.tick(now:focusStart+901)
  try reflectionState.apply(Command("editTask",taskID:parentID,title:"改名后的主任务"),now:focusStart+902)
  let reflectedRecord=reflectionState.history[0]
  let userThought="这一轮的已保存想法 🧭\n第二行保留 e\u{301}"
  let savedReflection=SessionReflection(recordID:reflectedRecord.id,text:userThought,draft:"不发送的编辑草稿",updatedAt:focusStart+86400,savedAt:focusStart+86400)
  let reflectionChat=ChatModel(directory:directory.appendingPathComponent("reflection-chat"),responder:{a,m,i,turns in try await responder.respond(account:a,model:m,instructions:i,messages:turns)})
  reflectionChat.draft="带想法的问题"
  reflectionChat.send(state:reflectionState,entries:[],accountID:"fixture",modelID:"fixture-model",now:fixtureNow,reflections:[savedReflection])
  while reflectionChat.busy {try await Task.sleep(nanoseconds:1_000_000)}
  let thoughtSnapshot=reflectionChat.messages.first?.context
  try check(thoughtSnapshot?.previewLines.joined(separator:"\n").contains(userThought)==true && thoughtSnapshot?.text.contains("不发送的编辑草稿")==false,"model failed to snapshot only exact saved thought")
  let reflectedSent=await responder.messages()
  let requestObject=try JSONSerialization.jsonObject(with:Data(thoughtSnapshot!.text.utf8)) as! [String:Any]
  let sentThoughts=requestObject["sessionReflections"] as! [[String:Any]]
  try check(sentThoughts.first?["text"] as? String==userThought && reflectedSent.first?.content.contains(thoughtSnapshot!.text)==true,"model request and stored source snapshot differ")
  let preparedReview=AIModel(directory:directory.appendingPathComponent("reflection-review"),chatResponder:{_,_,_,_ in "unused"})
  preparedReview.reviewDate=fixtureNow;preparedReview.answer="额外的补充"
  try check(preparedReview.prepareReview(state:reflectionState,entries:[],reflections:[savedReflection]),"saved thought review preparation unexpectedly rejected")
  let preparedObject=try JSONSerialization.jsonObject(with:Data(preparedReview.reviewSourceContext!.utf8)) as! [String:Any]
  let preparedThoughts=preparedObject["sessionReflections"] as! [[String:Any]]
  try check(preparedThoughts.first?["title"] as? String=="本轮原始主任务" && preparedThoughts.first?["subtaskTitle"] as? String=="本轮原始小任务" && preparedThoughts.first?["text"] as? String==userThought,"review model lost original attribution or saved text")
  try check(preparedReview.turns.count==1 && preparedReview.turns[0].content.hasSuffix("用户补充：额外的补充") && preparedReview.journal.isEmpty && !preparedReview.busy,"preparing review must remain local until manual ask")
  let preparedWeek=AIModel(directory:directory.appendingPathComponent("week-review"),chatResponder:{_,_,_,_ in "unused"})
  preparedWeek.reviewDate=fixtureNow;preparedWeek.answer="本周补充"
  try check(preparedWeek.prepareWeeklyReview(state:reflectionState,entries:[],reflections:[savedReflection]),"weekly review preparation failed")
  let weekObject = try JSONSerialization.jsonObject(with:Data(preparedWeek.reviewSourceContext!.utf8)) as! [String:Any]
  let weekThoughts = weekObject["sessionReflections"] as! [[String:Any]]
  try check(preparedWeek.kind == "weeklyReview" && preparedWeek.turns.count == 1 && weekThoughts.first?["text"] as? String == userThought && !preparedWeek.turns[0].content.contains("不发送的编辑草稿") && preparedWeek.turns[0].content.hasSuffix("用户补充：本周补充") && preparedWeek.journal.isEmpty && !preparedWeek.busy,"weekly preparation must remain local, preserve saved thought, and exclude drafts")
  var oversizedState=reflectionState
  try oversizedState.apply(Command("start",taskID:parentID,minutes:15,subtaskID:oversizedState.tasks[0].steps[0].id),now:focusStart+1000)
  oversizedState.tick(now:focusStart+1901)
  let longReflections=oversizedState.history.map {SessionReflection(recordID:$0.id,text:String(repeating:"想",count:8000),updatedAt:focusStart,savedAt:focusStart)}
  let failedChat=ChatModel(directory:directory.appendingPathComponent("oversized-chat"),responder:{a,m,i,turns in try await responder.respond(account:a,model:m,instructions:i,messages:turns)})
  let priorCalls=await responder.count()
  failedChat.draft="超限时保留我的问题"
  failedChat.send(state:oversizedState,entries:[],accountID:"fixture",modelID:"fixture-model",now:fixtureNow,reflections:longReflections)
  let laterCalls=await responder.count()
  try check(failedChat.error != nil && failedChat.draft=="超限时保留我的问题" && failedChat.pendingQuestion==nil && failedChat.messages.isEmpty && laterCalls==priorCalls,"oversized saved notes must stop chat before a request or local pair is created")
  preparedReview.answer="复盘超限时保留补充"
  try check(!preparedReview.prepareReview(state:oversizedState,entries:[],reflections:longReflections) && preparedReview.turns.isEmpty && preparedReview.reviewSourceContext==nil && preparedReview.error != nil && preparedReview.answer=="复盘超限时保留补充" && preparedReview.journal.isEmpty,"oversized reflection review must stop during preparation without stale context, truncation or journaling")
  let oversizedReview=AIModel(directory:directory.appendingPathComponent("oversized-review"),chatResponder:{_,_,_,_ in "unused"})
  oversizedReview.reviewDate=Date()
  oversizedReview.answer=String(repeating:"补",count:16001)
  oversizedReview.prepareReview(state:state,entries:[])
  try check(oversizedReview.error != nil && oversizedReview.turns.isEmpty && oversizedReview.answer.count==16001,"oversized review must fail during preparation and preserve unsent supplement")
  print("PASS: ChatModel saved reflection snapshot, original attribution, 16k request guard; review preparation, supplement retention; send/retry/cancel/history/restart/save failure")
 }
}
