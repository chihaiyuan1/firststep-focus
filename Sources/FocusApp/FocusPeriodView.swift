import SwiftUI
import FocusCore

private let statsSage = Color(red: 0.38, green: 0.46, blue: 0.32)
private let statsQuiet = Color(red: 0.50, green: 0.53, blue: 0.47)

struct FocusPeriodView: View {
    let records: [FocusRecord]
    let scope: FocusStatisticsScope
    @Binding var date: Date
    let today: Date
    @State private var hovered: Date?
    @State private var selected: Date?
    private var calendar: Calendar { .current }

    var body: some View {
        let stats = FocusStatistics(records: records, on: date, scope: scope, calendar: calendar)
        let active = stats.buckets.first { $0.id == (hovered ?? selected) }
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                metric("总专注时长", value: durationText(stats.totalFocusSeconds), emphasis: true)
                metric("完成番茄钟数量", value: "\(stats.completedCount) 个")
            }
            VStack(alignment: .leading, spacing: 0) {
                periodHeader(stats).padding(20)
                HStack(spacing: 6) {
                    Circle().fill(statsSage).frame(width: 6, height: 6)
                    Text(scope == .week ? "每天的专注时长" : "每周的专注时长")
                    Spacer()
                    Text("单位：分钟")
                }.font(.system(size: 11)).foregroundStyle(statsQuiet).padding(.horizontal, 22)
                chart(stats).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 18)
                Divider().opacity(0.5)
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill").font(.system(size: 15)).foregroundStyle(statsSage)
                        .frame(width: 34, height: 34).background(statsSage.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(active.map(bucketTitle) ?? (scope == .week ? "一周的投入，按天看见" : "一个月的积累，按周回看"))
                            .font(.system(size: 13, weight: .medium))
                        Text(active.map { "专注 \(durationText($0.focusSeconds)) · 完成 \($0.completedCount) 个番茄钟" }
                             ?? (scope == .week ? "指向或点击柱子，查看当天的数据。" : "指向或点击柱子，查看这一周的数据。"))
                            .font(.system(size: 11)).foregroundStyle(statsQuiet)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(18).background(.white.opacity(0.55)).accessibilityElement(children: .combine)
            }
            .background(LinearGradient(colors: [.white.opacity(0.85), Color(red: 0.96, green: 0.98, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(statsSage.opacity(0.13)))
            Text(scope == .week
                 ? "每周按周一至周日统计，每根柱子代表一天。"
                 : "每根柱子代表周一至周日的一周；月初和月末只统计属于当月的日期，所有柱子的时长之和就是当月总时长。")
                .font(.system(size: 11)).foregroundStyle(statsQuiet).lineSpacing(4)
        }
        .onChange(of: scope) { _ in clearSelection() }
        .onChange(of: stats.interval.start) { _ in clearSelection() }
    }

    private func metric(_ title: String, value: String, emphasis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 11)).foregroundStyle(statsQuiet)
            Text(value).font(.system(size: 28, weight: .regular, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(19)
            .background(emphasis ? Color(red: 0.92, green: 0.94, blue: 0.88) : .white.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(statsSage.opacity(0.1)))
            .accessibilityElement(children: .ignore).accessibilityLabel("\(title)，\(value)")
    }

    private func periodHeader(_ stats: FocusStatistics) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(periodTitle(stats)).font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(scope == .week ? "周一至周日 · 按天统计" : "当月 1 日至月底 · 按周统计")
                    .font(.system(size: 10)).foregroundStyle(statsQuiet)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button { date = scope.shiftedDate(from: date, by: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(scope == .week ? "上一周" : "上个月")
                Button(scope == .week ? "本周" : "本月") { date = today }
                    .font(.system(size: 11)).accessibilityLabel(scope == .week ? "回到本周" : "回到本月")
                Button { date = scope.shiftedDate(from: date, by: 1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel(scope == .week ? "下一周" : "下个月")
                DatePicker("统计日期", selection: $date, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field).font(.system(size: 11)).fixedSize()
                    .accessibilityLabel("选择统计日期")
            }.buttonStyle(.borderless)
        }
    }

    private func chart(_ stats: FocusStatistics) -> some View {
        let maxMinutes = (stats.buckets.map(\.focusSeconds).max() ?? 0) / 60
        let upperMinutes = max(60, ceil(maxMinutes / 60) * 60)
        let height = 220.0
        return HStack(alignment: .top, spacing: 8) {
            GeometryReader { geometry in
                ForEach(0..<5) { tick in
                    Text("\(Int(upperMinutes * Double(tick) / 4))")
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(statsQuiet)
                        .frame(width: geometry.size.width, alignment: .trailing)
                        .position(x: geometry.size.width / 2, y: height * (1 - Double(tick) / 4))
                }
            }.frame(width: 35, height: height).accessibilityHidden(true)
            ZStack(alignment: .top) {
                GeometryReader { geometry in
                    ForEach(0..<5) { tick in
                        Rectangle().fill(statsSage.opacity(tick == 0 ? 0.19 : 0.09)).frame(height: 0.7)
                            .position(x: geometry.size.width / 2, y: height * (1 - Double(tick) / 4))
                    }
                }.frame(height: height).allowsHitTesting(false).accessibilityHidden(true)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(stats.buckets) { bucket in
                        column(bucket, upper: upperMinutes, height: height)
                    }
                }
                if stats.totalFocusSeconds == 0 && stats.completedCount == 0 {
                    Text(scope == .week ? "这一周还没有专注记录" : "这个月还没有专注记录")
                        .font(.system(size: 12)).foregroundStyle(statsQuiet)
                        .frame(maxWidth: .infinity).padding(.top, 90).allowsHitTesting(false)
                }
            }
        }.frame(height: height + 45)
    }

    private func column(_ bucket: FocusStatisticsBucket, upper: Double, height: Double) -> some View {
        let active = bucket.id == (hovered ?? selected)
        let positive = bucket.focusSeconds > 0
        let barHeight = positive ? max(3, min(height, bucket.focusSeconds / 60 / upper * height)) : 2
        return Button { selected = selected == bucket.id ? nil : bucket.id } label: {
            VStack(spacing: 9) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: positive ? 5 : 1)
                        .fill(LinearGradient(colors: positive ? [statsSage.opacity(active ? 1 : 0.73), statsSage.opacity(active ? 0.88 : 0.56)] : [statsSage.opacity(0.16)], startPoint: .top, endPoint: .bottom))
                        .frame(height: barHeight).padding(.horizontal, 9)
                }.frame(height: height)
                    .background(active ? statsSage.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 8))
                VStack(spacing: 4) {
                    Text(axisTitle(bucket)).font(.system(size: 11, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? statsSage : statsQuiet).lineLimit(1).minimumScaleFactor(0.75)
                    if scope == .week {
                        Text("\(calendar.component(.month, from: bucket.start))/\(calendar.component(.day, from: bucket.start))")
                            .font(.system(size: 9)).foregroundStyle(statsQuiet.opacity(0.8))
                    }
                }
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = bucket.id }
            else if hovered == bucket.id { hovered = nil }
        }
        .help("\(bucketTitle(bucket)) · \(durationText(bucket.focusSeconds)) · \(bucket.completedCount) 个番茄钟")
        .accessibilityLabel("\(bucketTitle(bucket))，专注 \(durationText(bucket.focusSeconds))，完成 \(bucket.completedCount) 个番茄钟")
        .accessibilityAddTraits(selected == bucket.id ? .isSelected : [])
    }

    private func axisTitle(_ bucket: FocusStatisticsBucket) -> String {
        if scope == .week { return ["周日","周一","周二","周三","周四","周五","周六"][calendar.component(.weekday, from: bucket.start)-1] }
        let first = calendar.component(.day, from: bucket.start)
        let last = calendar.component(.day, from: lastDay(bucket.end))
        return first == last ? "\(first)日" : "\(first)–\(last)日"
    }
    private func bucketTitle(_ bucket: FocusStatisticsBucket) -> String {
        if scope == .week { return bucket.start.formatted(.dateTime.month().day().weekday(.wide)) }
        return bucket.start.formatted(.dateTime.month().day()) + " — " + lastDay(bucket.end).formatted(.dateTime.month().day())
    }
    private func periodTitle(_ stats: FocusStatistics) -> String {
        if scope == .month { return stats.interval.start.formatted(.dateTime.year().month(.wide)) }
        let last = lastDay(stats.interval.end)
        let end = calendar.component(.year, from: last) == calendar.component(.year, from: stats.interval.start)
            ? last.formatted(.dateTime.month().day()) : last.formatted(.dateTime.year().month().day())
        return stats.interval.start.formatted(.dateTime.year().month().day()) + " — " + end
    }
    private func lastDay(_ end: Date) -> Date { calendar.date(byAdding: .day, value: -1, to: end) ?? end }
    private func durationText(_ seconds: Double) -> String {
        if seconds > 0 && seconds < 60 { return "不足 1 分钟" }
        let minutes = max(0, Int(seconds / 60)), hours = minutes / 60
        if hours == 0 { return "\(minutes) 分钟" }
        return minutes % 60 == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes % 60) 分钟"
    }
    private func clearSelection() { hovered = nil; selected = nil }
}
