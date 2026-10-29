import Foundation
import FocusCore

@main struct HabitModelChecks {
    @MainActor static func main() throws {
        let fm=FileManager.default
        let dir=fm.temporaryDirectory.appendingPathComponent("firststep-habit-model-"+UUID().uuidString)
        try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:dir) }
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:8*3600)!
        let day="2026-10-28"
        let base=HabitDates.date(for:day,calendar:calendar)!.timeIntervalSince1970
        let clock=base+12*3600.0
        let store=HabitStore(directory:dir)
        let draft=HabitDraft(name:"自选运动",minimumAction:"活动一分钟",anchor:"午饭后",weekdays:[1,2,3,4,5,6,7],reminderMinute:12*60+1)
        let initial=try store.saveHabit(id:nil,draft:draft,now:clock,calendar:calendar)
        let habitID=initial.habits[0].id
        let model=HabitModel(directory:dir,calendar:calendar,now:clock)
        var changes=0;model.onChange={changes+=1}
        model.monthDate=HabitDates.date(for:"2026-09-01",calendar:calendar)!
        model.toggleToday(habitID)
        precondition(model.selectedID==habitID && model.data.completion(habitID:habitID,day:day) != nil,"one card action completes and selects habit")
        precondition(calendar.component(.month,from:model.monthDate)==10,"today card returns to current month")
        precondition(model.todayPlannedCount==1 && model.todayCompletedCount==1 && changes>0,"live count and immediate callback")
        let completedAt=model.data.completion(habitID:habitID,day:day)!.completedAt
        precondition(model.saveCompletion(habitID:habitID,day:day,actualAmount:"散步20分钟"),"edit optional amount")
        precondition(model.data.completions.count==1 && model.data.completion(habitID:habitID,day:day)!.completedAt==completedAt,"editing amount cannot add a day or move its original time")
        model.refresh(now:clock+61,force:true)
        precondition(model.reminderPresentation(focusActive:false)==nil,"completed habit does not remind")
        model.toggleToday(habitID)
        precondition(model.todayCompletedCount==0,"card can undo")
        model.refresh(now:clock+62,force:true)
        precondition(model.reminderPresentation(focusActive:false)==nil,"undo does not replay an already-handled reminder")
        precondition(model.saveHabit(id:nil,draft:HabitDraft(name:"提醒检查",minimumAction:"读一页",anchor:"",weekdays:[1,2,3,4,5,6,7],reminderMinute:12*60+2)),"create independent reminder case")
        let reminderID=model.selectedID!
        model.refresh(now:clock+121,force:true)
        guard let item=model.reminderPresentation(focusActive:false) else { fatalError("scheduled reminder must become due") }
        precondition(model.reminderPresentation(focusActive:false,focusStateAvailable:false)==nil,"unknown focus state conservatively hides reminders")
        do {
            precondition(model.reminderPresentation(focusActive:true)==nil,"focus gates due reminder")
            model.snoozeReminder(item.id)
            precondition(model.reminderPresentation(focusActive:false)==nil,"snooze hides current reminder")
            model.refresh(now:clock+722,force:true)
            precondition(model.reminderPresentation(focusActive:true)==nil,"focus also gates elapsed snooze")
            precondition(model.reminderPresentation(focusActive:false)?.id==item.id,"elapsed snooze appears on focus end")
            model.completeFromReminder(item.id)
            precondition(model.data.completion(habitID:reminderID,day:day) != nil && model.reminderPresentation(focusActive:false)==nil,"popup completion updates calendar and cancels reminder")
            model.completeFromReminder(item.id)
            precondition(model.data.completions.count==1,"repeated popup completion is idempotent")
        }
        let restart=HabitModel(directory:dir,calendar:calendar,now:clock+750)
        precondition(restart.todayCompletedCount==1,"completion persists across model restart")
        precondition(restart.reminderPresentation(focusActive:false)==nil,"completed reminder remains quiet after relaunch")
        restart.refresh(now:clock+800,force:true)
        precondition(!restart.saveCompletion(habitID:habitID,day:"2026-10-29",actualAmount:"未来"),"future record rejected")
        precondition(restart.data.completions.count==1,"invalid completion does not alter data")
        try Data("broken habit data".utf8).write(to:dir.appendingPathComponent("habits.json"))
        let malformed=try Data(contentsOf:dir.appendingPathComponent("habits.json"))
        restart.refresh(now:clock+900,force:true)
        precondition(restart.error != nil && restart.reminderPresentation(focusActive:false)==nil,"bad canonical data stops automatic reminder")
        restart.toggleToday(habitID)
        let after=try Data(contentsOf:dir.appendingPathComponent("habits.json"))
        precondition(after==malformed,"bad file remains byte-identical after rejected edit")
        let mainDir=dir.appendingPathComponent("business")
        let business=AppModel(store:StateStore(directory:mainDir))
        let mainFile=mainDir.appendingPathComponent("state.json")
        let originalMain=try Data(contentsOf:mainFile)
        precondition(!business.stateUnavailable,"valid main-state read is known")
        try Data("invalid business state".utf8).write(to:mainFile)
        business.refresh()
        precondition(business.stateUnavailable,"main-state corruption marks focus status unknown")
        try originalMain.write(to:mainFile)
        business.refresh()
        precondition(!business.stateUnavailable,"main-state recovery restores known focus status")
        print("PASS: habit card/month linkage, amount snapshots, focus/snooze/complete flow, restart, invalid-date and corrupt-file protection")
    }
}
