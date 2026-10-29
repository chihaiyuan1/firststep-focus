import Foundation
import Darwin

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
private func object(_ text: String) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
}
private func date(_ day: String, _ minute: Int = 0) -> Date {
    TimeGrid.date(for: day)!.addingTimeInterval(Double(minute * 60))
}
private func fixtureContext(_ day: String = "2026-10-23") throws -> ChatDayContext {
    try ChatDayContext.capture(state: FocusState(), entries: [], now: date(day, 600))
}
private func exchange(_ suffix: String, context: ChatDayContext, at: Double = 100) -> (ChatMessage, ChatMessage) {
    (ChatMessage(id: "q-" + suffix, role: "user", content: "问题" + suffix, createdAt: at, context: context),
     ChatMessage(id: "a-" + suffix, role: "assistant", content: "回答" + suffix, createdAt: at + 1))
}
private func readDocument(_ url: URL) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
}
private func writeDocument(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
}

@main struct FreeChatChecks {
    static func main() throws {
        // Mutations caught: using review-only task scope, including deleted/all-day logs,
        // counting by end day, adding active/manual duration, or serializing whole state.
        let today = "2026-10-23", yesterday = "2026-10-22"
        let now = date(today, 600)
        let midnight = date(today).timeIntervalSince1970
        var state = FocusState()
        let step = FocusSubtask(id: "step", title: "已完成小任务", completed: true, completedAt: midnight + 60)
        state.tasks = [
            FocusTask(id: "old-open", title: "旧日未完成", nextStep: "先核对资料", day: yesterday, subtasks: [step]),
            FocusTask(id: "today", title: "今天安排", nextStep: "", day: today),
            FocusTask(id: "done-today", title: "今日完成旧任务", nextStep: "", day: yesterday, completed: true, completedAt: midnight + 100),
            FocusTask(id: "focused", title: "今日专注旧任务", nextStep: "", day: yesterday, completed: true),
            FocusTask(id: "unrelated", title: "不相关的旧完成任务", nextStep: "", day: yesterday, completed: true)
        ]
        state.history = [
            FocusRecord(id: "cross-old", taskID: "unrelated", title: "昨天开始跨午夜", startAt: midnight - 600, endAt: midnight + 900, focusSeconds: 1200, finished: true, accessCount: 1),
            FocusRecord(id: "today-focus", taskID: "focused", title: "今日净专注", startAt: midnight + 9 * 3600, endAt: midnight + 10 * 3600, focusSeconds: 1500, finished: true, accessCount: 2),
            FocusRecord(id: "early", taskID: "today", title: "提前结束投入", startAt: midnight + 8 * 3600, endAt: midnight + 8 * 3600 + 600, focusSeconds: 500, finished: false, accessCount: 0)
        ]
        state.session = Session(id: "active", taskID: "old-open", title: "运行中的任务", nextStep: "进行中", startAt: midnight + 3600, endAt: midnight + 7200, allowances: [Allowance(site: "secret-blocked.example", startAt: midnight + 3601, endAt: midnight + 3700, reason: "不发送的临时理由")], subtaskID: "step", subtaskTitle: "当前小任务")
        state.inboxItems = [InboxItem(id: "secret-inbox", title: "不发送收集箱", createdAt: 100)]
        state.extensionError = "不发送授权信息"
        var deleted = try TimeEntry(id: "deleted", day: today, startMinute: 600, endMinute: 660, title: "不发送已删除记录", note: "不发送已删备注")
        deleted.deletedAt = midnight + 10
        let logs = [
            try TimeEntry(id: "one", day: today, startMinute: 540, endMinute: 600, title: "重叠日志一", note: "需要核对的备注"),
            try TimeEntry(id: "two", day: today, startMinute: 570, endMinute: 630, title: "重叠日志二"),
            try TimeEntry(id: "old", day: yesterday, startMinute: 540, endMinute: 600, title: "不发送昨日日志"), deleted
        ]
        let context = try ChatDayContext.capture(state: state, entries: logs, now: now)
        let snapshot = try object(context.text)
        check(context.day == today && context.capturedAt == now.timeIntervalSince1970 && context.timezone == TimeZone.current.identifier, "capture records the current local day, timestamp and timezone")
        check(context.taskCount == 4 && context.timeEntryCount == 2 && context.focusCount == 2, "capture counts exactly the disclosed rows")
        let tasks = snapshot["tasks"] as! [[String: Any]]
        check(Set(tasks.compactMap { $0["id"] as? String }) == ["old-open", "today", "done-today", "focused"], "old open, scheduled, completed and referenced tasks are included")
        check(context.text.contains("已完成小任务") && context.text.contains("先核对资料") && context.text.contains("需要核对的备注"), "snapshot retains subtask state, next step and manual notes")
        check(!context.text.contains("不发送") && !context.text.contains("secret-blocked") && !context.text.contains("不相关的旧完成任务") && !context.text.contains("昨天开始跨午夜"), "snapshot excludes inbox, private state, old/deleted logs and unrelated history")
        let summary = snapshot["focusSummary"] as! [String: Any]
        check(summary["focusSeconds"] as? Double == 2000 && summary["completedPomodoros"] as? Int == 1 && summary["earlyEnds"] as? Int == 1, "only saved net focus enters completed summary, without manual or active duration")
        let active = snapshot["activeSession"] as! [String: Any]
        check(active["id"] as? String == "active" && active["subtaskTitle"] as? String == "当前小任务", "active session is disclosed independently")
        let tomorrow = try ChatDayContext.capture(state: state, entries: logs, now: date("2026-10-24", 1))
        check(tomorrow.day == "2026-10-24" && tomorrow.focusCount == 0 && tomorrow.timeEntryCount == 0 && tomorrow.taskCount == 2, "a new capture after midnight uses the new day and retains old open tasks")
        var scheduledState = FocusState()
        scheduledState.tasks = [
            FocusTask(id:"future",title:"未来事项不发送",nextStep:"",day:today,scheduledDay:"2026-11-03"),
            FocusTask(id:"due",title:"已经到期的事项",nextStep:"",day:yesterday,scheduledDay:today),
            FocusTask(id:"worked",title:"今日已专注的未来事项",nextStep:"",day:yesterday,scheduledDay:"2026-11-03"),
            FocusTask(id:"completed",title:"今日完成的未来事项",nextStep:"",day:yesterday,completed:true,completedAt:midnight+100,scheduledDay:"2026-11-03"),
            FocusTask(id:"child",title:"今日完成小任务的未来事项",nextStep:"",day:yesterday,completed:true,subtasks:[step],scheduledDay:"2026-11-03"),
            FocusTask(id:"active-future",title:"进行中的未来事项",nextStep:"",day:yesterday,scheduledDay:"2026-11-03")
        ]
        scheduledState.history = [FocusRecord(id:"worked-record",taskID:"worked",title:"今日已专注的未来事项",startAt:midnight+1000,endAt:midnight+1600,focusSeconds:600,finished:false,accessCount:0)]
        scheduledState.session = Session(taskID:"active-future",title:"进行中的未来事项",nextStep:"",startAt:midnight-10,endAt:midnight+1000)
        let scheduledCapture = try ChatDayContext.capture(state:scheduledState,entries:[],now:now)
        let scheduledRows = try object(scheduledCapture.text)["tasks"] as! [[String:Any]]
        let scheduledIDs = Set(scheduledRows.compactMap { $0["id"] as? String })
        check(!scheduledIDs.contains("future") && !scheduledCapture.text.contains("未来事项不发送"), "future scheduled task with no today activity must not be sent")
        check(scheduledIDs == ["due","worked","completed","child","active-future"], "due and today-related focus, completion, subtask and active tasks remain in snapshot")
        check(scheduledRows.first { $0["id"] as? String == "worked" }?["scheduledDay"] as? String == "2026-11-03", "captured task must use its actual explicit planned date")
        check(scheduledRows.first { $0["id"] as? String == "due" }?["scheduledDay"] as? String == today, "due task exposes planned date instead of earlier original date")
        let linkedLog = try TimeEntry(day:today,startMinute:540,endMinute:600,title:"核对资料",taskID:"future",taskTitleSnapshot:"记录时的任务名")
        let linkedCapture = try ChatDayContext.capture(state:scheduledState,entries:[linkedLog],now:now)
        let linkedObject = try object(linkedCapture.text)
        let linkedRows = linkedObject["manualTimeEntries"] as! [[String:Any]]
        let linkedTasks = linkedObject["tasks"] as! [[String:Any]]
        check(linkedRows.first?["linkedTaskTitle"] as? String == "记录时的任务名" && linkedCapture.previewLines.joined().contains("记录时的任务名"),"linked task snapshot is sent and disclosed")
        check(linkedTasks.contains { $0["id"] as? String == "future" },"a future task with a manual record today is included as relevant")
        // Mutations caught: previewing a freshly filtered state instead of the captured
        // payload, omitting newly completed subtasks, or formatting with today's timezone.
        var previewState = state
        previewState.tasks.append(FocusTask(id: "old-finished-parent-identifier", title: "已完成旧主任务", nextStep: "旧主任务的下一步", day: yesterday, completed: true,
            subtasks: [FocusSubtask(id: "recent-step-identifier", title: "今天才完成的小任务", completed: true, completedAt: midnight + 30)], completedAt: midnight - 100))
        previewState.history[1].subtaskTitle = "净专注的小标题"
        let previewContext = try ChatDayContext.capture(state: previewState, entries: logs, now: now)
        let previewLines = previewContext.previewLines
        let preview = previewLines.joined(separator: "\n")
        check(preview.contains("已完成旧主任务") && preview.contains("今天才完成的小任务") && preview.contains("旧主任务的下一步"), "preview includes old completed parent when its subtask was completed today")
        check(preview.contains("当前状态：已完成") && preview.contains("当前状态：未完成") && preview.contains("完成日期：2026-10-22") && preview.contains("完成日期：2026-10-23"), "preview explains current task and subtask state and completion day")
        check(preview.contains("09:00–10:00") && preview.contains("需要核对的备注") && preview.contains("重叠日志二"), "manual preview retains wall-clock interval and notes")
        check(preview.contains("净专注 33.3 分钟") && preview.contains("完整 1 次") && preview.contains("提前结束 1 次"), "preview reports only net completed-record summary with separate round counts")
        check(preview.contains("今日净专注 · 净专注的小标题") && preview.contains("净专注 25 分钟") && preview.contains("临时访问 2 次") && preview.contains("2026-10-23 09:00") && preview.contains("2026-10-23 10:00"), "focus preview shows task and subtask, local interval, net minutes and access count")
        check(previewLines.contains { $0.contains("运行中的任务 · 当前小任务") && $0.contains("快照当时进行中") && $0.contains("不计入汇总") }, "active session preview is a separate row marked active at capture and excluded from totals")
        check(!preview.contains("不发送") && !preview.contains("secret-blocked") && !preview.contains("old-finished-parent-identifier") && !preview.contains("recent-step-identifier") && !preview.contains("today-focus"), "readable preview excludes inbox, old/deleted logs and internal identifiers")
        previewState.tasks.removeAll(); previewState.history.removeAll(); previewState.session = nil
        _ = try ChatDayContext.capture(state: previewState, entries: [], now: date("2026-10-24", 1))
        let restoredPreview = try JSONDecoder().decode(ChatDayContext.self, from: JSONEncoder().encode(previewContext))
        check(restoredPreview.previewLines == previewLines, "saved context preview retains the original content after business state changes")
        var fixedZoneContext = previewContext; fixedZoneContext.timezone = "Pacific/Honolulu"
        let fixedInstant = Date(timeIntervalSince1970: 0)
        var fixedSnapshot = try object(fixedZoneContext.text)
        fixedSnapshot["focusRecords"] = [["id": "fixed-zone-id", "title": "固定时区专注", "startAt": fixedInstant.timeIntervalSince1970, "endAt": 1800, "focusSeconds": 1500, "finished": true, "temporaryAccessCount": 0]]
        fixedSnapshot["activeSession"] = ["id": "fixed-active-id", "title": "固定时区会话", "startAt": 0, "plannedEndAt": 1800]
        fixedZoneContext.text = String(data: try JSONSerialization.data(withJSONObject: fixedSnapshot), encoding: .utf8)!
        let zonedPreview = fixedZoneContext.previewLines.joined(separator: "\n")
        check(zonedPreview.contains("1969-12-31 14:00") && zonedPreview.contains("1969-12-31 14:30") && !zonedPreview.contains("fixed-zone-id") && !zonedPreview.contains("fixed-active-id"), "saved timezone controls both focus and active timestamps instead of the current timezone")
        // A saved snapshot must disclose exactly the user-written text, including its line breaks.
        var reflectionPreview = previewContext
        var reflectionSnapshot = try object(reflectionPreview.text)
        let savedThought = "第一行：已核对 🧭\n第二行：仍需确认 e\u{301}"
        reflectionSnapshot["sessionReflections"] = [["recordID": "today-focus", "taskID": "focused", "title": "当时主任务", "subtaskID": "old-step", "subtaskTitle": "当时小任务", "text": savedThought]]
        reflectionPreview.text = String(data: try JSONSerialization.data(withJSONObject: reflectionSnapshot), encoding: .utf8)!
        let savedThoughtPreview = reflectionPreview.previewLines.joined(separator: "\n")
        check(savedThoughtPreview.contains(savedThought) && savedThoughtPreview.contains("用户写下的想法") && savedThoughtPreview.contains("当时主任务 · 当时小任务"), "saved source preview discloses exact multiline Unicode thought with original attribution and user-written label")
        check(!savedThoughtPreview.contains("today-focus") && !savedThoughtPreview.contains("old-step"), "saved thought preview does not disclose internal IDs")
        var malformedPreview = context; malformedPreview.text = "{broken"
        check(!malformedPreview.previewLines.isEmpty && !malformedPreview.previewLines.joined().contains("{broken"), "invalid snapshot preview fails visibly without exposing raw JSON")
        var largeState = FocusState()
        largeState.tasks = (0..<180).map { FocusTask(id: "large-\($0)", title: String(repeating: "中", count: 120), nextStep: "", day: today) }
        rejects("oversized snapshots fail instead of silently dropping rows") { _ = try ChatDayContext.capture(state: largeState, entries: [], now: now) }

        var reflectionState=state
        reflectionState.history[1].subtaskID="past-step";reflectionState.history[1].subtaskTitle="当时的小任务"
        let reflectionText=" 已保存的想法 🧭\n保留第二行 e\u{301} "
        let reflections=[
            SessionReflection(recordID:"today-focus",text:reflectionText,draft:"不发送编辑草稿",updatedAt:midnight+86400,savedAt:midnight+86400),
            SessionReflection(recordID:"cross-old",text:"不发送昨日起始轮次想法",updatedAt:midnight+100,savedAt:midnight+100),
            SessionReflection(recordID:"early",text:"不发送未保存想法",draft:"不发送草稿",updatedAt:midnight,savedAt:nil),
            SessionReflection(recordID:"orphan",text:"不发送孤立想法",updatedAt:midnight,savedAt:midnight)
        ]
        let reflected=try ChatDayContext.capture(state:reflectionState,entries:[],now:now,reflections:reflections)
        let reflectedRows=try object(reflected.text)["sessionReflections"] as! [[String:Any]]
        check(reflectedRows.count==1 && reflectedRows[0]["recordID"] as? String=="today-focus" && reflectedRows[0]["title"] as? String=="今日净专注" && reflectedRows[0]["subtaskTitle"] as? String=="当时的小任务","chat includes saved thought with original record and parent/subtask attribution")
        check(reflectedRows[0]["text"] as? String==reflectionText && !reflected.text.contains("不发送") && !reflected.text.contains("draft") && !reflected.text.contains("focus-reflections.json"),"chat sends last saved text exactly while excluding drafts, orphan notes, other days and local metadata")
        check(reflected.previewLines.joined(separator:"\n").contains(reflectionText),"chat source disclosure preserves saved whitespace and newlines")
        let afterMidnight=try ChatDayContext.capture(state:reflectionState,entries:[],now:date("2026-10-24",1),reflections:reflections)
        check(!afterMidnight.text.contains("已保存的想法"),"thought edited tomorrow remains associated with original start day")
        let cleared=[SessionReflection(recordID:"early",text:" \n\t",updatedAt:midnight,savedAt:midnight)]
        let clearedContext=try ChatDayContext.capture(state:reflectionState,entries:[],now:now,reflections:cleared)
        check((try object(clearedContext.text)["sessionReflections"] as? [[String:Any]])?.isEmpty==true,"saved blank thought is omitted from chat")
        let longNotes=reflectionState.history.filter {$0.id != "cross-old"}.map {SessionReflection(recordID:$0.id,text:String(repeating:"想",count:8000),updatedAt:midnight,savedAt:midnight)}
        rejects("saved thoughts that exceed snapshot limit fail visibly without truncation") {_ = try ChatDayContext.capture(state:reflectionState,entries:[],now:now,reflections:longNotes)}
        let savedSnapshot=try JSONDecoder().decode(ChatDayContext.self,from:JSONEncoder().encode(reflected))
        check(savedSnapshot.previewLines==reflected.previewLines,"reopened chat retains exact sent thought even after external edits")

        // Mutations caught: cutting an odd message window, replaying all history, losing
        // historical dates, accepting blank/oversized questions or malformed pairs.
        let oldContext = try fixtureContext(yesterday)
        var history: [ChatMessage] = []
        for i in 0..<7 { let pair = exchange(String(i), context: i < 4 ? oldContext : context); history += [pair.0, pair.1] }
        let turns = try ChatPrompts.messages(history: history, question: "接下来怎样安排？", context: context)
        check(turns.count == 12 && turns.first?.role == "user" && turns.first?.content.contains(context.text) == true, "current snapshot precedes five complete exchanges and the question")
        check(turns[1].content.contains("问题2") && turns[2].content == "回答2" && turns[9].content.contains("问题6") && turns[10].content == "回答6", "latest five full pairs retain order and content")
        check(!turns.contains { $0.content.contains("问题0") || $0.content.contains("问题1") }, "older exchanges are not replayed")
        check(turns[1].content.contains(yesterday) && turns[5].content.contains(today), "each historical question keeps its own snapshot day across midnight")
        check(turns.last?.content == "接下来怎样安排？", "new question remains its own user turn")
        check(try ChatPrompts.messages(history: [], question: String(repeating: "中", count: 8000), context: context).count == 2, "8000-character question boundary is accepted")
        var longHistory = [history[0], history[1]]; longHistory[0].content = String(repeating: "问", count: 16000); longHistory[1].content = String(repeating: "答", count: 16000)
        check(try ChatPrompts.messages(history: longHistory, question: "继续", context: context).count == 4, "each historical message accepts the 16000-character boundary")
        rejects("blank questions are rejected") { _ = try ChatPrompts.messages(history: [], question: " \n\t", context: context) }
        rejects("8001-character questions are rejected") { _ = try ChatPrompts.messages(history: [], question: String(repeating: "中", count: 8001), context: context) }
        rejects("incomplete history is rejected") { _ = try ChatPrompts.messages(history: [history[0]], question: "继续", context: context) }
        var oversize = history; oversize[0].content = String(repeating: "中", count: 16001)
        rejects("oversized history is rejected even outside the replay window") { _ = try ChatPrompts.messages(history: oversize, question: "继续", context: context) }
        var badRoles = history; badRoles[1].role = "user"
        rejects("malformed history roles are rejected") { _ = try ChatPrompts.messages(history: badRoles, question: "继续", context: context) }
        var badContext = context; badContext.text = "{}"
        rejects("missing snapshot fields cannot be sent as current context") { _ = try ChatPrompts.messages(history: [], question: "继续", context: badContext) }

        // Mutations caught: non-atomic half saves, revision lost updates, ID collisions,
        // malformed files being replaced, unsafe permissions and old journal mutation.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("free-chat-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ChatStore(directory: dir)
        check(try store.read().isEmpty, "new chat store reads as empty")
        let journalURL = dir.appendingPathComponent("ai-journal.json")
        let oldJournal = Data("existing-journal-sentinel".utf8); try oldJournal.write(to: journalURL)
        let pair = exchange("first", context: context)
        let first = try store.appendExchange(id: "one", title: "第一段对话", expectedRevision: 0, question: pair.0, answer: pair.1)
        check(first.count == 1 && first[0].revision == 1 && first[0].messages == [pair.0, pair.1], "a successful exchange saves exactly one pair and increments revision")
        check(try store.appendExchange(id: "one", title: "第一段对话", expectedRevision: 0, question: pair.0, answer: pair.1) == first, "identical exchange retry is idempotent after a successful write")
        var changedPair = pair; changedPair.1.content = "冲突的回答"
        rejects("same IDs with different content cannot be retried") { _ = try store.appendExchange(id: "one", title: "第一段对话", expectedRevision: 0, question: changedPair.0, answer: changedPair.1) }
        check(try store.read() == first && Data(contentsOf: journalURL) == oldJournal, "read roundtrip retains snapshots and does not touch the old AI journal")
        let url = dir.appendingPathComponent("ai-chats.json")
        check(try readDocument(url)["schema"] as? Int == 1, "chat document uses schema 1")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
        check(permissions.intValue & 0o777 == 0o600, "chat data is private 0600")
        let lockPermissions = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("ai-chats.lock").path)[.posixPermissions] as! NSNumber
        check(lockPermissions.intValue & 0o777 == 0o600, "chat lock is private 0600")
        let secondPair = exchange("second", context: context, at: 200)
        rejects("stale revision cannot overwrite saved conversation") { _ = try store.appendExchange(id: "one", title: "第一段对话", expectedRevision: 0, question: secondPair.0, answer: secondPair.1) }
        check(try store.read()[0].messages.count == 2, "rejected revision leaves the original pair intact")
        _ = try store.appendExchange(id: "one", title: "第一段对话", expectedRevision: 1, question: secondPair.0, answer: secondPair.1)
        let newer = exchange("newer", context: context, at: 300)
        let sorted = try store.appendExchange(id: "two", title: "第二段对话", expectedRevision: 0, question: newer.0, answer: newer.1)
        check(sorted.map(\.id) == ["two", "one"] && sorted.last?.revision == 2, "conversations are newest-updated first")
        rejects("message IDs cannot collide with an earlier exchange") { _ = try store.appendExchange(id: "two", title: "第二段对话", expectedRevision: 1, question: pair.0, answer: pair.1) }
        var duplicateID = exchange("duplicate", context: context); duplicateID.1.id = duplicateID.0.id
        rejects("same exchange cannot reuse a message ID") { _ = try store.appendExchange(id: "three", title: "第三段", expectedRevision: 0, question: duplicateID.0, answer: duplicateID.1) }
        var missingContext = exchange("no-context", context: context); missingContext.0.context = nil
        rejects("question requires a captured context") { _ = try store.appendExchange(id: "three", title: "第三段", expectedRevision: 0, question: missingContext.0, answer: missingContext.1) }
        var assistantContext = exchange("extra-context", context: context); assistantContext.1.context = context
        rejects("assistant must not carry a second context") { _ = try store.appendExchange(id: "three", title: "第三段", expectedRevision: 0, question: assistantContext.0, answer: assistantContext.1) }
        var blank = exchange("blank", context: context); blank.1.content = " \n"
        rejects("blank assistant result cannot be saved") { _ = try store.appendExchange(id: "three", title: "第三段", expectedRevision: 0, question: blank.0, answer: blank.1) }
        var longQuestion = exchange("long-question", context: context); longQuestion.0.content = String(repeating: "问", count: 8001)
        rejects("new saved questions cannot exceed 8000 characters") { _ = try store.appendExchange(id: "three", title: "第三段", expectedRevision: 0, question: longQuestion.0, answer: longQuestion.1) }
        let cleanPair = exchange("clean", context: context)
        rejects("blank conversation ID is rejected") { _ = try store.appendExchange(id: " \n", title: "第三段", expectedRevision: 0, question: cleanPair.0, answer: cleanPair.1) }
        rejects("blank conversation title is rejected") { _ = try store.appendExchange(id: "three", title: " \n", expectedRevision: 0, question: blank.0, answer: pair.1) }
        rejects("new conversations require revision zero") { _ = try store.appendExchange(id: "three", title: "第三段", expectedRevision: 1, question: blank.0, answer: pair.1) }

        let raceDir = dir.appendingPathComponent("race")
        let group = DispatchGroup(), resultLock = NSLock()
        var wins = 0, losses = 0
        for i in 0..<8 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let candidate = exchange("race-\(i)", context: context)
                    _ = try ChatStore(directory: raceDir).appendExchange(id: "race", title: "并发对话", expectedRevision: 0, question: candidate.0, answer: candidate.1)
                    resultLock.lock(); wins += 1; resultLock.unlock()
                } catch { resultLock.lock(); losses += 1; resultLock.unlock() }
            }
        }
        group.wait()
        let raced = try ChatStore(directory: raceDir).read()
        check(wins == 1 && losses == 7 && raced.first?.messages.count == 2, "flock permits one revision winner and no half pair under concurrent writers")

        let validDocument = try readDocument(url)
        var invalidSchema = validDocument; invalidSchema["schema"] = 2
        try writeDocument(invalidSchema, to: url)
        let invalidSchemaBytes = try Data(contentsOf: url)
        rejects("future schema is rejected") { _ = try store.read() }
        rejects("future schema is preserved on append") { _ = try store.appendExchange(id: "safe", title: "新对话", expectedRevision: 0, question: cleanPair.0, answer: cleanPair.1) }
        check(try Data(contentsOf: url) == invalidSchemaBytes, "future schema bytes remain unchanged")
        var halfDocument = validDocument
        var halfRows = halfDocument["conversations"] as! [[String: Any]]
        var halfMessages = halfRows[0]["messages"] as! [[String: Any]]; halfMessages.removeLast()
        halfRows[0]["messages"] = halfMessages; halfDocument["conversations"] = halfRows
        try writeDocument(halfDocument, to: url)
        rejects("a persisted half exchange is rejected") { _ = try store.read() }
        var invalidRevision = validDocument
        var revisionRows = invalidRevision["conversations"] as! [[String: Any]]; revisionRows[0]["revision"] = 99; invalidRevision["conversations"] = revisionRows
        try writeDocument(invalidRevision, to: url)
        rejects("a persisted revision inconsistent with saved pairs is rejected") { _ = try store.read() }
        var duplicateDocument = validDocument
        var rows = duplicateDocument["conversations"] as! [[String: Any]]; rows.append(rows[0]); duplicateDocument["conversations"] = rows
        try writeDocument(duplicateDocument, to: url)
        let duplicateBytes = try Data(contentsOf: url)
        rejects("duplicate conversation IDs make the document unreadable") { _ = try store.read() }
        rejects("invalid document cannot be overwritten by an append") { _ = try store.appendExchange(id: "safe", title: "新对话", expectedRevision: 0, question: newer.0, answer: newer.1) }
        check(try Data(contentsOf: url) == duplicateBytes, "invalid structured document is preserved byte-for-byte")
        let broken = Data("{broken".utf8); try broken.write(to: url)
        rejects("truncated JSON is rejected") { _ = try store.read() }
        rejects("truncated JSON is never replaced by a fresh chat") { _ = try store.appendExchange(id: "safe", title: "新对话", expectedRevision: 0, question: newer.0, answer: newer.1) }
        check(try Data(contentsOf: url) == broken && Data(contentsOf: journalURL) == oldJournal, "damaged chat and legacy journal remain unchanged")
        if failures.isEmpty { print("PASS: \(checks) free chat context, prompt and atomic store checks") }
        else { failures.forEach { print("FAIL: \($0)") }; exit(1) }
    }
}
