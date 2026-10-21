import Foundation

public enum ForestPlantKind: CaseIterable, Sendable {
    case sapling, tree, mediumTree, largeTree, pit

    public var title: String {
        switch self {
        case .sapling: return "小树"
        case .tree: return "正常树"
        case .mediumTree: return "稍大的树"
        case .largeTree: return "大树"
        case .pit: return "树坑"
        }
    }
    public var scale: Double {
        switch self {
        case .sapling: return 0.58
        case .tree: return 0.84
        case .mediumTree: return 0.97
        case .largeTree: return 1.16
        case .pit: return 1
        }
    }
}

public struct ForestItem: Identifiable {
    public let record: FocusRecord
    public var id: String { record.id }
    public init(record: FocusRecord) { self.record = record }
    public var kind: ForestPlantKind {
        guard record.finished else { return .pit }
        // A completed round's wall-clock span is its original duration. Net
        // focusSeconds may be shorter after temporarily opening a website.
        let minutes = (record.endAt - record.startAt) / 60
        if minutes <= 15.5 { return .sapling }
        if minutes <= 25.5 { return .tree }
        if minutes <= 30.5 { return .mediumTree }
        return .largeTree
    }
}

public struct DailyForest {
    public let records: [FocusRecord]
    public var items: [ForestItem] { records.map(ForestItem.init) }
    public var completedCount: Int { records.filter(\.finished).count }
    public var interruptedCount: Int { records.count - completedCount }
    public var focusMinutes: Int {
        Int(records.reduce(0.0) { $0 + max(0, $1.focusSeconds.isFinite ? $1.focusSeconds : 0) } / 60)
    }
    public init(records: [FocusRecord], on date: Date, calendar: Calendar = .current) {
        guard let interval = calendar.dateInterval(of: .day, for: date) else { self.records = []; return }
        let start = interval.start.timeIntervalSince1970, end = interval.end.timeIntervalSince1970
        self.records = records.filter { $0.startAt >= start && $0.startAt < end }
            .sorted { $0.startAt == $1.startAt ? $0.id < $1.id : $0.startAt < $1.startAt }
    }
}

public struct ForestPosition: Equatable {
    public let x: Double
    public let y: Double
    public let scale: Double
}

public enum ForestLayout {
    public static func positions(count: Int) -> [ForestPosition] {
        guard count > 0 else { return [] }
        if count == 1 { return [ForestPosition(x: 0.5, y: 0.62, scale: 1)] }
        if count <= 7 {
            let points: [(Double, Double)] = [(430,149), (320,205), (540,205), (210,263), (430,263), (320,322), (540,322)]
            return points.prefix(count).map { ForestPosition(x: $0.0 / 860, y: $0.1 / 430, scale: 1) }
        }
        let side = Int(ceil(sqrt(Double(count))))
        return (0..<count).map { index in
            let row = index / side, column = index % side
            return ForestPosition(x: 0.5 + Double(column - row) / Double(side - 1) * 0.34,
                                  y: 0.32 + Double(column + row) / Double(2 * side - 2) * 0.46,
                                  scale: min(1, 3.1 / Double(side)))
        }
    }
}
