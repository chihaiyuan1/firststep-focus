import Foundation

@main struct SubtaskChecks {
 static func main() throws {
  func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
  func rejected(_ block: () throws -> Void) { do { try block(); fatalError("expected rejection") } catch {} }
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:dir) }
  let store=StateStore(directory:dir), now=1_792_600_000.0
  var state=try store.transact(command:Command("addTask",title:"读书笔记"),now:now)
  let id=state.tasks[0].id, version=state.tasks[0].editVersion
  state=try store.transact(command:Command("appendSubtasks",taskID:id,subtaskTitles:["摘录三段文字","写下一个感想"],expectedTaskVersion:version),now:now)
  check(state.schema==4 && state.tasks[0].steps.count==2,"subtasks persist with migration")
  let step=state.tasks[0].steps[0]
  rejected { _=try store.transact(command:Command("appendSubtasks",taskID:id,subtaskTitles:["过期建议"],expectedTaskVersion:version),now:now) }
  rejected { _=try store.transact(command:Command("start",taskID:id,minutes:15),now:now) }
  rejected { _=try store.transact(command:Command("start",taskID:id,minutes:15,subtaskID:"unknown"),now:now) }
  state=try store.transact(command:Command("start",taskID:id,minutes:15,subtaskID:step.id),now:now)
  check(state.session?.subtaskTitle=="摘录三段文字" && state.session?.title=="读书笔记","session snapshots both titles")
  rejected { _=try store.transact(command:Command("editSubtask",taskID:id,title:"偷偷修改",subtaskID:step.id),now:now+1) }
  state=try store.transact(now:now+901)
  check(state.history.count==1 && state.history[0].finished && state.history[0].taskID==id && state.history[0].subtaskID==step.id,"history preserves parent attribution")
  check(!state.tasks[0].steps[0].completed && !state.tasks[0].completed,"timer does not complete task")
  state=try store.transact(command:Command("completeSubtask",taskID:id,subtaskID:step.id),now:now+902)
  check(state.tasks[0].steps[0].completedAt==now+902,"manual completion timestamp")
  rejected { _=try store.transact(command:Command("start",taskID:id,minutes:15,subtaskID:step.id),now:now+903) }
  state=try store.transact(command:Command("editTask",taskID:id,title:"新的主任务标题"),now:now+904)
  check(state.history[0].title=="读书笔记" && state.history[0].subtaskTitle=="摘录三段文字","historical title immutable")
  state=try store.transact(command:Command("deleteSubtask",taskID:id,subtaskID:step.id),now:now+905)
  check(state.history[0].subtaskID==step.id && state.tasks[0].steps.count==1,"delete preserves history")
  rejected { _=try store.transact(command:Command("appendSubtasks",taskID:id,subtaskTitles:["  "]),now:now+906) }
  rejected { _=try store.transact(command:Command("appendSubtasks",taskID:id,subtaskTitles:Array(repeating:"x",count:31)),now:now+906) }
  state=try store.transact(command:Command("completeTask",taskID:id),now:now+907)
  check(state.tasks[0].completedAt==now+907,"main task completion timestamp")
  let old=Data("""
  {"schema":3,"tasks":[{"id":"old","title":"旧任务","nextStep":"下一步","day":"2026-10-20","completed":true}],"history":[]}
  """.utf8)
  let oldDir=dir.appendingPathComponent("old");try FileManager.default.createDirectory(at:oldDir,withIntermediateDirectories:true)
  try old.write(to:oldDir.appendingPathComponent("state.json"))
  let migrated=try StateStore(directory:oldDir).transact(now:now)
  check(migrated.schema==4 && migrated.tasks[0].steps.isEmpty && migrated.tasks[0].completedAt==nil,"no invented old completion date")
  print("PASS: subtasks migration, explicit selection, snapshot attribution, completion, stale adoption and active edit guards")
 }
}
