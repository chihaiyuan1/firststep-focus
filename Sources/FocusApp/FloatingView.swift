import SwiftUI
import FocusCore

enum FloatingTimerMetrics {
    static let side: CGFloat = 112
    static let cornerRadius: CGFloat = 22
    static let screenInset: CGFloat = 20
}

private let timerPaper = Color(red: 0.96, green: 0.96, blue: 0.93)
private let timerInk = Color(red: 0.17, green: 0.20, blue: 0.16)
private let timerSage = Color(red: 0.38, green: 0.46, blue: 0.32)
private let timerPurple = Color(red: 0.55, green: 0.45, blue: 0.84)

struct FloatingView: View {
    @ObservedObject var model: AppModel
    @State private var hovering = false

    private var title: String {
        model.state.session?.displayTitle ?? (model.state.breakUntil != nil ? "休息一下" : "这一轮完成了")
    }
    private var status: String {
        guard model.state.session != nil else { return model.state.breakUntil != nil ? "休息中" : "已完成" }
        return model.extensionConnected ? "专注中" : "仅计时 · 未连接"
    }
    private var progress: Double {
        let duration = model.state.session.map { $0.endAt - $0.startAt } ?? 300
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - model.remaining / duration))
    }
    private var detail: String {
        guard let session = model.state.session else { return title }
        var lines = [session.displayTitle]
        if session.subtaskTitle != nil { lines.append("主任务：\(session.title)") }
        if !session.nextStep.isEmpty { lines.append(session.nextStep) }
        lines.append(model.extensionConnected ? "信息流已暂时屏蔽" : model.extensionConnectionHint)
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 14)).foregroundStyle(timerSage)
                    .opacity(hovering ? 0 : 1).accessibilityHidden(true)
                if !hovering, model.state.session != nil {
                    HStack {
                        Spacer()
                        Circle().fill(model.extensionConnected ? timerSage : .orange)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel(model.extensionConnectionLabel)
                    }
                }
                HStack(spacing: 0) {
                    Button { model.showMain?() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10)).frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }.help("打开主窗口").accessibilityLabel("打开主窗口")
                    Spacer(minLength: 0)
                    if model.state.session != nil {
                        Button { model.requestEnd() } label: {
                            Text("结束").font(.system(size: 9, weight: .medium))
                                .frame(width: 28, height: 22).contentShape(Rectangle())
                        }.help("提前结束，仍需等待确认").accessibilityLabel("提前结束专注")
                    }
                }
                .buttonStyle(.plain).foregroundStyle(timerSage)
                .opacity(hovering ? 1 : 0).allowsHitTesting(hovering)
                .accessibilityHidden(!hovering)
            }.frame(height: 18)

            Text(title).font(.system(size: 10, weight: .medium))
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity)
                .help(detail)
            Text(clockText(model.remaining))
                .font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.8).lineLimit(1).frame(height: 31)
                .accessibilityLabel("剩余 \(clockText(model.remaining))")
            GeometryReader { geometry in
                Capsule().fill(timerSage.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule().fill(model.state.session != nil ? timerPurple : timerSage)
                            .frame(width: geometry.size.width * progress)
                    }
            }.frame(height: 4).accessibilityHidden(true)
            Text(status).font(.system(size: 8.5))
                .foregroundStyle(model.state.session != nil && !model.extensionConnected ? .orange : timerSage)
                .lineLimit(1).help(detail)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(width: FloatingTimerMetrics.side, height: FloatingTimerMetrics.side)
        .foregroundStyle(timerInk).background(timerPaper)
        .overlay {
            RoundedRectangle(cornerRadius: FloatingTimerMetrics.cornerRadius)
                .strokeBorder(timerSage.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
    }
}
