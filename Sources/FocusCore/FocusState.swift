import Foundation

public struct FocusTask: Codable, Identifiable, Equatable {
    public var id = UUID().uuidString
    public var title: String
    public var nextStep: String
    public var day: String
    public var completed = false
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
    public init(_ action: String, taskID: String? = nil, title: String? = nil, nextStep: String? = nil, minutes: Int? = nil, site: String? = nil, requestID: String? = nil, reason: String? = nil) {
        self.action = action; self.taskID = taskID; self.title = title; self.nextStep = nextStep
        self.minutes = minutes; self.site = site; self.requestID = requestID; self.reason = reason
    }
}
public struct FocusError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public struct FocusState: Codable {
    public var schema = 1
    public var tasks: [FocusTask] = []
    public var session: Session?
    public var history: [FocusRecord] = []
    public var pending: PendingRequest?
    public var breakUntil: Double?
    public var lastExtensionSeen: Double?
    public var extensionError: String?
    public init() {}

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
            endAt: end, focusSeconds: max(0, end - s.startAt - away), finished: finished, accessCount: s.allowances.count), at: 0)
        history = Array(history.prefix(500)); session = nil; pending = nil
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
        case "heartbeat": lastExtensionSeen = now; extensionError = c.reason?.isEmpty == false ? c.reason : nil
        case "addTask":
            let title = text(c.title); guard !title.isEmpty else { throw FocusError("先写下你想做的事") }
            tasks.append(FocusTask(title: title, nextStep: text(c.nextStep, maxLength: 180), day: Self.day(at: now)))
        case "editTask", "completeTask", "deleteTask", "moveToday":
            let i = try index()
            guard session?.taskID != tasks[i].id else { throw FocusError("请等这一轮结束后再修改任务") }
            if c.action == "editTask" {
                let title = text(c.title); guard !title.isEmpty else { throw FocusError("任务名称不能为空") }
                tasks[i].title = title; tasks[i].nextStep = text(c.nextStep, maxLength: 180)
            } else if c.action == "completeTask" { tasks[i].completed.toggle() }
            else if c.action == "moveToday" { tasks[i].day = Self.day(at: now); tasks[i].completed = false }
            else { tasks.remove(at: i) }
        case "start":
            guard session == nil else { throw FocusError("先完成当前这一轮") }
            let i = try index()
            guard !tasks[i].completed else { throw FocusError("这件事已经完成了") }
            guard let minutes = c.minutes, [15,25,30,45].contains(minutes) else { throw FocusError("请选择 15、25、30 或 45 分钟") }
            tasks[i].day = Self.day(at: now)
            session = Session(taskID: tasks[i].id, title: tasks[i].title, nextStep: tasks[i].nextStep,
                              startAt: now, endAt: now + Double(minutes * 60))
            breakUntil = nil; pending = nil
        case "requestAccess", "requestEnd":
            guard let s = session else { throw FocusError("当前没有正在进行的专注") }
            let site = Self.canonicalSite(c.site ?? "")
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
