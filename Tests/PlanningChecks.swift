import Foundation

@main struct PlanningChecks {
    static func main() throws {
        let now = TimeGrid.date(for: "2026-10-29")!.timeIntervalSince1970 + 9*3600
        var state = FocusState()
        try state.apply(Command("addInbox", title: "整理测试资料"), now: now)
        let id = state.activeInboxItems[0].id
        try state.apply(Command("scheduleInbox", taskID: id, scheduledDay: "2026-10-30", reminderAt: now + 90000), now: now)
        precondition(state.activeInboxItems[0].scheduledDay == "2026-10-30")
        precondition(state.activeInboxItems[0].reminderAt == now + 90000)
        precondition(state.nextTaskReminder(now: now + 90000, focusActive: true) == nil)
        precondition(state.nextTaskReminder(now: now + 90000, focusActive: false)?.id == id)
        try state.apply(Command("scheduleInbox", taskID: id, scheduledDay: "2026-10-30", reminderAt: now + 90600), now: now + 90000)
        precondition(state.nextTaskReminder(now: now + 90001, focusActive: false) == nil)
        precondition(state.nextTaskReminder(now: now + 90600, focusActive: false)?.id == id)
        precondition(!state.planningCandidates(day: "2026-10-29").contains(where: { $0.id == id }))
        precondition(state.planningCandidates(day: "2026-10-30").contains(where: { $0.id == id }))
        try state.apply(Command("moveInboxToday", taskID: id), now: now)
        precondition(state.tasks[0].id == id && state.tasks[0].scheduledDay == "2026-10-29" && state.tasks[0].reminderAt == now + 90600, "moving inbox to today must preserve future reminder")
        try state.apply(Command("scheduleTask", taskID: id, scheduledDay: "2026-10-30"), now: now)
        precondition(!state.visibleTasks(day: "2026-10-29").contains(where: { $0.id == id }))
        precondition(state.visibleTasks(day: "2026-10-30").contains(where: { $0.id == id }))
        try state.apply(Command("scheduleTask", taskID: id, scheduledDay: "2026-10-30", reminderAt:now+90000), now:now)
        try state.apply(Command("moveToday", taskID: id), now: now)
        precondition(state.tasks[0].scheduledDay == "2026-10-29" && state.tasks[0].reminderAt == now+90000, "moving existing task to today must preserve future reminder")
        precondition(state.visibleTasks(day: "2026-10-29").contains(where: { $0.id == id }))
        try state.apply(Command("scheduleTask", taskID:id, scheduledDay:"2026-10-29", reminderAt:now+60), now:now)
        try state.apply(Command("completeTask", taskID:id), now:now)
        try state.apply(Command("completeTask", taskID:id), now:now)
        precondition(state.nextTaskReminder(now:now+100, focusActive:false) == nil, "restoring completed task must not replay old reminder")
        try state.apply(Command("addInbox",title:"第一个提醒"),now:now)
        try state.apply(Command("addInbox",title:"第二个提醒"),now:now)
        let first = state.activeInboxItems[0].id, second = state.activeInboxItems[1].id
        try state.apply(Command("scheduleInbox",taskID:first,scheduledDay:"2026-10-29",reminderAt:now+5),now:now)
        try state.apply(Command("scheduleInbox",taskID:second,scheduledDay:"2026-10-29",reminderAt:now+10),now:now)
        precondition(state.dueTaskReminders(now:now+11,focusActive:false).count == 2)
        try state.apply(Command("dismissInboxReminder",taskID:first),now:now+11)
        precondition(state.nextTaskReminder(now:now+11,focusActive:false)?.id == second)
        try state.apply(Command("moveInboxToday",taskID:second),now:now+11)
        precondition(state.nextTaskReminder(now:now+11,focusActive:false)?.id == second, "moving a due item must preserve deferred reminder")
        try state.apply(Command("moveToday",taskID:second,consumeReminder:true),now:now+11)
        precondition(state.nextTaskReminder(now:now+11,focusActive:false) == nil, "reminder action must consume the handled reminder")
        var focusing = FocusState()
        try focusing.apply(Command("addTask",title:"专注中的任务"),now:now)
        let focusID = focusing.tasks[0].id
        try focusing.apply(Command("addInbox",title:"中途到期事项"),now:now)
        let duringFocusID = focusing.activeInboxItems[0].id
        try focusing.apply(Command("scheduleInbox",taskID:duringFocusID,scheduledDay:"2026-10-29",reminderAt:now+5),now:now)
        try focusing.apply(Command("start",taskID:focusID,minutes:15),now:now)
        try focusing.apply(Command("moveInboxToday",taskID:duringFocusID),now:now+10)
        precondition(focusing.nextTaskReminder(now:now+10,focusActive:true) == nil)
        focusing.tick(now:now+901)
        precondition(focusing.nextTaskReminder(now:now+901,focusActive:false)?.id == duringFocusID, "reminder stays deferred after moving during focus")
        let originalDay = TimeGrid.date(for:"2026-10-29")!
        let nextDay = TimeGrid.date(for:"2026-10-30")!
        let afterMidnight = nextDay.addingTimeInterval(5 * 60)
        precondition(ScheduleTimes.reminderWhenMovingPlan(afterMidnight, from:originalDay, to:originalDay) == afterMidnight, "editing must preserve snooze across midnight")
        precondition(ScheduleTimes.reminderWhenMovingPlan(originalDay.addingTimeInterval(10*3600), from:originalDay, to:nextDay) == nextDay.addingTimeInterval(10*3600), "moving a same-day reminder follows the plan date")
        do { try state.apply(Command("scheduleTask", taskID: id, scheduledDay: "2026-02-30"), now: now); fatalError("invalid date accepted") } catch {}
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(FocusState.self, from: data)
        precondition(restored.tasks[0].id == id)
        print("PASS: schedule, move, defer, invalid dates and round trip")
    }
}
