import Foundation

public struct TaskCompletionRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var taskID: String
    public var subtaskID: String?
    public var title: String
    public var parentTitle: String?
    public var completedAt: Double?
    public var estimatedPomodoros: Int?
    public var focusRecordIDs: [String]
    public var completedPomodoros: Int
    public var focusSeconds: Double

    public init(id: String = UUID().uuidString, taskID: String, subtaskID: String? = nil, title: String,
                parentTitle: String? = nil, completedAt: Double? = nil, estimatedPomodoros: Int? = nil,
                focusRecordIDs: [String] = [], completedPomodoros: Int = 0, focusSeconds: Double = 0) {
        self.id = id; self.taskID = taskID; self.subtaskID = subtaskID; self.title = title
        self.parentTitle = parentTitle; self.completedAt = completedAt; self.estimatedPomodoros = estimatedPomodoros
        self.focusRecordIDs = focusRecordIDs; self.completedPomodoros = completedPomodoros; self.focusSeconds = focusSeconds
    }
}

public extension FocusState {
    var completionHistory: [TaskCompletionRecord] { completionRecords ?? [] }
}

extension FocusState {
    /// nil is the one-time migration marker; an empty array has already migrated.
    mutating func migrateTaskCompletions() {
        schema = 6
        guard completionRecords == nil else { return }
        completionRecords = []
        for task in tasks {
            if task.completed { appendCompletion(task: task, completedAt: task.completedAt) }
            for step in task.steps where step.completed {
                appendCompletion(task: task, subtask: step, completedAt: step.completedAt)
            }
        }
        completionRecords?.sort { ($0.completedAt ?? -.infinity) > ($1.completedAt ?? -.infinity) }
    }

    mutating func appendCompletion(task: FocusTask, subtask: FocusSubtask? = nil, completedAt: Double?) {
        let totals = taskProgress(taskID: task.id, subtaskID: subtask?.id, through: completedAt)
        let record = TaskCompletionRecord(taskID: task.id, subtaskID: subtask?.id, title: subtask?.title ?? task.title,
            parentTitle: subtask == nil ? nil : task.title, completedAt: completedAt,
            estimatedPomodoros: subtask == nil ? task.estimatedPomodoros : nil, focusRecordIDs: totals.recordIDs,
            completedPomodoros: totals.completedPomodoros, focusSeconds: totals.focusSeconds)
        if completionRecords == nil { completionRecords = [] }
        completionRecords?.insert(record, at: 0)
    }

    func validateTaskProgress() throws {
        for task in tasks { try validateSchedule(day: task.scheduledDay, reminderAt: task.reminderAt) }
        func validID(_ value: String) -> Bool { !value.isEmpty && value.count <= 100 }
        func validTitle(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 120 }
        func validEstimate(_ value: Int?) -> Bool { value == nil || value! > 0 }
        guard tasks.allSatisfy({ validEstimate($0.estimatedPomodoros) }) else { throw FocusError("预估番茄钟数据无效，原文件已保留") }
        let records = completionHistory
        guard Set(records.map(\.id)).count == records.count else { throw FocusError("完成记录重复，原文件已保留") }
        for record in records {
            guard validID(record.id), validID(record.taskID), record.subtaskID.map(validID) != false,
                  validTitle(record.title), record.parentTitle.map(validTitle) != false,
                  (record.subtaskID == nil ? record.parentTitle == nil : record.parentTitle != nil),
                  record.completedAt?.isFinite != false, validEstimate(record.estimatedPomodoros),
                  record.focusRecordIDs.allSatisfy(validID), Set(record.focusRecordIDs).count == record.focusRecordIDs.count,
                  record.completedPomodoros >= 0, record.completedPomodoros <= record.focusRecordIDs.count,
                  record.focusSeconds.isFinite, record.focusSeconds >= 0 else {
                throw FocusError("完成记录数据无效，原文件已保留")
            }
            let expectedIDs = Set(record.focusRecordIDs)
            let source = history.filter { expectedIDs.contains($0.id) }
            guard Set(source.map(\.id)) == expectedIDs,
                  source.allSatisfy({ $0.taskID == record.taskID && (record.subtaskID == nil || $0.subtaskID == record.subtaskID)
                      && (record.completedAt == nil || $0.endAt <= record.completedAt!)
                      && $0.startAt.isFinite && $0.endAt.isFinite && $0.endAt >= $0.startAt
                      && $0.focusSeconds.isFinite && $0.focusSeconds >= 0 && $0.focusSeconds <= $0.endAt - $0.startAt }) else {
                throw FocusError("完成记录关联无效，原文件已保留")
            }
            let total = progress(for: source)
            guard record.completedPomodoros == total.completedPomodoros,
                  abs(record.focusSeconds - total.focusSeconds) < 0.000_001 else {
                throw FocusError("完成记录汇总无效，原文件已保留")
            }
        }
    }
}
