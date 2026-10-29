import Foundation

public struct TaskFocusProgress: Equatable {
    public var completedPomodoros: Int
    public var focusSeconds: Double
    public var recordIDs: [String]

    public init(completedPomodoros: Int = 0, focusSeconds: Double = 0, recordIDs: [String] = []) {
        self.completedPomodoros = completedPomodoros
        self.focusSeconds = focusSeconds
        self.recordIDs = recordIDs
    }
}

public extension FocusState {
    /// A main task includes every child session, including sessions of deleted children.
    func taskProgress(taskID: String, subtaskID: String? = nil, through: Double? = nil) -> TaskFocusProgress {
        progress(for: history.filter {
            $0.taskID == taskID && (subtaskID == nil || $0.subtaskID == subtaskID)
                && (through == nil || $0.endAt <= through!)
        })
    }

    /// Completion cohorts can contain parent, child and repeated completion events.
    func completionProgress(for records: [TaskCompletionRecord]) -> TaskFocusProgress {
        let ids = Set(records.flatMap(\.focusRecordIDs))
        return progress(for: history.filter { ids.contains($0.id) })
    }
}

extension FocusState {
    func progress(for records: [FocusRecord]) -> TaskFocusProgress {
        var result = TaskFocusProgress()
        var seen = Set<String>()
        for record in records where seen.insert(record.id).inserted {
            result.recordIDs.append(record.id)
            if record.finished { result.completedPomodoros += 1 }
            result.focusSeconds += max(0, record.focusSeconds.isFinite ? record.focusSeconds : 0)
        }
        return result
    }
}
