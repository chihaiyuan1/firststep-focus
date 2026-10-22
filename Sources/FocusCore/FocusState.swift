import Foundation

public struct FocusTask: Codable, Identifiable, Equatable {
    public var id = UUID().uuidString
    public var title: String
    public var nextStep: String
    public var day: String
    public var completed = false
    public var subtasks: [FocusSubtask]?
    public var completedAt: Double?
}
public struct Allowance: Codable, Equatable {
    public var site: String
    public var startAt: Double
    public var endAt: Double
    public var reason: String
}
public struct Session: Codable, Identifiable, Equatable {
    public var id = UUID().uuidString
    public var taskID: String
    public var title: String
    public var nextStep: String
    public var startAt: Double
    public var endAt: Double
    public var allowances: [Allowance] = []
    public var subtaskID: String?
    public var subtaskTitle: String?
}
public struct PendingRequest: Codable, Equatable {
    public var id = UUID().uuidString
    public var sessionID: String
    public var kind: String
    public var site: String?
    public var readyAt: Double
    public var reason: String
}
public struct FocusRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var taskID: String
    public var title: String
    public var startAt: Double
    public var endAt: Double
    public var focusSeconds: Double
    public var finished: Bool
    public var accessCount: Int
    public var subtaskID: String?
    public var subtaskTitle: String?
}
public struct Command: Codable {
    public var action: String
    public var taskID: String?
    public var title: String?
    public var nextStep: String?
    public var minutes: Int?
    public var site: String?
    public var requestID: String?
    public var reason: String?
    public var protocolVersion: Int?
    public var subtaskID: String?
    public var subtaskTitles: [String]?
    public var expectedTaskVersion: String?
    public init(_ action: String, taskID: String? = nil, title: String? = nil, nextStep: String? = nil, minutes: Int? = nil, site: String? = nil, requestID: String? = nil, reason: String? = nil, protocolVersion: Int? = nil, subtaskID: String? = nil, subtaskTitles: [String]? = nil, expectedTaskVersion: String? = nil) {
        self.action = action; self.taskID = taskID; self.title = title; self.nextStep = nextStep
        self.minutes = minutes; self.site = site; self.requestID = requestID; self.reason = reason
        self.protocolVersion = protocolVersion
        self.subtaskID = subtaskID; self.subtaskTitles = subtaskTitles; self.expectedTaskVersion = expectedTaskVersion
    }
}
public struct FocusError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public struct FocusState: Codable {
    public var schema = 4
    public var tasks: [FocusTask] = []
    public var session: Session?
    public var history: [FocusRecord] = []
    public var pending: PendingRequest?
    public var breakUntil: Double?
    public var lastExtensionSeen: Double?
    public var extensionError: String?
    public var extensionProtocol: Int?
    public var blockedSites: [BlockedSite]?
    public var inboxItems: [InboxItem]?
    public init() {}
    public var effectiveBlockedSites: [BlockedSite] { blockedSites ?? BlockedSite.defaults }
    public func canonicalBlockedSite(_ value: String) -> String? {
        guard let host = try? BlockedSite.normalizedDomain(value) else { return nil }
        return BlockedSite.matching(host, in: effectiveBlockedSites)
    }

    public static func day(at time: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: time))
    }
    public static func canonicalSite(_ value: String) -> String? {
        switch value { case "x.com", "twitter.com": return "x.com"
        case "weibo.com", "weibo.cn": return "weibo.com"
        case "xueqiu.com": return "xueqiu.com"
        default: return nil }
    }
    public mutating func tick(now: Double) {
        if let s = session, now >= s.endAt { finish(at: s.endAt, finished: true) }
        if let end = breakUntil, now >= end { breakUntil = nil }
    }
    private mutating func finish(at end: Double, finished: Bool) {
        guard let s = session else { return }
        // Merge overlaps: two temporarily open websites still represent one interval away.
        let intervals = s.allowances.map { (max(s.startAt, $0.startAt), min(end, $0.endAt)) }
            .filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var away = 0.0; var right = s.startAt
        for (a, b) in intervals { away += max(0, b - max(right, a)); right = max(right, b) }
        history.insert(FocusRecord(id: s.id, taskID: s.taskID, title: s.title, startAt: s.startAt,
            endAt: end, focusSeconds: max(0, end - s.startAt - away), finished: finished, accessCount: s.allowances.count,
            subtaskID: s.subtaskID, subtaskTitle: s.subtaskTitle), at: 0)
        session = nil; pending = nil
    }
    public mutating func apply(_ c: Command, now: Double) throws {
        guard now.isFinite else { throw FocusError("时间无效") }
        tick(now: now)
        func text(_ value: String?, maxLength: Int = 120) -> String {
            String((value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        }
        func index() throws -> Int {
            guard let i = tasks.firstIndex(where: { $0.id == c.taskID }) else { throw FocusError("任务不存在") }
            return i
        }
        switch c.action {
        case "getState": break
        case "appendSubtasks", "editSubtask", "deleteSubtask", "completeSubtask": try applySubtasks(c, now: now)
        case "addInbox", "editInbox", "deleteInbox", "restoreInbox", "moveInboxToday": try applyInbox(c, now: now)
        case "heartbeat": lastExtensionSeen = now; extensionError = c.reason?.isEmpty == false ? c.reason : nil; extensionProtocol = c.protocolVersion
        case "addBlockedSite", "removeBlockedSite":
            guard session == nil else { throw FocusError("这一轮结束后再修改屏蔽网站；临时访问仍需等待 30 秒") }
            let domain = try BlockedSite.normalizedDomain(c.site ?? "")
            var sites = effectiveBlockedSites
            if c.action == "addBlockedSite" {
                if let existing = sites.first(where: { $0.domains.contains(where: { BlockedSite.overlaps($0, domain) }) }) {
                    throw FocusError("与已有网站 \(existing.site) 的范围重叠，无需重复添加；如需扩大范围，请先移除原项")
                }
                guard sites.count < 100 else { throw FocusError("最多可设置 100 个网站") }
                sites.append(BlockedSite(site: domain, name: domain, domains: [domain]))
            } else {
                guard sites.contains(where: { $0.site == domain }) else { throw FocusError("这个网站不在屏蔽列表中") }
                sites.removeAll { $0.site == domain }
            }
            blockedSites = sites
        case "addTask":
            let title = text(c.title); guard !title.isEmpty else { throw FocusError("先写下你想做的事") }
            tasks.append(FocusTask(title: title, nextStep: text(c.nextStep, maxLength: 180), day: Self.day(at: now)))
        case "editTask", "completeTask", "deleteTask", "moveToday":
            let i = try index()
            guard session?.taskID != tasks[i].id else { throw FocusError("请等这一轮结束后再修改任务") }
            if c.action == "editTask" {
                let title = text(c.title); guard !title.isEmpty else { throw FocusError("任务名称不能为空") }
                tasks[i].title = title; tasks[i].nextStep = text(c.nextStep, maxLength: 180)
            } else if c.action == "completeTask" { tasks[i].completed.toggle(); tasks[i].completedAt = tasks[i].completed ? now : nil }
            else if c.action == "moveToday" { tasks[i].day = Self.day(at: now); tasks[i].completed = false; tasks[i].completedAt = nil }
            else { tasks.remove(at: i) }
        case "start":
            guard session == nil else { throw FocusError("先完成当前这一轮") }
            let i = try index()
            guard !tasks[i].completed else { throw FocusError("这件事已经完成了") }
            guard let minutes = c.minutes, [15,25,30,45].contains(minutes) else { throw FocusError("请选择 15、25、30 或 45 分钟") }
            let subtask = tasks[i].steps.first(where: { $0.id == c.subtaskID })
            if c.subtaskID != nil || !tasks[i].steps.isEmpty {
                guard let subtask, !subtask.completed else { throw FocusError("请先选中一个未完成的小任务") }
            }
            tasks[i].day = Self.day(at: now)
            session = Session(taskID: tasks[i].id, title: tasks[i].title, nextStep: tasks[i].nextStep,
                              startAt: now, endAt: now + Double(minutes * 60), subtaskID: subtask?.id, subtaskTitle: subtask?.title)
            breakUntil = nil; pending = nil
        case "requestAccess", "requestEnd":
            guard let s = session else { throw FocusError("当前没有正在进行的专注") }
            let site = canonicalBlockedSite(c.site ?? "")
            if c.action == "requestAccess" && site == nil { throw FocusError("这个网站不在限制名单里") }
            let kind = c.action == "requestEnd" ? "end" : "access"
            if let existing = pending, existing.kind == kind, existing.site == site { return }
            pending = PendingRequest(sessionID: s.id, kind: kind, site: site, readyAt: now + 30,
                                     reason: text(c.reason, maxLength: 240))
        case "confirmAccess", "confirmEnd":
            guard let s = session, let p = pending, p.id == c.requestID, p.sessionID == s.id,
                  p.kind == (c.action == "confirmEnd" ? "end" : "access") else { throw FocusError("这次请求已过期，请重新操作") }
            guard now >= p.readyAt else { throw FocusError("请等 30 秒结束后再确认") }
            if c.action == "confirmEnd" { finish(at: now, finished: false) }
            else {
                guard let site = p.site else { throw FocusError("缺少网站") }
                session?.allowances.append(Allowance(site: site, startAt: now, endAt: min(now + 300, s.endAt), reason: p.reason))
                pending = nil
            }
        case "cancelRequest": pending = nil
        case "startBreak":
            guard session == nil else { throw FocusError("专注结束后再休息") }; breakUntil = now + 300
        case "endBreak": breakUntil = nil
        default: throw FocusError("不支持的操作")
        }
    }

}
