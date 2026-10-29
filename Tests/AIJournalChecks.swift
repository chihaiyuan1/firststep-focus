import Foundation

private var failures: [String] = []
private var checks = 0
private func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    checks += 1
    do { if try !condition() { failures.append(name) } }
    catch { failures.append("\(name): \(error)") }
}
private func rejects(_ name: String, _ operation: () throws -> Void) {
    checks += 1
    do { try operation(); failures.append(name) } catch {}
}
private func json(_ value: Any) throws -> String {
    String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!
}
private func replyJSON(kind: String = "taskPlan", message: String = "先完成一个可检查的小成果。", questions: [String] = [], steps: [String] = ["列出三条要点"]) throws -> String {
    try json(["kind": kind, "message": message, "questions": questions, "steps": steps])
}

@main struct AIJournalChecks {
    static func main() throws {
        let plan = try replyJSON(steps: ["  列出三条要点  ", "写出第一段"])
        check(try AssistantReply.parse(plan).steps == ["列出三条要点", "写出第一段"], "plan trims editable step titles")
        check(try AssistantReply.parse("  ```json\n\(plan)\n```  ").kind == "taskPlan", "accepts exactly one JSON fence")
        check(try AssistantReply.parse("```json\r\n\(plan)\r\n```").kind == "taskPlan", "accepts fenced CRLF JSON")
        check(try AssistantReply.parse(replyJSON(kind: "questions", questions: ["怎样算完成？"], steps: [])).questions.count == 1, "one clarification question")
        check(try AssistantReply.parse(replyJSON(kind: "questions", questions: ["怎样算完成？", "有已确定的期限吗？"], steps: [])).questions.count == 2, "two clarification questions")
        check(try AssistantReply.parse(replyJSON(kind: "review", steps: [])).kind == "review", "review can have no generated steps")
        check(try AssistantReply.parse(replyJSON(kind: "review", steps: ["明天先核对三条来源"])).steps.count == 1, "review can retain a suggested first step")
        rejects("rejects prose surrounding JSON") { _ = try AssistantReply.parse("这是我的建议：\n" + plan) }
        rejects("rejects prose surrounding fence") { _ = try AssistantReply.parse("这是我的建议：\n```json\n\(plan)\n```") }
        rejects("rejects two JSON fences") { _ = try AssistantReply.parse("```json\n\(plan)\n```\n```json\n\(plan)\n```") }
        rejects("rejects unlabeled fence") { _ = try AssistantReply.parse("```\n\(plan)\n```") }
        rejects("rejects truncated JSON") { _ = try AssistantReply.parse(String(plan.dropLast())) }
        rejects("rejects missing keys") { _ = try AssistantReply.parse("{\"kind\":\"review\",\"message\":\"复盘\"}") }
        rejects("rejects unknown tool payload") { _ = try AssistantReply.parse("{\"kind\":\"review\",\"message\":\"复盘\",\"questions\":[],\"steps\":[],\"tool_call\":\"write\"}") }
        rejects("rejects unsupported kind") { _ = try AssistantReply.parse(replyJSON(kind: "execute")) }
        rejects("rejects empty message") { _ = try AssistantReply.parse(replyJSON(message: " \n ")) }
        rejects("rejects oversized message") { _ = try AssistantReply.parse(replyJSON(message: String(repeating: "中", count: 8001))) }
        rejects("rejects questions without a question") { _ = try AssistantReply.parse(replyJSON(kind: "questions", steps: [])) }
        rejects("rejects three clarification questions") { _ = try AssistantReply.parse(replyJSON(kind: "questions", questions: ["一", "二", "三"], steps: [])) }
        rejects("rejects long clarification question") { _ = try AssistantReply.parse(replyJSON(kind: "questions", questions: [String(repeating: "中", count: 301)], steps: [])) }
        rejects("rejects blank clarification question") { _ = try AssistantReply.parse(replyJSON(kind: "questions", questions: [" "], steps: [])) }
        rejects("rejects mixed questions and plan") { _ = try AssistantReply.parse(replyJSON(kind: "questions", questions: ["怎样算完成？"])) }
        rejects("rejects task plan with question") { _ = try AssistantReply.parse(replyJSON(questions: ["再想想？"])) }
        rejects("rejects review with questions") { _ = try AssistantReply.parse(replyJSON(kind: "review", questions: ["再想想？"], steps: [])) }
        rejects("rejects empty task plan") { _ = try AssistantReply.parse(replyJSON(steps: [])) }
        rejects("rejects nine steps") { _ = try AssistantReply.parse(replyJSON(steps: (1...9).map { "步骤\($0)" })) }
        rejects("rejects empty step") { _ = try AssistantReply.parse(replyJSON(steps: ["  "])) }
        rejects("rejects oversized step") { _ = try AssistantReply.parse(replyJSON(steps: [String(repeating: "中", count: 121)])) }
        rejects("rejects duplicate normalized steps") { _ = try AssistantReply.parse(replyJSON(steps: ["列出要点", " 列出要点 "])) }
        rejects("rejects multiline step title") { _ = try AssistantReply.parse(replyJSON(steps: ["先做第一项\n再做第二项"])) }
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store=AIJournalStore(directory:dir)
        let entry=AIJournalEntry(day:"2026-10-22",kind:"review",taskID:nil,title:"当天复盘",turns:[AITurn(role:"user",content:"今天完成了读书笔记")],reply:try AssistantReply.parse(replyJSON(kind:"review",steps:[])))
        check(try store.append(entry).count==1,"journal persists entry")
        check(try store.append(entry).count==1,"journal idempotence")
        var changed=entry; changed.title="变化"
        rejects("same id conflict") { _=try store.append(changed) }
        let raw=Data("broken".utf8);try raw.write(to:dir.appendingPathComponent("ai-journal.json"))
        rejects("corruption never overwritten") { _=try store.append(entry) }
        check(try Data(contentsOf:dir.appendingPathComponent("ai-journal.json"))==raw,"bad journal retained")
        var state=FocusState(); state.tasks=[FocusTask(title:"当天任务",nextStep:"",day:"2026-10-22",completed:true)]
        let start=TimeGrid.date(for:"2026-10-22")!.timeIntervalSince1970+23*3600+45*60
        state.history=[FocusRecord(id:"a",taskID:state.tasks[0].id,title:"当天任务",startAt:start,endAt:start+1800,focusSeconds:1500,finished:true,accessCount:1)]
        let time=try TimeEntry(day:"2026-10-22",startMinute:540,endMinute:600,title:"整理资料")
        let context=AssistantPrompts.reviewContext(state:state,entries:[time],day:"2026-10-22")
        let obj=try JSONSerialization.jsonObject(with:Data(context.utf8)) as! [String:Any]
        check(obj["focusSeconds"] as? Int == 1500 && obj["completedPomodoros"] as? Int == 1,"uses net focus once with start-day attribution")
        let next=try JSONSerialization.jsonObject(with:Data(AssistantPrompts.reviewContext(state:state,entries:[time],day:"2026-10-23").utf8)) as! [String:Any]
        check(next["focusSeconds"] as? Int == 0,"cross-midnight not double counted")
        check(context.contains("完成日期未知"),"unknown completion is not inferred from task day")
        state.history[0].subtaskID="original-step";state.history[0].subtaskTitle="当时小任务"
        state.tasks[0].title="后来改名的主任务"
        let savedThought="第一行：先核对 🧭\n第二行：e\u{301} 仍待确认"
        let reflections=[
            SessionReflection(recordID:"a",text:savedThought,draft:"不发送修改草稿",updatedAt:start+86400,savedAt:start+86400),
            SessionReflection(recordID:"orphan",text:"不发送孤立想法",updatedAt:start,savedAt:start)
        ]
        let withThought=AssistantPrompts.reviewContext(state:state,entries:[time],day:"2026-10-22",reflections:reflections)
        let thoughtObject=try JSONSerialization.jsonObject(with:Data(withThought.utf8)) as! [String:Any]
        let thoughtRows=thoughtObject["sessionReflections"] as! [[String:Any]]
        check(thoughtRows.count==1 && thoughtRows[0]["recordID"] as? String=="a" && thoughtRows[0]["taskID"] as? String==state.history[0].taskID,"review includes only saved thoughts linked to selected-day records")
        check(thoughtRows[0]["title"] as? String=="当天任务" && thoughtRows[0]["subtaskTitle"] as? String=="当时小任务" && thoughtRows[0]["text"] as? String==savedThought,"review preserves original parent/subtask attribution and exact saved text after later edits")
        check(!withThought.contains("不发送") && !withThought.contains("focus-reflections.json") && !withThought.contains("draft"),"review omits drafts, orphan notes and storage metadata")
        let nextThought=AssistantPrompts.reviewContext(state:state,entries:[],day:"2026-10-23",reflections:reflections)
        check(!nextThought.contains("第一行") && !nextThought.contains("仍待确认"),"next-day edits do not move a thought away from session start day")
        let unsaved=[SessionReflection(recordID:"a",text:"不发送未保存文字",draft:"不发送草稿",updatedAt:start,savedAt:nil)]
        let blankSaved=[SessionReflection(recordID:"a",text:" \n\t",updatedAt:start,savedAt:start)]
        check(!AssistantPrompts.reviewContext(state:state,entries:[],day:"2026-10-22",reflections:unsaved).contains("不发送"),"unsaved text is excluded even when nonempty")
        let blankObject=try JSONSerialization.jsonObject(with:Data(AssistantPrompts.reviewContext(state:state,entries:[],day:"2026-10-22",reflections:blankSaved).utf8)) as! [String:Any]
        check((blankObject["sessionReflections"] as? [[String:Any]])?.isEmpty==true,"saved whitespace-only thoughts are excluded")
        let disclosed=AssistantPrompts.reflectionPreviewLines(context:withThought).joined(separator:"\n")
        check(disclosed.contains(savedThought) && disclosed.contains("用户写下的想法") && disclosed.contains("当天任务 · 当时小任务") && !disclosed.contains("original-step"),"review preview shows exact included multiline user thought with readable attribution")
        check(AssistantPrompts.reflectionPreviewLines(context:withThought+"\n用户补充：这是另外的补充").joined(separator:"\n").contains(savedThought),"saved review turn with supplemental text still discloses the captured thought exactly")
        check(!AssistantPrompts.taskContext(state.tasks[0]).contains(savedThought),"task decomposition does not gain reflection context")
        finish()
    }
    static func finish() {
        if failures.isEmpty { print("PASS: \(checks) AI reply, context and journal checks") }
        else { failures.forEach { print("FAIL: \($0)") }; exit(1) }
    }
}
