import SwiftUI
import AppKit
import FocusCore

private let logInk = Color(red: 0.17, green: 0.20, blue: 0.16)
private let logQuiet = Color(red: 0.50, green: 0.53, blue: 0.47)
private let logAccent = Color(red: 0.46, green: 0.36, blue: 0.70)
private let logPaper = Color(red: 0.96, green: 0.96, blue: 0.93)
private func logPalette(_ key: String) -> (Color, Color, String) {
    switch key {
    case "sky": return (Color(red: 0.86, green: 0.94, blue: 1), Color(red: 0.25, green: 0.57, blue: 0.79), "晴空蓝")
    case "mint": return (Color(red: 0.86, green: 0.96, blue: 0.89), Color(red: 0.28, green: 0.62, blue: 0.42), "薄荷绿")
    case "rose": return (Color(red: 1, green: 0.88, blue: 0.91), Color(red: 0.81, green: 0.40, blue: 0.51), "珊瑚粉")
    case "amber": return (Color(red: 1, green: 0.95, blue: 0.78), Color(red: 0.72, green: 0.56, blue: 0.19), "暖阳黄")
    default: return (Color(red: 0.92, green: 0.88, blue: 1), Color(red: 0.57, green: 0.41, blue: 0.81), "鸢尾紫")
    }
}
private func minuteText(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
private struct TimeDraft: Identifiable {
    var id = UUID().uuidString
    var existing: TimeEntry?
    var date: Date
    var start: Int
    var end: Int
}
private struct GridSelection { var day: String; var start: Int; var end: Int }

struct TimeLogView: View {
    @ObservedObject var model: AppModel
    @State private var draft: TimeDraft?
    @State private var selection: GridSelection?
    @State private var dragPreview: TimeEntry?
    private let hourHeight: CGFloat = 64
    private let axisWidth: CGFloat = 46
    private var days: [Date] { model.logScope == "week" ? TimeGrid.week(containing: model.selectedLogDate) : [Calendar.current.startOfDay(for: model.selectedLogDate)] }
    private var shownEntries: [TimeEntry] { model.timeEntries.filter { $0.deletedAt == nil } }
    private var rangeTitle: String {
        guard let first = days.first, let last = days.last else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy 年 M 月 d 日"
        if model.logScope == "day" { return f.string(from: first) }
        let firstText = f.string(from: first)
        if Calendar.current.component(.year, from: first) == Calendar.current.component(.year, from: last) { f.dateFormat = "M 月 d 日" }
        return firstText + " – " + f.string(from: last)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) { Text("时间记录").font(.system(size: 26, weight: .semibold)); Text("把一天的去向，慢慢记下来。").font(.system(size: 12)).foregroundStyle(logQuiet) }
                Spacer()
                Button { newEntry(date: model.selectedLogDate, start: 540, end: 570) } label: { Label("新增记录", systemImage: "plus") }.buttonStyle(SoftButton())
            }
            HStack(spacing: 8) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 18) }.buttonStyle(SoftButton()).help(model.logScope == "week" ? "上一周" : "前一天")
                Button { model.selectedLogDate = Date() } label: { Text("今天") }.buttonStyle(SoftButton())
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 18) }.buttonStyle(SoftButton()).help(model.logScope == "week" ? "下一周" : "后一天")
                Spacer(minLength: 6)
                Picker("视图", selection: $model.logScope) { Text("周").tag("week"); Text("日").tag("day") }.pickerStyle(.segmented).frame(width: 96).labelsHidden()
            }
            HStack { Text(rangeTitle).font(.system(size: 13, weight: .medium)); Spacer(); DatePicker("选择日期", selection: $model.selectedLogDate, displayedComponents: .date).labelsHidden().fixedSize() }
            if let error = model.timeLogError { Text(error).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled) }
            calendarGrid
            HStack(spacing: 6) {
                if model.lastDeletedTimeID != nil {
                    Text("记录已移除。").font(.system(size: 11)).foregroundStyle(logQuiet)
                    Button("撤销") { model.undoTimeDeletion() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(logAccent)
                } else { Text("点击或拖选空白新增 · 拖动卡片移动 · 拉动上下边缘调整 · 半小时对齐").font(.system(size: 10)).foregroundStyle(logQuiet) }
                Spacer(minLength: 0)
                Text("仅保存在本机").font(.system(size: 10)).foregroundStyle(logQuiet)
            }
        }.padding(24).foregroundStyle(logInk).background(logPaper)
        .sheet(item: $draft) { value in TimeEntryEditor(model: model, draft: value) }
        .onChange(of: model.selectedLogDate) { _ in selection = nil; dragPreview = nil }
        .onChange(of: model.logScope) { _ in selection = nil; dragPreview = nil }
    }
    private var calendarGrid: some View {
        GeometryReader { geometry in
            let width = max(1, (geometry.size.width - axisWidth) / CGFloat(days.count))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("时间").font(.system(size: 10)).foregroundStyle(logQuiet).frame(width: axisWidth)
                    ForEach(days, id: \.self) { date in
                        let today = Calendar.current.isDateInToday(date)
                        Button { model.selectedLogDate = date; model.logScope = "day" } label: {
                            VStack(spacing: 5) { Text(weekday(date)).font(.system(size: 10)); Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits)).font(.system(size: 13, weight: today ? .semibold : .medium)) }.frame(width: width, height: 56).foregroundStyle(today ? logAccent : logInk).background(today ? logAccent.opacity(0.1) : .white.opacity(0.7))
                        }.buttonStyle(.plain).help("查看这一天")
                    }
                }.background(.white.opacity(0.7))
                Divider()
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        timeAxis
                        ForEach(Array(days.enumerated()), id: \.element) { index, date in
                            dayColumn(date, index: index, width: width)
                        }
                    }.padding(.top, 12).padding(.bottom, 14)
                }.background(Color.white.opacity(0.65))
            }.clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(logQuiet.opacity(0.13)))
        }.frame(minHeight: 300)
    }
    private var timeAxis: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(7...20, id: \.self) { hour in Text(String(format: "%02d:00", hour)).font(.system(size: 9, design: .monospaced)).foregroundStyle(logQuiet).position(x: 22, y: CGFloat(hour - 7) * hourHeight) }
        }.frame(width: axisWidth, height: hourHeight * 13)
    }
    private func dayColumn(_ date: Date, index: Int, width: CGFloat) -> some View {
        let key = TimeGrid.dayKey(date)
        let entries = shownEntries.filter { $0.day == key }
        let placements = TimeGrid.placements(entries, minimumDuration: Int(ceil(26 / hourHeight * 60)))
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Calendar.current.isDateInToday(date) ? logAccent.opacity(0.025) : .clear)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let range = TimeGrid.selection(fromY: value.startLocation.y, toY: value.location.y, hourHeight: hourHeight)
                    selection = GridSelection(day: key, start: range.0, end: range.1)
                }.onEnded { value in
                    let range = TimeGrid.selection(fromY: value.startLocation.y, toY: value.location.y, hourHeight: hourHeight)
                    selection = nil; newEntry(date: date, start: range.0, end: range.1)
                }).accessibilityLabel("\(key) 空白时间，点击新增记录")
            Rectangle().fill(logQuiet.opacity(0.12)).frame(width: 0.5)
            ForEach(0...26, id: \.self) { line in Rectangle().fill(logQuiet.opacity(line.isMultiple(of: 2) ? 0.17 : 0.07)).frame(height: 0.5).offset(y: CGFloat(line) * hourHeight / 2).allowsHitTesting(false) }
            if let selection, selection.day == key {
                RoundedRectangle(cornerRadius: 6).fill(logAccent.opacity(0.17)).overlay(RoundedRectangle(cornerRadius: 6).stroke(logAccent, style: StrokeStyle(lineWidth: 1, dash: [4,3])))
                    .overlay(Text("\(minuteText(selection.start))–\(minuteText(selection.end))").font(.system(size: 9)).foregroundStyle(logAccent))
                    .frame(width: width - 6, height: CGFloat(selection.end - selection.start) / 60 * hourHeight).offset(x: 3, y: CGFloat(selection.start - 420) / 60 * hourHeight).allowsHitTesting(false)
            }
            ForEach(entries) { entry in
                if let placement = placements.first(where: { $0.id == entry.id }) {
                    let laneWidth = (width - 4) / CGFloat(placement.laneCount)
                    let displayed = dragPreview?.id == entry.id ? dragPreview! : entry
                    let targetIndex = days.firstIndex { TimeGrid.dayKey($0) == displayed.day } ?? index
                    let height = max(24, CGFloat(displayed.endMinute - displayed.startMinute) / 60 * hourHeight - 2)
                    eventCard(entry, displayed: displayed, index: index, dayWidth: width, height: height)
                        .frame(width: max(4, laneWidth - 3), height: height)
                        .offset(x: 3 + CGFloat(placement.lane) * laneWidth + CGFloat(targetIndex - index) * width, y: CGFloat(displayed.startMinute - 420) / 60 * hourHeight + 1)
                        .zIndex(dragPreview?.id == entry.id ? 100 : 0)
                }
            }
        }.frame(width: width, height: hourHeight * 13)
        .zIndex(dragPreview.flatMap { preview in model.timeEntries.first { $0.id == preview.id } }?.day == key ? 1 : 0)
    }
    private func eventCard(_ entry: TimeEntry, displayed: TimeEntry, index: Int, dayWidth: CGFloat, height: CGFloat) -> some View {
        let palette = logPalette(entry.color)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6).fill(palette.0)
            Rectangle().fill(palette.1).frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                resizeHandle(entry, edge: "start", color: palette.1, compact: height < 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayed.title).font(.system(size: 10, weight: .medium)).lineLimit(height > 90 ? 4 : (height > 50 ? 2 : 1)).frame(maxWidth: .infinity, alignment: .leading)
                    if height > 43 { Text("\(minuteText(displayed.startMinute))–\(minuteText(displayed.endMinute))").font(.system(size: 8, design: .monospaced)).foregroundStyle(logInk.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.75) }
                }.padding(.horizontal, 6)
                Spacer(minLength: 0)
                resizeHandle(entry, edge: "end", color: palette.1, compact: height < 30)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.1.opacity(0.15)))
        .help("\(entry.title)\n\(entry.day) \(minuteText(entry.startMinute))–\(minuteText(entry.endMinute))\(entry.note.isEmpty ? "" : "\n" + entry.note)")
        .onTapGesture { editEntry(entry) }
        .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global).onChanged { value in
            let base = original(entry)
            let originalIndex = days.firstIndex { TimeGrid.dayKey($0) == base.day } ?? index
            let target = max(0, min(days.count - 1, originalIndex + Int((value.translation.width / dayWidth).rounded())))
            dragPreview = TimeGrid.moved(base, deltaMinutes: Int(value.translation.height / hourHeight * 60), dayOffset: target - originalIndex)
        }.onEnded { value in
            let base = original(entry)
            let originalIndex = days.firstIndex { TimeGrid.dayKey($0) == base.day } ?? index
            let target = max(0, min(days.count - 1, originalIndex + Int((value.translation.width / dayWidth).rounded())))
            let changed = TimeGrid.moved(base, deltaMinutes: Int(value.translation.height / hourHeight * 60), dayOffset: target - originalIndex)
            dragPreview = nil; _ = model.saveTimeEntry(changed)
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.title)，\(entry.day)，\(minuteText(entry.startMinute)) 到 \(minuteText(entry.endMinute))")
        .accessibilityAddTraits(.isButton).accessibilityAction { editEntry(entry) }
    }
    private func resizeHandle(_ entry: TimeEntry, edge: String, color: Color, compact: Bool) -> some View {
        Capsule().fill(color.opacity(0.55)).frame(width: 16, height: 2).frame(maxWidth: .infinity).frame(height: compact ? 4 : 7).contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global).onChanged { value in
                dragPreview = TimeGrid.resized(original(entry), edge: edge, deltaMinutes: Int(value.translation.height / hourHeight * 60))
            }.onEnded { value in
                let changed = TimeGrid.resized(original(entry), edge: edge, deltaMinutes: Int(value.translation.height / hourHeight * 60))
                dragPreview = nil; _ = model.saveTimeEntry(changed)
            }).help(edge == "start" ? "拖动调整开始时间" : "拖动调整结束时间")
    }
    private func original(_ entry: TimeEntry) -> TimeEntry { model.timeEntries.first { $0.id == entry.id } ?? entry }
    private func newEntry(date: Date, start: Int, end: Int) { draft = TimeDraft(date: date, start: start, end: end) }
    private func editEntry(_ entry: TimeEntry) { draft = TimeDraft(existing: entry, date: TimeGrid.date(for: entry.day) ?? model.selectedLogDate, start: entry.startMinute, end: entry.endMinute) }
    private func shift(_ direction: Int) { if let date = Calendar.current.date(byAdding: .day, value: direction * (model.logScope == "week" ? 7 : 1), to: model.selectedLogDate) { model.selectedLogDate = date } }
    private func weekday(_ date: Date) -> String { let names = ["周日","周一","周二","周三","周四","周五","周六"]; return names[Calendar.current.component(.weekday, from: date) - 1] }
}

private struct TimeEntryEditor: View {
    @ObservedObject var model: AppModel
    let draft: TimeDraft
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var title = ""
    @State private var note = ""
    @State private var color = "violet"
    @State private var start = 540
    @State private var end = 570
    @State private var validation: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.existing == nil ? "这段时间做了什么？" : "修改时间记录").font(.system(size: 23, weight: .semibold))
            TextField("例如：写文章、拜访客户、午休", text: $title).textFieldStyle(.roundedBorder).font(.system(size: 14))
            DatePicker("日期", selection: $date, displayedComponents: .date)
            HStack(spacing: 24) { DatePicker("开始", selection: timeBinding(start: true), displayedComponents: .hourAndMinute); DatePicker("结束", selection: timeBinding(start: false), displayedComponents: .hourAndMinute) }
            Text("可填写 07:00–20:00 的任意时段；日历拖动按半小时对齐。").font(.system(size: 11)).foregroundStyle(logQuiet)
            HStack(spacing: 12) {
                Text("颜色").font(.system(size: 12)).foregroundStyle(logQuiet)
                ForEach(TimeGrid.colors, id: \.self) { key in
                    let palette = logPalette(key)
                    Button { color = key } label: { Circle().fill(palette.0).overlay(Circle().stroke(color == key ? palette.1 : .clear, lineWidth: 2)).overlay(Image(systemName: color == key ? "checkmark" : "").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.1)).frame(width: 29, height: 29) }.buttonStyle(.plain).help(palette.2).accessibilityLabel(palette.2)
                }
            }
            Text("备注（选填）").font(.system(size: 12)).foregroundStyle(logQuiet)
            TextEditor(text: $note).font(.system(size: 12)).frame(height: 70).padding(6).background(.white, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(logQuiet.opacity(0.2)))
            if let validation { Text(validation).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                if let existing = draft.existing { Button("删除记录", role: .destructive) { if model.removeTimeEntry(existing.id) { dismiss() } }.buttonStyle(.plain).font(.system(size: 12)) }
                Spacer(); Button("取消") { dismiss() }.buttonStyle(SoftButton())
                Button("保存记录") { save() }.buttonStyle(SoftButton(primary: true)).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(30).frame(width: 480).background(logPaper).foregroundStyle(logInk)
        .onAppear { date = draft.date; start = draft.start; end = draft.end; title = draft.existing?.title ?? ""; note = draft.existing?.note ?? ""; color = draft.existing?.color ?? "violet" }
    }
    private func timeBinding(start isStart: Bool) -> Binding<Date> {
        Binding(get: {
            let minute = isStart ? start : end
            return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date) ?? date
        }, set: { value in
            let c = Calendar.current.dateComponents([.hour,.minute], from: value), minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            if isStart { start = minute } else { end = minute }
        })
    }
    private func save() {
        do {
            let entry = try TimeEntry(id: draft.existing?.id ?? UUID().uuidString, day: TimeGrid.dayKey(date), startMinute: start, endMinute: end, title: title, note: note, color: color)
            if model.saveTimeEntry(entry) { dismiss() }
        } catch { validation = error.localizedDescription }
    }
}
