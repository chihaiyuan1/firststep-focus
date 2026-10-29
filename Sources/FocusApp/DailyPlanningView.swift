import SwiftUI
import FocusCore

private let planSage = Color(red: 0.38, green: 0.46, blue: 0.32)
private let planPaper = Color(red: 0.96, green: 0.96, blue: 0.93)

struct DailyPlanningView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var scheduling: PlanningCandidate?
    private var day: String { FocusCore.FocusState.day(at: model.now) }
    private var candidates: [PlanningCandidate] { model.state.planningCandidates(day: day) }
    private var later: [PlanningCandidate] {
        model.state.tasks.filter { !$0.completed && ($0.scheduledDay ?? "") > day }.map {
            PlanningCandidate(id: $0.id, title: $0.title, isInbox: false, scheduledDay: $0.scheduledDay)
        } + model.state.activeInboxItems.filter { ($0.scheduledDay ?? "") > day }.map {
            PlanningCandidate(id: $0.id, title: $0.title, isInbox: true, scheduledDay: $0.scheduledDay)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text("安排今天").font(.system(size: 22, weight: .semibold)); Text("挑选今天想推进的事，通常 1–3 件就好。").font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Button("完成") { dismiss() }.buttonStyle(SoftButton(primary: true)) }
            Text("今天已有 \(model.todayTasks.count) 件未完成任务").font(.system(size: 12)).foregroundStyle(planSage)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if candidates.isEmpty { Text("暂时没有需要挑选的事。你也可以稍后再来。") .foregroundStyle(.secondary).padding(.vertical, 25) }
                    ForEach(candidates) { candidate in row(candidate) }
                    if !later.isEmpty {
                        Text("已安排到以后").font(.system(size: 13, weight: .semibold)).padding(.top, 12)
                        ForEach(later) { candidate in row(candidate) }
                    }
                }
            }.frame(minHeight: 230, maxHeight: 430)
            Text("加入今天只会选中任务，不会自动开始番茄钟。未选择的事情仍会保留。") .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 590).background(planPaper)
        .sheet(item: $scheduling) { item in
            let inbox = model.state.activeInboxItems.first { $0.id == item.id }
            let task = model.state.tasks.first { $0.id == item.id }
            ScheduleEditor(model: model, id: item.id, title: item.title, isInbox: item.isInbox, day: item.scheduledDay, reminderAt: inbox?.reminderAt ?? task?.reminderAt)
        }
    }
    private func row(_ item: PlanningCandidate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 13, weight: .medium))
                Text(item.scheduledDay.map { "计划：\($0)" } ?? (item.isInbox ? "收集箱" : "之前未完成"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("安排日期") { scheduling = item }.buttonStyle(SoftButton())
            Button("加入今天") {
                if item.isInbox { _ = model.moveInboxToToday(item.id) }
                else if model.send(Command("moveToday", taskID: item.id)) { model.selectTask(item.id) }
            }.buttonStyle(SoftButton(primary: true)).disabled(model.state.session?.taskID == item.id)
        }.padding(12).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ScheduleEditor: View {
    @ObservedObject var model: AppModel
    let id: String
    let title: String
    let isInbox: Bool
    let day: String?
    let reminderAt: Double?
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var useReminder = false
    @State private var reminderTime = Date()
    @State private var previousDate = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("安排日期").font(.system(size: 22, weight: .semibold))
            Text(title).font(.system(size: 14)).lineLimit(2)
            DatePicker("计划日期", selection: $date, displayedComponents: .date)
            Toggle("在指定时间提醒我", isOn: $useReminder)
            if useReminder { DatePicker("提醒日期与时间", selection: $reminderTime, displayedComponents: [.date, .hourAndMinute]) }
            Text("计划日期可以调整；提醒需要应用保持运行，专注期间会等这一轮结束。") .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack { if day != nil { Button("清除安排") { save(clear: true) }.buttonStyle(.plain) }; Spacer(); Button("取消") { dismiss() }.buttonStyle(SoftButton()); Button("保存") { save(clear: false) }.buttonStyle(SoftButton(primary: true)).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 430).background(planPaper)
        .onAppear {
            date = day.flatMap { TimeGrid.date(for: $0) } ?? Date(); previousDate = date
            if let reminderAt { useReminder = true; reminderTime = Date(timeIntervalSince1970: reminderAt) }
            else { moveReminder(to: date) }
        }
        .onChange(of: date) { newDate in
            reminderTime = ScheduleTimes.reminderWhenMovingPlan(reminderTime, from:previousDate, to:newDate)
            previousDate = newDate
        }
    }
    private func moveReminder(to day: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        reminderTime = Calendar.current.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: day) ?? day
    }
    private func save(clear: Bool) {
        let key = clear ? nil : TimeGrid.dayKey(date)
        let timestamp = !clear && useReminder ? reminderTime.timeIntervalSince1970 : nil
        if model.send(Command(isInbox ? "scheduleInbox" : "scheduleTask", taskID: id, scheduledDay: key, reminderAt: timestamp)) { dismiss() }
    }
}
