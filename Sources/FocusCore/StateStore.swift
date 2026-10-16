import Foundation
import Darwin

public final class StateStore {
    public let directory: URL
    public init(directory: URL? = nil) {
        if let directory { self.directory = directory }
        else if let override = ProcessInfo.processInfo.environment["FIRSTSTEP_DATA_DIR"] { self.directory = URL(fileURLWithPath: override) }
        else { self.directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FirstStep") }
    }
    public func transact(command: Command? = nil, now: Double = Date().timeIntervalSince1970) throws -> FocusState {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = directory.appendingPathComponent("state.lock")
        let fd = open(lock.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw FocusError("无法打开数据锁") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw FocusError("无法锁定数据") }
        defer { flock(fd, LOCK_UN) }
        let url = directory.appendingPathComponent("state.json")
        var state: FocusState
        if fm.fileExists(atPath: url.path) {
            do { state = try JSONDecoder().decode(FocusState.self, from: Data(contentsOf: url)) }
            catch { throw FocusError("本地数据无法读取，已保留原文件：\(url.path)") }
            guard [1, 2, 3].contains(state.schema) else { throw FocusError("数据来自其他版本，请先升级工具") }
        } else { state = FocusState() }
        try BlockedSite.validate(state.effectiveBlockedSites)
        try InboxItem.validate(state.inboxItems ?? [])
        state.schema = 3
        state.tick(now: now)
        if let command { try state.apply(command, now: now) }
        try BlockedSite.validate(state.effectiveBlockedSites)
        try InboxItem.validate(state.inboxItems ?? [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        if (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return state
    }
}
