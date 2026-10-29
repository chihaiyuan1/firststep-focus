import SwiftUI
import FocusCore

private let completionSage = Color(red: 0.38, green: 0.46, blue: 0.32)
private let completionQuiet = Color(red: 0.50, green: 0.53, blue: 0.47)

private enum CompletionKind: String, CaseIterable {
    case tasks = "完成任务", steps = "完成小任务", unknown = "日期未知"
}

struct CompletionRecordsView: View {
    @ObservedObject var model: AppModel
    @State private var date = Date()
    @State private var scope: FocusStatisticsScope = .week
    @State private var kind: CompletionKind = .tasks
    @State private var search = ""
    private var calendar: Calendar { .current }
    private var interval: DateInterval { scope.interval(containing: date) }
    private var allRecords: [TaskCompletionRecord] { model.state.completionHistory }
    private var records: [TaskCompletionRecord] {
        allRecords.filter { record in
            let matchesKind: Bool
            if kind == .unknown { matchesKind = record.completedAt == nil }
            else if let timestamp = record.completedAt {
                matchesKind = (record.subtaskID == nil) == (kind == .tasks)
                    && timestamp >= interval.start.timeIntervalSince1970
                    && timestamp < interval.end.timeIntervalSince1970
            } else { matchesKind = false }
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            return matchesKind && (query.isEmpty || (record.title + " " + (record.parentTitle ?? "")).localizedCaseInsensitiveContains(query))
        }.sorted { ($0.completedAt ?? 0) > ($1.completedAt ?? 0) }
    }
    private var groupedDays: [Date] {
        Array(Set(records.compactMap { $0.completedAt.map { calendar.startOfDay(for: Date(timeIntervalSince1970: $0)) } })).sorted(by: >)
    }
    private var totals: TaskFocusProgress { model.state.completionProgress(for: records) }
    private var datedKindRecords: [TaskCompletionRecord] {
        allRecords.filter { $0.completedAt != nil && ($0.subtaskID == nil) == (kind != .steps) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("专注记录 / 完成记录").font(.system(size: 11)).foregroundStyle(completionQuiet)
                Text("完成记录").font(.system(size: 26, weight: .semibold))
                Text("看看完成了什么，也看看为它投入了多少时间。")
                    .font(.system(size: 12)).foregroundStyle(completionQuiet)
            }
            periodHeader
            if kind != .unknown {
                HStack(spacing: 10) {
                    metric(kind == .steps ? "本期完成小任务" : "本期完成任务", value: "\(records.count) 次")
                    metric("这些任务累计专注", value: taskDuration(totals.focusSeconds))
                    metric("这些任务累计番茄钟", value: "\(totals.completedPomodoros) 个")
                }
                calendarStrip
            }
            HStack(spacing: 10) {
                Picker("完成记录类型", selection: $kind) {
                    ForEach(CompletionKind.allCases, id: \.self) { item in
                        Text(item == .unknown ? "日期未知 \(allRecords.filter { $0.completedAt == nil }.count)" : item.rawValue).tag(item)
                    }
                }.pickerStyle(.segmented).labelsHidden()
                .accessibilityIdentifier("completion-kind")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(completionQuiet)
                TextField("搜索完成的事", text: $search).textFieldStyle(.plain)
                    .accessibilityIdentifier("completion-search")
            }.font(.system(size: 12)).padding(11)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
            if kind == .unknown {
                Label("旧版未保存准确完成日期，单独保留，不计入所选周期。", systemImage: "questionmark.circle")
                    .font(.system(size: 11)).foregroundStyle(completionQuiet)
                ForEach(records) { record in completionCard(record) }
            } else {
                ForEach(groupedDays, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(day, format: .dateTime.month().day().weekday(.wide)).font(.system(size: 12, weight: .semibold))
                        ForEach(records.filter { record in
                            record.completedAt.map { calendar.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: day) } == true
                        }) { record in completionCard(record) }
                    }
                }
            }
            if records.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "leaf").font(.system(size: 26)).foregroundStyle(completionSage.opacity(0.7))
                    Text(search.isEmpty ? (kind == .unknown ? "没有日期未知的完成记录" : "这一段时间还没有完成记录") : "没有找到匹配的完成记录")
                        .font(.system(size: 13))
                    Text("手动完成任务后，会留在这里，方便以后回看。")
                        .font(.system(size: 11)).foregroundStyle(completionQuiet)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
                    .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
            }
            Text("按完成日期筛选，每项显示完成前的全部投入，包含此前日期的番茄钟。\n主任务包含小任务的投入，两类分开展示；同一轮在页面合计中只计算一次。\n修改、删除或恢复任务不会抹去完成记录；再次完成会保留一条新的记录。")
                .font(.system(size: 10)).foregroundStyle(completionQuiet).lineSpacing(4)
        }
    }

    private var periodHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(periodTitle).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 10)
                Picker("完成日期范围", selection: $scope) {
                    ForEach(FocusStatisticsScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(width: 135).labelsHidden()
                    .accessibilityIdentifier("completion-scope")
            }
            HStack(spacing: 10) {
                Button { date = scope.shiftedDate(from: date, by: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("上一周期")
                Button(scope == .day ? "今天" : scope == .week ? "本周" : "本月") { date = Date(timeIntervalSince1970: model.now) }
                    .font(.system(size: 11))
                Button { date = scope.shiftedDate(from: date, by: 1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("下一周期")
                Spacer()
                DatePicker("完成日期", selection: $date, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field).font(.system(size: 11)).fixedSize()
                    .accessibilityLabel("选择完成日期")
            }.buttonStyle(.borderless)
        }
    }

    private var periodTitle: String {
        switch scope {
        case .day: return date.formatted(.dateTime.year().month().day().weekday(.wide))
        case .month: return interval.start.formatted(.dateTime.year().month(.wide))
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
            return interval.start.formatted(.dateTime.year().month().day()) + " — " + last.formatted(.dateTime.month().day())
        }
    }

    @ViewBuilder private var calendarStrip: some View {
        if scope == .month {
            let month = FocusStatisticsScope.month.interval(containing: date)
            let count = calendar.dateComponents([.day], from: month.start, to: month.end).day ?? 0
            let offset = (calendar.component(.weekday, from: month.start) + 5) % 7
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(completionQuiet) }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 43) }
                ForEach(0..<count, id: \.self) { index in
                    if let day = calendar.date(byAdding: .day, value: index, to: month.start) { dayButton(day, compact: true) }
                }
            }
        } else {
            let week = FocusStatisticsScope.week.interval(containing: date)
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { index in
                    if let day = calendar.date(byAdding: .day, value: index, to: week.start) { dayButton(day) }
                }
            }
        }
    }

    private func dayButton(_ day: Date, compact: Bool = false) -> some View {
        let count = datedKindRecords.filter { $0.completedAt.map { calendar.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: day) } == true }.count
        let selected = scope == .day && calendar.isDate(date, inSameDayAs: day)
        let today = calendar.isDate(day, inSameDayAs: Date(timeIntervalSince1970: model.now))
        return Button { date = day; scope = .day } label: {
            VStack(spacing: compact ? 2 : 4) {
                if !compact { Text(day, format: .dateTime.weekday(.abbreviated)).font(.system(size: 10)) }
                Text("\(calendar.component(.day, from: day))").font(.system(size: compact ? 11 : 15, weight: .medium, design: .rounded))
                Text(count > 0 ? "\(count) 个完成" : " ").font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity).padding(.vertical, compact ? 5 : 8)
                .foregroundStyle(selected ? .white : today ? completionSage : completionQuiet)
                .background(selected ? completionSage : count > 0 || today ? completionSage.opacity(0.09) : .white.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(today ? completionSage.opacity(0.4) : completionSage.opacity(0.1)))
        }.buttonStyle(.plain)
            .accessibilityLabel("查看 \(day.formatted(.dateTime.year().month().day()))，\(count) 个完成")
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 10)).foregroundStyle(completionQuiet)
            Text(value).font(.system(size: 22, weight: .regular, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(completionSage)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    private func completionCard(_ record: TaskCompletionRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(completionSage)
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.title).font(.system(size: 14, weight: .medium))
                    if let parent = record.parentTitle { Text("主任务：\(parent)").font(.system(size: 11)).foregroundStyle(completionQuiet) }
                }
                Spacer(minLength: 8)
                if let timestamp = record.completedAt { Text(Date(timeIntervalSince1970: timestamp), format: .dateTime.hour().minute()).font(.system(size: 10)).foregroundStyle(completionQuiet) }
                else { Text("日期未知").font(.system(size: 10)).foregroundStyle(completionQuiet) }
                if let current = model.state.tasks.first(where: { $0.id == record.taskID }) {
                    Menu {
                        Button(current.completed ? "恢复到今天继续" : "回到当前任务") {
                            if !current.completed || model.send(Command("moveToday", taskID: current.id)) {
                                model.page = "today"; model.selectTask(current.id, subtaskID: record.subtaskID)
                            }
                        }.disabled(model.state.session?.taskID == current.id)
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: 20)
                        .accessibilityLabel("完成任务操作：\(record.title)")
                }
            }
            HStack(spacing: 18) {
                Text("完成番茄钟 **\(record.completedPomodoros)** 个")
                Text("累计专注 **\(taskDuration(record.focusSeconds))**")
            }.font(.system(size: 11)).foregroundStyle(completionSage)
            PomodoroProgressView(completed: record.completedPomodoros, estimated: record.estimatedPomodoros, isCompleted: true)
            DisclosureGroup("查看投入明细") {
                VStack(alignment: .leading, spacing: 6) {
                    if let timestamp = record.completedAt {
                        Text("完成于 \(Date(timeIntervalSince1970: timestamp).formatted(.dateTime.year().month().day().hour().minute())) · 完成前累计投入")
                    } else { Text("未保存准确完成日期；以下为旧记录迁入时关联的投入。") }
                    let ids = Set(record.focusRecordIDs)
                    let linked = model.state.history.filter { ids.contains($0.id) }.sorted { $0.endAt < $1.endAt }
                    if linked.isEmpty { Text("未关联番茄钟，也可以手动完成任务。") }
                    ForEach(linked) { session in
                        Text("\(Date(timeIntervalSince1970: session.endAt).formatted(.dateTime.month().day().hour().minute())) · \(taskDuration(session.focusSeconds)) · \(session.finished ? "完整完成一轮" : "提前结束，不计完整番茄")")
                    }
                    if record.subtaskID == nil { Text("已包含小任务的投入，同一轮只计算一次。") }
                }.font(.system(size: 10)).foregroundStyle(completionQuiet).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(completionSage.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }.font(.system(size: 10)).tint(completionQuiet)
        }.padding(16).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("completion-record-\(record.id)")
    }
}

private func taskDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0 分钟" }
    if seconds < 60 { return "不足 1 分钟" }
    let minutes = Int(min(seconds / 60, Double(Int.max / 2)))
    let hours = minutes / 60, remainder = minutes % 60
    if hours == 0 { return "\(minutes) 分钟" }
    return remainder == 0 ? "\(hours) 小时" : "\(hours) 小时 \(remainder) 分钟"
}
