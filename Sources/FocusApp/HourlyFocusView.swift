import SwiftUI
import FocusCore

struct HourlyFocusView: View {
    let records: [FocusRecord]
    let now: Date
    @State private var days = 28
    @State private var selected: Int?
    private let sage = Color(red: 0.38, green: 0.46, blue: 0.32)
    var body: some View {
        let stats = HourlyFocusStatistics(records: records, ending: now, days: days)
        let maximum = stats.seconds.max() ?? 0
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text("一天中的专注时段").font(.system(size: 16, weight: .semibold)); Text("观察什么时候更常开始专注").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                Picker("时间范围", selection: $days) { Text("7 天").tag(7); Text("4 周").tag(28); Text("90 天").tag(90) }.pickerStyle(.segmented).frame(width: 180).labelsHidden()
            }
            if maximum == 0 {
                Text("这个时间范围还没有专注记录。") .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            } else { HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24) { hour in
                    Button { selected = hour } label: {
                        VStack(spacing: 5) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3).fill(sage.opacity(selected == hour ? 1 : 0.6))
                                .frame(height: maximum > 0 ? max(2, 115 * stats.seconds[hour] / maximum) : 2)
                            Text(hour.isMultiple(of: 3) ? String(format: "%02d", hour) : " ").font(.system(size: 9)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).frame(height: 135).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(String(format: "%02d:00", hour) + " 开始的专注：\(Int(stats.seconds[hour] / 60)) 分钟")
                    .accessibilityLabel("\(hour) 点开始的专注，\(Int(stats.seconds[hour] / 60)) 分钟")
                }
            } }
            if let selected { Text("\(selected) 点开始的专注：\(Int(stats.seconds[selected] / 60)) 分钟") .font(.system(size: 12, weight: .medium)) }
            Text("按每轮开始的小时归类整轮净专注时间，包含提前结束；仅表示专注发生较多的时段，并不代表效率高低。") .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
        }.padding(20).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
    }
}
