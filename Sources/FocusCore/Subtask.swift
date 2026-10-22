import Foundation

public struct FocusSubtask: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var completed: Bool
    public var completedAt: Double?
    public init(id: String = UUID().uuidString, title: String, completed: Bool = false, completedAt: Double? = nil) {
        self.id = id; self.title = title; self.completed = completed; self.completedAt = completedAt
    }
}
public extension FocusTask {
    var steps: [FocusSubtask] { subtasks ?? [] }
    var editVersion: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self).base64EncodedString()) ?? ""
    }
}
public extension FocusRecord {
    var displayTitle: String { subtaskTitle.map { "\(title) · \($0)" } ?? title }
}
public extension Session {
    var displayTitle: String { subtaskTitle ?? title }
}
extension FocusState {
    func validateSubtasks() throws {
        for task in tasks {
            guard task.steps.count <= 30, Set(task.steps.map(\.id)).count == task.steps.count else { throw FocusError("小任务数据无效，原文件已保留") }
            for step in task.steps {
                guard !step.id.isEmpty, step.id.count <= 100, !step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      step.title.count <= 120, step.completedAt?.isFinite != false else { throw FocusError("小任务数据无效，原文件已保留") }
            }
            guard task.completedAt?.isFinite != false else { throw FocusError("任务完成时间无效") }
        }
    }
    mutating func applySubtasks(_ command: Command, now: Double) throws {
        guard let i = tasks.firstIndex(where: { $0.id == command.taskID }) else { throw FocusError("主任务已不存在，请重新选择") }
        guard session?.taskID != tasks[i].id else { throw FocusError("这一轮结束后再修改小任务") }
        if let expected = command.expectedTaskVersion, expected != tasks[i].editVersion { throw FocusError("主任务或小任务已被修改，请重新生成建议，避免覆盖你的更改") }
        var steps = tasks[i].steps
        if command.action == "appendSubtasks" {
            guard !tasks[i].completed else { throw FocusError("请先恢复这个主任务，再添加小任务") }
            let titles = (command.subtaskTitles ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !titles.isEmpty, titles.allSatisfy({ !$0.isEmpty && $0.count <= 120 }), steps.count + titles.count <= 30 else { throw FocusError("每个小任务填写 1–120 字，一个主任务最多 30 个小任务") }
            guard Set(titles).count == titles.count, !titles.contains(where: { title in steps.contains(where: { $0.title == title }) }) else { throw FocusError("有重复的小任务，请修改后再添加") }
            steps.append(contentsOf: titles.map { FocusSubtask(title: $0) })
        } else {
            guard let j = steps.firstIndex(where: { $0.id == command.subtaskID }) else { throw FocusError("这个小任务已不存在") }
            if command.action == "deleteSubtask" { steps.remove(at: j) }
            else if command.action == "completeSubtask" { steps[j].completed.toggle(); steps[j].completedAt = steps[j].completed ? now : nil }
            else {
                let title = (command.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.count <= 120 else { throw FocusError("小任务请填写 1–120 字") }
                steps[j].title = title
            }
        }
        tasks[i].subtasks = steps
    }
}
