import Foundation

public struct InboxItem: Codable, Identifiable, Equatable {
    public var id = UUID().uuidString
    public var title: String
    public var createdAt: Double
    public var deletedAt: Double?

    static func title(_ value: String?) throws -> String {
        let title = (value ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !title.isEmpty else { throw FocusError("先写下你想收集的事") }
        guard title.count <= 120 else { throw FocusError("标题请控制在 120 个字以内") }
        guard !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw FocusError("标题中包含无法保存的字符") }
        return title
    }
    static func validate(_ items: [InboxItem]) throws {
        var ids = Set<String>()
        for item in items {
            guard !item.id.isEmpty, ids.insert(item.id).inserted,
                  try title(item.title) == item.title, item.createdAt.isFinite, item.createdAt >= 0,
                  item.deletedAt == nil || (item.deletedAt!.isFinite && item.deletedAt! >= 0) else { throw FocusError("收集箱数据无效，已保留原文件") }
        }
    }
}

extension FocusState {
    public var activeInboxItems: [InboxItem] { (inboxItems ?? []).filter { $0.deletedAt == nil } }
    mutating func applyInbox(_ command: Command, now: Double) throws {
        var items = inboxItems ?? []
        if command.action == "addInbox" {
            items.append(InboxItem(title: try InboxItem.title(command.title), createdAt: now))
        } else {
            guard let index = items.firstIndex(where: { $0.id == command.taskID }) else {
                if command.action == "moveInboxToday", tasks.contains(where: { $0.id == command.taskID }) { return }
                throw FocusError("这件事已移出收集箱")
            }
            if command.action == "restoreInbox" { items[index].deletedAt = nil }
            else {
                guard items[index].deletedAt == nil else { throw FocusError("这件事已从收集箱移除") }
                switch command.action {
                case "editInbox": items[index].title = try InboxItem.title(command.title)
                case "deleteInbox": items[index].deletedAt = now
                case "moveInboxToday":
                    let item = items[index]
                    guard !tasks.contains(where: { $0.id == item.id }) else { throw FocusError("任务编号冲突，未移动原记录") }
                    tasks.append(FocusTask(id: item.id, title: item.title, nextStep: "", day: Self.day(at: now)))
                    items.remove(at: index)
                default: throw FocusError("不支持的收集箱操作")
                }
            }
        }
        inboxItems = items
    }
}
