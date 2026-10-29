import SwiftUI

/// A tomato records one fully ended focus round, independent of the round's length.
struct PomodoroProgressView: View {
    let completed: Int
    let estimated: Int?
    var isCompleted = false

    private let iconLimit = 12
    private let muted = Color(red: 0.50, green: 0.53, blue: 0.47)
    private var rounds: Int { max(0, completed) }
    private var estimate: Int? { estimated.flatMap { $0 > 0 ? $0 : nil } }
    private var remaining: Int { isCompleted ? 0 : max(0, (estimate ?? 0) - rounds) }
    private var filledCount: Int { min(rounds, iconLimit) }
    private var emptyCount: Int { min(remaining, iconLimit - filledCount) }
    private var overflowCount: Int { max(0, max(rounds, isCompleted ? 0 : (estimate ?? 0)) - iconLimit) }
    private var countLabel: String {
        if let estimate { return "已完成 \(rounds) / 预估 \(estimate)" }
        return "已完成 \(rounds) 个 · 未设置预估"
    }
    private var accessibilitySummary: String {
        let actual = "已完成 \(rounds) 个番茄钟，按完整轮次计数"
        return actual + (estimate.map { "，预估 \($0) 个" } ?? "，未设置预估")
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) { marks; count }
            VStack(alignment: .leading, spacing: 6) { marks; count }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .help("实心番茄表示完整结束一轮，15／25／30／45 分钟都算一轮；空心表示距离预估还差的轮次。达到预估后，任务仍需手动标记完成。")
    }
    private var marks: some View {
        HStack(spacing: 4) {
            ForEach(0..<filledCount, id: \.self) { _ in TomatoMark(filled: true) }
            ForEach(0..<emptyCount, id: \.self) { _ in TomatoMark(filled: false) }
            if overflowCount > 0 { Text("另 \(overflowCount) 个").font(.system(size: 10)).foregroundStyle(muted).padding(.leading, 2) }
        }.fixedSize()
    }
    private var count: some View {
        Text(countLabel).font(.system(size: 10))
            .foregroundStyle(estimate.map { rounds > $0 } == true ? Color(red: 0.67, green: 0.47, blue: 0.30) : muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TomatoMark: View {
    let filled: Bool
    var body: some View {
        ZStack {
            TomatoFruit().fill(filled ? Color(red: 0.87, green: 0.47, blue: 0.39) : .clear)
            TomatoFruit().stroke(filled ? Color(red: 0.80, green: 0.42, blue: 0.35) : Color(red: 0.83, green: 0.85, blue: 0.80), lineWidth: 1.2)
            TomatoStem().fill(filled ? Color(red: 0.47, green: 0.58, blue: 0.42) : .clear)
            TomatoStem().stroke(filled ? Color(red: 0.43, green: 0.56, blue: 0.38) : Color(red: 0.76, green: 0.80, blue: 0.72), lineWidth: 1.2)
        }.frame(width: 18, height: 18).accessibilityHidden(true)
    }
}

private struct TomatoFruit: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 7))
        path.addCurve(to: CGPoint(x: 2, y: 12), control1: CGPoint(x: 7, y: 3), control2: CGPoint(x: 2, y: 7))
        path.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 2, y: 18), control2: CGPoint(x: 7, y: 22))
        path.addCurve(to: CGPoint(x: 22, y: 12), control1: CGPoint(x: 17, y: 22), control2: CGPoint(x: 22, y: 18))
        path.addCurve(to: CGPoint(x: 12, y: 7), control1: CGPoint(x: 22, y: 7), control2: CGPoint(x: 17, y: 3))
        path.closeSubpath()
        return path.applying(CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 24, tx: rect.minX, ty: rect.minY))
    }
}

private struct TomatoStem: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint] = [CGPoint(x: 12, y: 8), CGPoint(x: 7, y: 4), CGPoint(x: 11, y: 5), CGPoint(x: 12, y: 1), CGPoint(x: 14, y: 5), CGPoint(x: 18, y: 4), CGPoint(x: 14, y: 8)]
        path.addLines(points)
        path.closeSubpath()
        return path.applying(CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 24, tx: rect.minX, ty: rect.minY))
    }
}
