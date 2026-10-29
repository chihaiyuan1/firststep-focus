import SwiftUI
import FocusCore

private let forestInk = Color(red: 0.17, green: 0.20, blue: 0.16)
private let forestQuiet = Color(red: 0.50, green: 0.53, blue: 0.47)
private let forestSage = Color(red: 0.38, green: 0.46, blue: 0.32)

struct ForestView: View {
    @ObservedObject var model: AppModel
    @State private var date = Date()
    @State private var scope: FocusStatisticsScope = .day
    @State private var selectedID: String?
    @State private var expanded = false
    @State private var previousToday = Calendar.current.startOfDay(for: Date())
    private var calendar: Calendar { Calendar.current }
    private var today: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: model.now)) }
    private var forest: DailyForest { DailyForest(records: model.state.history, on: date, calendar: calendar) }
    private var selected: ForestItem? { forest.items.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("专注记录").font(.system(size: 26, weight: .semibold))
                    Text("每一小段，都长成了风景。").font(.system(size: 13)).foregroundStyle(forestQuiet)
                }
                Spacer(minLength: 0)
                Picker("统计范围", selection: $scope) {
                    ForEach(FocusStatisticsScope.allCases, id: \.self) { value in Text(value.title).tag(value) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 164).accessibilityLabel("统计范围")
            }.padding(.bottom, 3)
            if scope == .day {
                HStack(spacing: 12) {
                    statistic("当天完成的番茄钟", value: forest.completedCount, unit: "个", emphasis: true)
                    statistic("当天专注时长", value: forest.focusMinutes, unit: "分钟")
                    statistic("提前结束", value: forest.interruptedCount, unit: "次")
                }
                forestCard
                legend
                records
            } else {
                FocusPeriodView(records: model.state.history, scope: scope, date: $date, today: today)
            }
            HourlyFocusView(records: model.state.history, now: Date(timeIntervalSince1970: model.now))
            Text("按专注开始日期归档。完整结束长成树，提前结束留下树坑；临时开放网站的时段不计入专注分钟。日常活动仍可在「时间记录」中手动填写。")
                .font(.system(size: 11)).foregroundStyle(forestQuiet).lineSpacing(4)
        }
        .foregroundStyle(forestInk)
        .onChange(of: calendar.startOfDay(for: date)) { _ in selectedID = nil; expanded = false }
        .onChange(of: scope) { _ in selectedID = nil; expanded = false }
        .onChange(of: today) { newToday in
            let previous = scope.interval(containing: previousToday, calendar: calendar)
            if date >= previous.start && date < previous.end { date = newToday }
            previousToday = newToday
        }
    }

    private func statistic(_ title: String, value: Int, unit: String, emphasis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11)).foregroundStyle(forestQuiet).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(value)").font(.system(size: 32, weight: .regular, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 11)).foregroundStyle(forestQuiet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(17)
        .background(emphasis ? Color(red: 0.92, green: 0.94, blue: 0.88) : .white.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(forestSage.opacity(emphasis ? 0.13 : 0.07)))
        .accessibilityElement(children: .ignore).accessibilityLabel("\(title)，\(value) \(unit)")
    }

    private var forestCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(date, format: .dateTime.month().day()).font(.system(size: 16, weight: .semibold))
                    Text(date, format: .dateTime.weekday(.wide)).font(.system(size: 10)).foregroundStyle(forestQuiet)
                }
                Spacer(minLength: 4)
                Button { moveDay(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("前一天").help("前一天")
                Button("今天") { date = today }.font(.system(size: 11)).accessibilityLabel("回到今天")
                Button { moveDay(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("后一天").help("后一天")
                DatePicker("选择日期", selection: $date, displayedComponents: .date).labelsHidden().datePickerStyle(.field)
                    .font(.system(size: 11)).fixedSize().accessibilityLabel("选择森林日期")
            }.buttonStyle(.borderless).padding(.horizontal, 20).padding(.top, 19)
            weekStrip.padding(.horizontal, 17).padding(.top, 15)
            ForestScene(items: forest.items, selectedID: selectedID) { selectedID = $0 }
                .padding(.horizontal, 4)
            Text(forest.records.isEmpty ? "完成一轮，就会种下一棵树" : "点击树或树坑，看看这一轮做了什么")
                .font(.system(size: 10)).foregroundStyle(forestQuiet.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 21).padding(.bottom, 13)
            Divider().opacity(0.6)
            selectionDetail.padding(.horizontal, 18).padding(.vertical, 13).background(.white.opacity(0.5))
        }
        .background(LinearGradient(colors: [Color(red: 0.99, green: 0.99, blue: 0.97), Color(red: 0.96, green: 0.98, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(forestSage.opacity(0.14)))
    }

    private var weekStrip: some View {
        let start = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: date) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
        return HStack(spacing: 5) {
            ForEach(0..<7) { index in
                let day = calendar.date(byAdding: .day, value: index, to: monday) ?? monday
                let active = calendar.isDate(day, inSameDayAs: date)
                let hasTrees = model.state.history.contains { $0.finished && calendar.isDate(Date(timeIntervalSince1970: $0.startAt), inSameDayAs: day) }
                Button { date = day } label: {
                    VStack(spacing: 5) {
                        Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][index]).font(.system(size: 10))
                        Text("\(calendar.component(.day, from: day))").font(.system(size: 12, weight: active ? .semibold : .regular))
                        Circle().fill(hasTrees ? forestSage.opacity(0.55) : .clear).frame(width: 3, height: 3)
                    }.frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(active ? forestSage.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain).foregroundStyle(active ? forestSage : forestQuiet)
                .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted))\(hasTrees ? "，有已完成的专注" : "")")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    private var selectionDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
            ForestPlant(kind: selected?.kind ?? .tree).frame(width: 28, height: 32)
                .padding(5).background(forestSage.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(selected?.record.displayTitle ?? (forest.records.isEmpty ? "给这一天，留下一点生长" : "\(forest.completedCount) 轮专注，长成这一天的小森林"))
                    .font(.system(size: 12, weight: .medium)).lineLimit(2)
                if let item = selected {
                    Text("\(timeRange(item.record)) · 实际专注 \(Int(item.record.focusSeconds / 60)) 分钟 · 临时访问 \(item.record.accessCount) 次")
                        .font(.system(size: 10)).foregroundStyle(forestQuiet)
                } else {
                    Text("完整结束长成树，提前结束留树坑。").font(.system(size: 10)).foregroundStyle(forestQuiet)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(selected.map { $0.kind == .pit ? "提前结束 · 树坑" : $0.kind.title } ?? "每日一片森林")
                .font(.system(size: 10)).foregroundStyle(selected?.kind == .pit ? Color.brown : forestSage)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background((selected?.kind == .pit ? Color.brown : forestSage).opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        }
            .accessibilityElement(children: .combine)
            if let item = selected { SessionReflectionSummary(model: model, record: item.record) }
        }
    }

    private var legend: some View {
        HStack(spacing: 15) {
            legendItem(.sapling, "15 分钟")
            legendItem(.tree, "25 分钟")
            legendItem(.mediumTree, "30 分钟")
            legendItem(.largeTree, "45 分钟")
            legendItem(.pit, "提前结束")
        }.frame(maxWidth: .infinity).padding(.top, -8)
    }
    private func legendItem(_ kind: ForestPlantKind, _ title: String) -> some View {
        HStack(spacing: 3) {
            ForestPlant(kind: kind).frame(width: 15, height: 22)
            Text(title).font(.system(size: 10)).foregroundStyle(forestQuiet).lineLimit(1).minimumScaleFactor(0.75)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(title)，\(kind.title)")
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("这一天的专注").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(forest.records.count) 条记录 · 最新在前").font(.system(size: 10)).foregroundStyle(forestQuiet)
            }
            if forest.records.isEmpty {
                Text("这一天还没有专注记录。").font(.system(size: 12)).foregroundStyle(forestQuiet).padding(.vertical, 15)
            } else {
                VStack(spacing: 0) {
                    let recent = Array(forest.items.reversed())
                    ForEach(expanded ? recent : Array(recent.prefix(3))) { item in
                        recordRow(item)
                        if item.id != (expanded ? recent.last?.id : recent.prefix(3).last?.id) { Divider().opacity(0.45).padding(.horizontal, 15) }
                    }
                    if recent.count > 3 {
                        Divider().opacity(0.45)
                        Button(expanded ? "收起记录" : "展开全部 \(recent.count) 条记录") { expanded.toggle() }
                            .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(forestSage)
                            .frame(maxWidth: .infinity).padding(13)
                    }
                }.background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(forestSage.opacity(0.08)))
            }
        }
    }
    private func recordRow(_ item: ForestItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { selectedID = item.id } label: {
            HStack(spacing: 12) {
                ForestPlant(kind: item.kind).frame(width: 25, height: 32)
                    .padding(5).background(forestSage.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.record.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    Text("\(timeRange(item.record)) · \(item.record.finished ? "完整完成" : "提前结束") · 临时访问 \(item.record.accessCount) 次")
                        .font(.system(size: 10)).foregroundStyle(forestQuiet)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(Int(item.record.focusSeconds / 60)) 分钟").font(.system(size: 12, weight: .medium, design: .rounded))
                    Text(item.kind == .pit ? "留下一处树坑" : item.kind.title).font(.system(size: 10)).foregroundStyle(forestQuiet)
                }
            }.padding(.horizontal, 15).padding(.vertical, 13)
                .background(selectedID == item.id ? forestSage.opacity(0.06) : .clear)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(item.record.displayTitle)，\(item.record.finished ? "完整完成" : "提前结束")，专注 \(Int(item.record.focusSeconds / 60)) 分钟，查看\(item.kind.title)")
            SessionReflectionSummary(model: model, record: item.record, compact: true)
                .padding(.horizontal, 15).padding(.bottom, 13)
        }
    }
    private func moveDay(_ delta: Int) {
        if let next = calendar.date(byAdding: .day, value: delta, to: date) { date = next }
    }
    private func timeRange(_ record: FocusRecord) -> String {
        let format = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return Date(timeIntervalSince1970: record.startAt).formatted(format) + "–" + Date(timeIntervalSince1970: record.endAt).formatted(format)
    }
}
