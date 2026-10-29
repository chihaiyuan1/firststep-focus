import Foundation
@main struct WeeklyReviewChecks {
    static func main() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 8*3600)!
        let iso = ISO8601DateFormatter()
        func t(_ text: String) -> Double { iso.date(from: text)!.timeIntervalSince1970 }
        let monday = t("2026-10-18T16:00:00Z"), sunday = t("2026-10-25T15:00:00Z"), next = t("2026-10-25T16:00:00Z")
        func record(_ id: String, _ time: Double) -> FocusRecord { FocusRecord(id: id, taskID: "task", title: "原任务", startAt: time, endAt: time + 600, focusSeconds: 600, finished: true, accessCount: 0) }
        var state = FocusState()
        state.tasks = [FocusTask(id:"scheduled",title:"本周安排",nextStep:"",day:"2026-10-01",scheduledDay:"2026-10-20"), FocusTask(id:"old",title:"过去未推进",nextStep:"",day:"2026-10-01"), FocusTask(id:"later",title:"未来安排",nextStep:"",day:"2026-10-20",scheduledDay:"2026-11-02")]
        state.history = [record("monday",monday), record("sunday",sunday), record("next",next)]
        state.completionRecords = [TaskCompletionRecord(taskID: "task", title: "本周完成", completedAt: sunday), TaskCompletionRecord(taskID: "other", title: "下周完成", completedAt: next), TaskCompletionRecord(taskID: "unknown", title: "未知完成", completedAt: nil)]
        let entries = [try TimeEntry(day:"2026-10-20",startMinute:540,endMinute:600,title:"实际记录",taskID:"old",taskTitleSnapshot:"关联时旧任务"), try TimeEntry(day:"2026-10-26",startMinute:540,endMinute:600,title:"不属于本周")]
        let thoughts = [SessionReflection(recordID:"monday",text:"已保存的想法",draft:"未保存草稿",savedAt:monday+700), SessionReflection(recordID:"sunday",text:"未保存想法")]
        let context = AssistantPrompts.weeklyReviewContext(state:state, entries:entries, on:Date(timeIntervalSince1970:monday), reflections:thoughts, calendar:c)
        let object = try JSONSerialization.jsonObject(with:Data(context.utf8)) as! [String:Any]
        let selectedTasks = object["currentTasks"] as! [[String:Any]]
        precondition(selectedTasks.contains { $0["title"] as? String == "本周安排" && $0["scheduledDay"] as? String == "2026-10-20" })
        precondition(!selectedTasks.contains { $0["title"] as? String == "未来安排" })
        precondition(selectedTasks.contains { $0["title"] as? String == "过去未推进" })
        let completionRows = object["completedTasks"] as! [[String:Any]]
        precondition(completionRows[0]["lifetimeFocusSeconds"] != nil && completionRows[0]["focusSeconds"] == nil)
        precondition(object["completedPomodoros"] as? Int == 2)
        precondition((object["completedTasks"] as! [[String:Any]]).count == 1)
        precondition((object["manualTimeEntries"] as! [[String:Any]]).count == 1)
        precondition((object["manualTimeEntries"] as! [[String:Any]])[0]["linkedTaskTitle"] as? String == "关联时旧任务")
        precondition((object["sessionReflections"] as! [[String:Any]]).count == 1)
        precondition(context.contains("已保存的想法") && !context.contains("未保存草稿") && !context.contains("下周完成"))
        let preview = AssistantPrompts.weeklyReviewPreviewLines(context:context).joined(separator:"\n")
        precondition(preview.contains("本周安排") && preview.contains("实际记录") && preview.contains("关联时旧任务") && preview.contains("截至完成累计") && preview.contains("已保存的想法"))
        precondition(!preview.contains("未保存草稿") && !preview.contains("下周完成"))
        var subtaskState = FocusState()
        subtaskState.tasks = [FocusTask(id:"parent",title:"旧任务",nextStep:"",day:"2026-10-01",subtasks:[FocusSubtask(id:"step",title:"今日完成步骤",completed:true,completedAt:sunday)])]
        precondition(AssistantPrompts.reviewTasks(state:subtaskState,day:FocusState.day(at:sunday)).contains { $0.id == "parent" }, "daily review must include parent of a subtask completed today")
        print("PASS: week boundary, completed snapshots, manual logs and saved thoughts only")
    }
}
