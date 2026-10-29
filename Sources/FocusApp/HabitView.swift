import SwiftUI
import FocusCore

private let habitInk = Color(red: 0.17, green: 0.20, blue: 0.16)
private let habitQuiet = Color(red: 0.45, green: 0.49, blue: 0.41)
private let habitSage = Color(red: 0.38, green: 0.46, blue: 0.32)
private let habitPaper = Color(red: 0.96, green: 0.96, blue: 0.93)
private let habitLine = Color(red: 0.87, green: 0.89, blue: 0.84)
private let habitSaved = Color(red: 0.60, green: 0.69, blue: 0.51)
private let habitInactive = Color(red: 0.93, green: 0.94, blue: 0.90)
private let habitToday = Color(red: 0.50, green: 0.39, blue: 0.71)

struct HabitView: View {
    @ObservedObject var model: HabitModel
    @State private var sheet: HabitSheet?

    private var calendar: Calendar { habitGregorianCalendar(model.calendar) }
    private var selectedHabit: Habit? { model.selectedHabit ?? model.data.habits.first }
    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: model.monthDate)?.start ?? model.monthDate
    }
    private var currentMonthStart: Date {
        calendar.dateInterval(of: .month, for: Date(timeIntervalSince1970: model.now))?.start
            ?? Date(timeIntervalSince1970: model.now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(Color(red: 0.62, green: 0.35, blue: 0.24))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("habit-error")
            }
            if model.data.habits.isEmpty {
                emptyState
            } else {
                HStack(spacing: 10) {
                    Text("今天，只做这一点").font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 8)
                    Text("今日已完成 \(model.todayCompletedCount) / \(model.todayPlannedCount)")
                        .font(.system(size: 11)).foregroundStyle(habitQuiet).monospacedDigit()
                        .accessibilityIdentifier("habit-today-count")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 166), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                    ForEach(model.data.habits) { habit in habitCard(habit) }
                }
                if let habit = selectedHabit { monthlyCalendar(habit) }
            }
            Text("提醒需要应用保持运行；专注时到点，会等本轮结束。所有习惯与记录仅保存在本机。")
                .font(.system(size: 10)).foregroundStyle(habitQuiet).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(habitInk)
        .sheet(item: $sheet) { item in
            switch item {
            case .editor(let habit): HabitEditorSheet(model: model, habit: habit)
            case .record(let habitID, let day): HabitRecordSheet(model: model, habitID: habitID, day: day)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(habitDateText(Date(timeIntervalSince1970: model.now), calendar: calendar, format: "M 月 d 日，EEEE"))
                    .font(.system(size: 11)).foregroundStyle(habitQuiet)
                Text("习惯养成").font(.system(size: 26, weight: .semibold))
                Text("把行动变小，让它在生活里留下来。")
                    .font(.system(size: 12)).foregroundStyle(habitQuiet)
            }
            Spacer(minLength: 8)
            Button { sheet = .editor(nil) } label: { Label("新增习惯", systemImage: "plus") }
                .buttonStyle(HabitButtonStyle())
                .accessibilityIdentifier("habit-add")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf").font(.system(size: 30, weight: .light)).foregroundStyle(habitSage)
            Text("从一个小行动开始").font(.system(size: 16, weight: .medium))
            Text("名称、最小行动与提醒时间，都由你决定。")
                .font(.system(size: 12)).foregroundStyle(habitQuiet)
            Button("添加第一个习惯") { sheet = .editor(nil) }
                .buttonStyle(HabitButtonStyle(primary: true)).padding(.top, 3)
                .accessibilityIdentifier("habit-empty-add")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    }

    private func habitCard(_ habit: Habit) -> some View {
        let rule = habit.rule(on: model.today)
        let completion = model.data.completion(habitID: habit.id, day: model.today)
        let paused = rule?.paused ?? false
        let selected = selectedHabit?.id == habit.id
        let planned = habitIsPlanned(habit, on: model.today, calendar: calendar)
        let status = completion.flatMap { $0.actualAmount.isEmpty ? nil : $0.actualAmount }
            ?? (paused ? "已暂停" : selected ? "查看中" : !planned ? "未安排" : "")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Button { model.select(habit.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf")
                            .font(.system(size: 12)).foregroundStyle(habitSage)
                            .frame(width: 22, height: 24)
                            .background(habitSage.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                        Text(habit.name).font(.system(size: 14, weight: .semibold))
                            .multilineTextAlignment(.leading).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("查看\(habit.name)的月历")
                .accessibilityLabel("查看\(habit.name)的月历")
                .accessibilityValue(selected ? "正在查看" : "")
                .accessibilityIdentifier("habit-select-\(habit.id)")
                Button("编辑") { sheet = .editor(habit) }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(habitQuiet).fixedSize()
                    .accessibilityLabel("编辑\(habit.name)")
                    .accessibilityIdentifier("habit-edit-\(habit.id)")
            }.frame(height: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("最低行动").font(.system(size: 10)).foregroundStyle(habitQuiet)
                Text(rule?.minimumAction ?? "")
                    .font(.system(size: 14, weight: .medium)).lineLimit(2)
                    .help(rule?.minimumAction ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let anchor = rule?.anchor, !anchor.isEmpty {
                    Text(anchor).font(.system(size: 10)).foregroundStyle(habitQuiet)
                        .lineLimit(1).help(anchor)
                }
            }.frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            Label(reminderSummary(rule), systemImage: paused ? "pause.circle" : "bell")
                .font(.system(size: 10)).foregroundStyle(habitQuiet).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .topLeading)
                .help(reminderSummary(rule))
            Button {
                if paused { model.setPaused(id: habit.id, paused: false) }
                else { model.toggleToday(habit.id) }
            } label: {
                Label(paused ? "恢复习惯" : "今日已做到", systemImage: paused ? "play" : completion == nil ? "circle" : "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HabitButtonStyle(primary: !paused && completion != nil))
            .help(paused ? "恢复执行与提醒，已有记录保留" : completion == nil ? "一键完成，今天的月历会立即填色" : "再次点击可撤销今天的记录")
            .accessibilityLabel(paused ? "恢复\(habit.name)" : "\(habit.name)，今日已做到")
            .accessibilityValue(completion == nil ? "未完成" : "已完成，再次点击撤销")
            .accessibilityIdentifier("habit-toggle-\(habit.id)")
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(status).font(.system(size: 10)).foregroundStyle(selected || completion != nil ? habitSage : habitQuiet)
                    .lineLimit(1).help(status)
                Spacer(minLength: 0)
                Button(completion == nil ? "记录实际量" : "补充 / 修改") {
                    sheet = .record(habit.id, model.today)
                }
                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(habitSage).fixedSize()
                .disabled(paused)
                .accessibilityLabel("\(habit.name)，\(completion == nil ? "记录今天的实际量" : "修改今天的记录")")
                .accessibilityIdentifier("habit-record-today-\(habit.id)")
            }.frame(height: 14)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(paused ? habitInactive.opacity(0.7) : completion == nil ? .white.opacity(0.78) : habitSage.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? habitSage.opacity(0.52) : habitLine.opacity(0.7), lineWidth: selected ? 1.25 : 1))
        .accessibilityIdentifier("habit-card-\(habit.id)")
    }

    private func monthlyCalendar(_ habit: Habit) -> some View {
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
        let offset = (calendar.component(.weekday, from: monthStart) + 5) % 7
        let prefix = String(HabitDates.day(at: monthStart.timeIntervalSince1970, calendar: calendar).prefix(7))
        let completed = model.data.completions.filter { $0.habitID == habit.id && $0.day.hasPrefix(prefix) && $0.day <= model.today }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(habit.name) · 当月完成情况")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1).help("\(habit.name) · 当月完成情况")
                    Text("本月已完成 \(completed) 天").font(.system(size: 11)).foregroundStyle(habitQuiet)
                        .accessibilityIdentifier("habit-month-count")
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 20, height: 24) }
                        .accessibilityLabel("上一个月").accessibilityIdentifier("habit-month-prev")
                    Text(habitDateText(monthStart, calendar: calendar, format: "yyyy 年 M 月"))
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .accessibilityIdentifier("habit-month-title")
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 20, height: 24) }
                        .disabled(monthStart >= currentMonthStart)
                        .accessibilityLabel("下一个月").accessibilityIdentifier("habit-month-next")
                    Button("本月") { model.monthDate = Date(timeIntervalSince1970: model.now) }
                        .font(.system(size: 10)).padding(.leading, 3).help("回到本月")
                        .accessibilityLabel("回到本月").accessibilityIdentifier("habit-month-current")
                }.buttonStyle(.borderless).foregroundStyle(habitSage).fixedSize()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                    Text(weekday).font(.system(size: 10)).foregroundStyle(habitQuiet)
                        .frame(maxWidth: .infinity).padding(.bottom, 3).accessibilityHidden(true)
                }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 35).accessibilityHidden(true) }
                ForEach(0..<dayCount, id: \.self) { index in
                    if let date = calendar.date(byAdding: .day, value: index, to: monthStart) { calendarDay(date, habit: habit) }
                }
            }
            HStack(spacing: 12) {
                legend("已完成", fill: habitSaved)
                legend("未完成", fill: .white)
                legend("未安排", fill: .clear, dash: true)
                legend("未来", fill: habitInactive)
                legend("今天", fill: .clear, today: true)
                Spacer(minLength: 0)
            }
            Text("点击日期可补记、修改或撤销；点击「今日已做到」，今天会立即填色。")
                .font(.system(size: 10)).foregroundStyle(habitQuiet).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.white.opacity(0.40), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(habitLine.opacity(0.7)))
    }

    private func calendarDay(_ date: Date, habit: Habit) -> some View {
        let day = HabitDates.day(at: date.timeIntervalSince1970, calendar: calendar)
        let done = model.data.completion(habitID: habit.id, day: day) != nil
        let future = day > model.today
        let beforeCreation = day < HabitDates.day(at: habit.createdAt, calendar: calendar)
        let planned = habitIsPlanned(habit, on: day, calendar: calendar)
        let today = day == model.today
        let status = done ? "已完成" : future ? "未来日期" : beforeCreation ? "尚未开始" : planned ? "未完成" : "未安排，可自愿记录"
        let label = "\(habit.name)，\(habitDateText(date, calendar: calendar, format: "yyyy 年 M 月 d 日，EEEE"))，\(status)"
        return Button { sheet = .record(habit.id, day) } label: {
            HStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: done ? .medium : .regular, design: .rounded)).monospacedDigit()
                if done { Image(systemName: "checkmark").font(.system(size: 8, weight: .semibold)) }
                else if !planned && !future && !beforeCreation { Text("–").font(.system(size: 10)) }
            }
            .frame(maxWidth: .infinity).frame(height: 35)
            .foregroundStyle(done ? habitInk : future || beforeCreation ? habitQuiet.opacity(0.50) : planned ? habitInk : habitQuiet.opacity(0.78))
            .background(done ? habitSaved : future ? habitInactive : beforeCreation ? .white.opacity(0.16) : planned ? .white.opacity(0.90) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(today ? habitToday : planned && !future && !beforeCreation && !done ? habitLine : .clear, lineWidth: today ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).disabled(future || beforeCreation)
        .help(label).accessibilityLabel(label).accessibilityIdentifier("habit-day-\(day)")
    }

    private func legend(_ title: String, fill: Color, dash: Bool = false, today: Bool = false) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 10, height: 10)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(today ? habitToday : dash ? .clear : habitLine, lineWidth: 1))
                .overlay { if dash { Text("–").font(.system(size: 10)) } }
            Text(title)
        }.font(.system(size: 10)).foregroundStyle(habitQuiet)
    }

    private func shiftMonth(_ amount: Int) {
        if let date = calendar.date(byAdding: .month, value: amount, to: monthStart) { model.monthDate = date }
    }

    private func reminderSummary(_ rule: HabitRule?) -> String {
        guard let rule else { return "未开启提醒" }
        if rule.paused { return "提醒已暂停" }
        let frequency = habitFrequencyText(rule.weekdays)
        if let minute = rule.reminderMinute {
            return String(format: "%@ · %02d:%02d 提醒", frequency, minute / 60, minute % 60)
        }
        return "\(frequency) · 未开启提醒"
    }
}

private enum HabitSheet: Identifiable {
    case editor(Habit?)
    case record(String, String)
    var id: String {
        switch self {
        case .editor(let habit): return "editor-" + (habit?.id ?? "new")
        case .record(let habitID, let day): return "record-\(habitID)-\(day)"
        }
    }
}

private enum HabitFrequency: String, CaseIterable {
    case daily = "每天", workdays = "工作日（周一至周五）", custom = "自选星期"
}

private struct HabitEditorSheet: View {
    @ObservedObject var model: HabitModel
    let habit: Habit?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var minimum: String
    @State private var anchor: String
    @State private var frequency: HabitFrequency
    @State private var customWeekdays: Set<Int>
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var errorText: String?
    @SwiftUI.FocusState private var field: Field?

    private enum Field: Hashable { case name, minimum, anchor }
    private let paused: Bool
    private var calendar: Calendar { habitGregorianCalendar(model.calendar) }
    private var weekdays: [Int] {
        switch frequency {
        case .daily: return Array(1...7)
        case .workdays: return Array(1...5)
        case .custom: return customWeekdays.sorted()
        }
    }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 60
            && !minimum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && minimum.count <= 180
            && anchor.count <= 180 && !weekdays.isEmpty
    }

    init(model: HabitModel, habit: Habit?) {
        self.model = model
        self.habit = habit
        let rule = habit?.rule(on: model.today) ?? habit?.rules.sorted { $0.effectiveDay < $1.effectiveDay }.last
        let days = rule?.weekdays.sorted() ?? Array(1...7)
        let minute = rule?.reminderMinute ?? 8 * 60
        let calendar = habitGregorianCalendar(model.calendar)
        _name = State(initialValue: habit?.name ?? "")
        _minimum = State(initialValue: rule?.minimumAction ?? "")
        _anchor = State(initialValue: rule?.anchor ?? "")
        _frequency = State(initialValue: days == Array(1...7) ? .daily : days == Array(1...5) ? .workdays : .custom)
        _customWeekdays = State(initialValue: Set(days))
        _reminderEnabled = State(initialValue: rule?.reminderMinute != nil)
        _reminderTime = State(initialValue: calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date(timeIntervalSince1970: model.now)) ?? Date(timeIntervalSince1970: model.now))
        paused = rule?.paused ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(habit == nil ? "新增习惯" : "编辑习惯").font(.system(size: 23, weight: .semibold))
            editorField("习惯名称", hint: "你想持续做的一件事", text: $name, limit: 60, focus: .name)
            editorField("最小行动", hint: "忙的时候，也愿意做到的一小步", text: $minimum, limit: 180, focus: .minimum)
            editorField("行动时机（可选）", hint: "例如：午饭后、洗漱后", text: $anchor, limit: 180, focus: .anchor)
            VStack(alignment: .leading, spacing: 8) {
                Text("执行频率").font(.system(size: 12, weight: .medium))
                Picker("执行频率", selection: $frequency) {
                    ForEach(HabitFrequency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("habit-editor-frequency")
                if frequency == .custom {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { weekday in
                            Button {
                                if customWeekdays.contains(weekday) { customWeekdays.remove(weekday) }
                                else { customWeekdays.insert(weekday) }
                            } label: {
                                Text("周\(habitWeekdayNames[weekday - 1])")
                                    .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .foregroundStyle(customWeekdays.contains(weekday) ? .white : habitQuiet)
                                    .background(customWeekdays.contains(weekday) ? habitSage : .white.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("每周\(habitWeekdayNames[weekday - 1])执行")
                            .accessibilityValue(customWeekdays.contains(weekday) ? "已选择" : "未选择")
                            .accessibilityIdentifier("habit-editor-weekday-\(weekday)")
                        }
                    }
                    if customWeekdays.isEmpty {
                        Text("至少选择一个执行日。").font(.system(size: 10)).foregroundStyle(habitQuiet)
                    }
                }
            }
            HStack(spacing: 12) {
                Toggle("开启右上角提醒", isOn: $reminderEnabled).toggleStyle(.checkbox)
                    .font(.system(size: 12)).accessibilityIdentifier("habit-editor-reminder-enabled")
                Spacer(minLength: 12)
                DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .labelsHidden().datePickerStyle(.field).fixedSize().disabled(!reminderEnabled)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .accessibilityLabel("提醒时间").accessibilityIdentifier("habit-editor-reminder-time")
            }
            Text(habit == nil ? "专注中到点，会等本轮番茄钟结束后提醒。" : "修改从今天生效，过去记录保留。专注中到点，会等本轮结束后提醒。")
                .font(.system(size: 11)).foregroundStyle(habitQuiet).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let errorText { habitFormError(errorText) }
            HStack(spacing: 10) {
                if habit != nil {
                    Button(paused ? "恢复习惯" : "暂停此习惯") { setPaused(!paused) }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(habitQuiet)
                        .accessibilityIdentifier("habit-editor-pause")
                }
                Spacer(minLength: 8)
                Button("取消") { dismiss() }.buttonStyle(HabitButtonStyle()).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("habit-editor-cancel")
                Button(habit == nil ? "添加习惯" : "保存修改") { save() }
                    .buttonStyle(HabitButtonStyle(primary: true)).disabled(!valid).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("habit-editor-save")
            }.padding(.top, 3)
        }
        .padding(26).frame(width: 480).background(habitPaper).foregroundStyle(habitInk)
        .onAppear { field = .name }
    }

    private func editorField(_ title: String, hint: String, text: Binding<String>, limit: Int, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                if text.wrappedValue.count > limit {
                    Text("最多 \(limit) 字").font(.system(size: 10)).foregroundStyle(Color(red: 0.62, green: 0.35, blue: 0.24))
                }
            }
            TextField(hint, text: text).textFieldStyle(.roundedBorder).font(.system(size: 14))
                .focused($field, equals: focus).onSubmit { submit() }
                .accessibilityLabel(title)
                .accessibilityIdentifier("habit-editor-\(focus == .name ? "name" : focus == .minimum ? "minimum" : "anchor")")
        }
    }

    private func submit() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { field = .name }
        else if minimum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { field = .minimum }
        else if valid { save() }
    }

    private func save() {
        guard valid else { return }
        let time = calendar.dateComponents([.hour, .minute], from: reminderTime)
        let minute = (time.hour ?? 8) * 60 + (time.minute ?? 0)
        let draft = HabitDraft(name: name, minimumAction: minimum, anchor: anchor, weekdays: weekdays,
                               reminderMinute: reminderEnabled ? minute : nil, paused: paused)
        if model.saveHabit(id: habit?.id, draft: draft) { dismiss() }
        else { errorText = model.error ?? "没有保存成功，请再试一次。" }
    }

    private func setPaused(_ value: Bool) {
        guard let habit else { return }
        model.setPaused(id: habit.id, paused: value)
        if model.data.habits.first(where: { $0.id == habit.id })?.rule(on: model.today)?.paused == value { dismiss() }
        else { errorText = model.error ?? "没有保存成功，请再试一次。" }
    }
}

private struct HabitRecordSheet: View {
    @ObservedObject var model: HabitModel
    let habitID: String
    let day: String
    @Environment(\.dismiss) private var dismiss
    @State private var actualAmount: String
    @State private var errorText: String?
    @SwiftUI.FocusState private var amountFocused: Bool

    private var habit: Habit? { model.data.habits.first { $0.id == habitID } }
    private var completion: HabitCompletion? { model.data.completion(habitID: habitID, day: day) }
    private var calendar: Calendar { habitGregorianCalendar(model.calendar) }

    init(model: HabitModel, habitID: String, day: String) {
        self.model = model
        self.habitID = habitID
        self.day = day
        _actualAmount = State(initialValue: model.data.completion(habitID: habitID, day: day)?.actualAmount ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 6) {
                Text(completion?.name ?? habit?.name ?? "习惯记录")
                    .font(.system(size: 22, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                if let date = HabitDates.date(for: day, calendar: calendar) {
                    Text(habitDateText(date, calendar: calendar, format: "yyyy 年 M 月 d 日，EEEE"))
                        .font(.system(size: 12)).foregroundStyle(habitQuiet)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Label(completion == nil ? "未完成" : "已完成", systemImage: completion == nil ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(habitSage)
                Text("当天最低行动：\(completion?.minimumAction ?? habit?.rule(on: day)?.minimumAction ?? "")")
                    .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                Text(habit.map { habitIsPlanned($0, on: day, calendar: calendar) } == true ? "当天计划内的行动" : "当天未安排，也可以自愿记录。")
                    .font(.system(size: 11)).foregroundStyle(habitQuiet)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(habitSage.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("实际做了多少（可选）").font(.system(size: 12, weight: .medium))
                    Spacer()
                    if actualAmount.count > 2_000 {
                        Text("最多 2000 字").font(.system(size: 10)).foregroundStyle(Color(red: 0.62, green: 0.35, blue: 0.24))
                    }
                }
                TextField("例如：散步 20 分钟、读了 6 页", text: $actualAmount)
                    .textFieldStyle(.roundedBorder).font(.system(size: 14)).focused($amountFocused)
                    .onSubmit { save() }.accessibilityLabel("实际做了多少，可选")
                    .accessibilityIdentifier("habit-record-amount")
                Text("留空也可以，保存后这一天会填色。")
                    .font(.system(size: 11)).foregroundStyle(habitQuiet)
            }
            if let errorText { habitFormError(errorText) }
            HStack(spacing: 10) {
                if completion != nil {
                    Button("撤销这次记录") { undo() }.buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(habitQuiet)
                        .accessibilityIdentifier("habit-record-undo")
                }
                Spacer(minLength: 8)
                Button("取消") { dismiss() }.buttonStyle(HabitButtonStyle()).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("habit-record-cancel")
                Button(completion == nil ? "记为已完成" : "保存记录") { save() }
                    .buttonStyle(HabitButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
                    .disabled(actualAmount.count > 2_000 || habit == nil)
                    .accessibilityIdentifier("habit-record-save")
            }
        }
        .padding(26).frame(width: 480).background(habitPaper).foregroundStyle(habitInk)
        .onAppear { amountFocused = true }
    }

    private func save() {
        guard actualAmount.count <= 2_000, habit != nil else { return }
        if model.saveCompletion(habitID: habitID, day: day, actualAmount: actualAmount) { dismiss() }
        else { errorText = model.error ?? "没有保存成功，请再试一次。" }
    }

    private func undo() {
        model.removeCompletion(habitID: habitID, day: day)
        if model.data.completion(habitID: habitID, day: day) == nil { dismiss() }
        else { errorText = model.error ?? "没有撤销成功，请再试一次。" }
    }
}

private struct HabitButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(primary ? .white : habitInk)
            .background(primary ? habitSage : habitSage.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.70 : 1)
    }
}

private let habitWeekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

private func habitGregorianCalendar(_ calendar: Calendar) -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = calendar.timeZone
    value.locale = Locale(identifier: "zh_CN")
    value.firstWeekday = 2
    return value
}

private func habitDateText(_ date: Date, calendar: Calendar, format: String) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = format
    return formatter.string(from: date)
}

private func habitIsPlanned(_ habit: Habit, on day: String, calendar: Calendar) -> Bool {
    guard day >= HabitDates.day(at: habit.createdAt, calendar: calendar),
          let rule = habit.rule(on: day), !rule.paused,
          let weekday = HabitDates.weekday(for: day, calendar: calendar) else { return false }
    return rule.weekdays.contains(weekday)
}

private func habitFrequencyText(_ weekdays: [Int]) -> String {
    let days = weekdays.sorted()
    if days == Array(1...7) { return "每天" }
    if days == Array(1...5) { return "周一至周五" }
    return days.compactMap { (1...7).contains($0) ? "周\(habitWeekdayNames[$0 - 1])" : nil }.joined(separator: "、")
}

private func habitFormError(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.circle")
        .font(.system(size: 11)).foregroundStyle(Color(red: 0.62, green: 0.35, blue: 0.24))
        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("habit-form-error")
}
