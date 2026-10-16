import Foundation
import Darwin

private struct TimeLogDocument: Codable {
    var schema = 1
    var entries: [TimeEntry] = []
}
public final class TimeLogStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func read() throws -> [TimeEntry] { try transaction(nil) }
    public func upsert(_ entry: TimeEntry) throws -> [TimeEntry] {
        try entry.validate()
        return try transaction { entries in
            if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = entry }
            else { entries.append(entry) }
        }
    }
    public func remove(id: String) throws -> [TimeEntry] {
        try transaction { entries in
            guard let i = entries.firstIndex(where: { $0.id == id }) else { throw FocusError("记录已不存在") }
            entries[i].deletedAt = Date().timeIntervalSince1970
        }
    }
    public func restore(id: String) throws -> [TimeEntry] {
        try transaction { entries in
            guard let i = entries.firstIndex(where: { $0.id == id }) else { throw FocusError("记录已不存在") }
            entries[i].deletedAt = nil
        }
    }
    private func transaction(_ change: ((inout [TimeEntry]) throws -> Void)?) throws -> [TimeEntry] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("time-records.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw FocusError("无法打开时间记录锁") }; defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw FocusError("无法锁定时间记录") }; defer { flock(fd, LOCK_UN) }
        let file = directory.appendingPathComponent("time-records.json")
        var document = TimeLogDocument()
        if fm.fileExists(atPath: file.path) {
            do { document = try JSONDecoder().decode(TimeLogDocument.self, from: Data(contentsOf: file)); try document.entries.forEach { try $0.validate() } }
            catch { throw FocusError("时间记录无法读取，已保留原文件：\(file.path)") }
            guard document.schema == 1 else { throw FocusError("时间记录版本不兼容，请先升级") }
        }
        if let change {
            try change(&document.entries)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(document).write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        return document.entries
    }
}
