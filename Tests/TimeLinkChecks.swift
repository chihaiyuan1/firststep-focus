import Foundation
@main struct TimeLinkChecks {
    static func main() throws {
        let old = """
        {"id":"old","day":"2026-10-29","startMinute":540,"endMinute":600,"title":"记录","note":"","color":"violet"}
        """
        let existing = try JSONDecoder().decode(TimeEntry.self, from: Data(old.utf8))
        precondition(existing.taskID == nil)
        let entry = try TimeEntry(id: "new", day: "2026-10-29", startMinute: 540, endMinute: 600, title: "记录", taskID: "task-1", taskTitleSnapshot: "原关联任务")
        let loaded = try JSONDecoder().decode(TimeEntry.self, from: JSONEncoder().encode(entry))
        precondition(loaded.taskID == "task-1" && loaded.taskTitleSnapshot == "原关联任务")
        precondition(loaded.linkedTaskTitle(tasks: []) == "原关联任务")
        precondition(TimeGrid.moved(loaded, deltaMinutes: 30).taskID == "task-1")
        print("PASS: old time entries and linked task survive save/move")
    }
}
