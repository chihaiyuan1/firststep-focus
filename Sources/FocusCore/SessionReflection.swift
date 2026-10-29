import Foundation
import Darwin

public struct SessionReflection: Codable, Equatable, Identifiable {
    public static let maxTextLength = 8000
    public var recordID: String
    public var text: String
    public var draft: String?
    public var updatedAt: Double
    public var savedAt: Double?
    public var dismissedAt: Double?
    public var id: String { recordID }
    public var editorText: String { draft ?? text }

    public init(recordID: String, text: String = "", draft: String? = nil,
                updatedAt: Double = Date().timeIntervalSince1970,
                savedAt: Double? = nil, dismissedAt: Double? = nil) {
        self.recordID = recordID
        self.text = text
        self.draft = draft
        self.updatedAt = updatedAt
        self.savedAt = savedAt
        self.dismissedAt = dismissedAt
    }
}

private struct SessionReflectionDocument: Codable {
    var schema: Int = 1
    var reflections: [SessionReflection] = []
}

private struct SessionReflectionError: LocalizedError {
    var errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

public final class SessionReflectionStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func read() throws -> [SessionReflection] { try transaction(nil) }

    public func save(recordID: String, text: String, now: Double = Date().timeIntervalSince1970) throws -> [SessionReflection] {
        try Self.validateText(text)
        return try update(recordID: recordID, now: now) { reflection in
            reflection.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            reflection.draft = nil
            reflection.savedAt = now
        }
    }

    public func saveDraft(recordID: String, text: String, now: Double = Date().timeIntervalSince1970) throws -> [SessionReflection] {
        try Self.validateText(text)
        return try update(recordID: recordID, now: now) { $0.draft = text }
    }

    public func dismiss(recordID: String, now: Double = Date().timeIntervalSince1970) throws -> [SessionReflection] {
        try update(recordID: recordID, now: now) { $0.dismissedAt = now }
    }

    private static func validateID(_ recordID: String) throws {
        guard !recordID.isEmpty && recordID.count <= 100 else {
            throw SessionReflectionError("专注记录标识无效")
        }
    }

    private static func validateText(_ text: String) throws {
        guard text.count <= SessionReflection.maxTextLength else {
            throw SessionReflectionError("本轮想法最多可输入\(SessionReflection.maxTextLength)个字")
        }
    }

    private static func validate(_ reflections: [SessionReflection]) throws {
        var identifiers = Set<String>()
        for reflection in reflections {
            try validateID(reflection.recordID)
            try validateText(reflection.text)
            if let draft = reflection.draft { try validateText(draft) }
            guard reflection.updatedAt.isFinite,
                  reflection.savedAt?.isFinite != false,
                  reflection.dismissedAt?.isFinite != false,
                  identifiers.insert(reflection.recordID).inserted else {
                throw SessionReflectionError("本轮想法包含无效时间或重复记录")
            }
        }
    }

    private func update(recordID: String, now: Double, _ change: @escaping (inout SessionReflection) -> Void) throws -> [SessionReflection] {
        try Self.validateID(recordID)
        guard now.isFinite else { throw SessionReflectionError("本轮想法的时间无效") }
        return try transaction { reflections in
            if let index = reflections.firstIndex(where: { $0.recordID == recordID }) {
                change(&reflections[index])
                reflections[index].updatedAt = now
            } else {
                var reflection = SessionReflection(recordID: recordID, updatedAt: now)
                change(&reflection)
                reflections.append(reflection)
            }
        }
    }

    private func transaction(_ change: ((inout [SessionReflection]) throws -> Void)?) throws -> [SessionReflection] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let lockURL = directory.appendingPathComponent("focus-reflections.lock")
        let lockFD = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0 else { throw SessionReflectionError("无法打开本轮想法数据锁") }
        defer { close(lockFD) }
        guard fchmod(lockFD, 0o600) == 0, flock(lockFD, LOCK_EX) == 0 else {
            throw SessionReflectionError("无法锁定本轮想法数据")
        }
        defer { flock(lockFD, LOCK_UN) }

        let file = directory.appendingPathComponent("focus-reflections.json")
        var document = SessionReflectionDocument()
        if fm.fileExists(atPath: file.path) {
            do {
                document = try JSONDecoder().decode(SessionReflectionDocument.self, from: Data(contentsOf: file))
                try Self.validate(document.reflections)
            } catch {
                throw SessionReflectionError("本轮想法无法读取，已保留原文件：\(file.path)")
            }
            guard document.schema == 1 else { throw SessionReflectionError("本轮想法来自其他版本，请先升级工具") }
        }
        if let change {
            try change(&document.reflections)
            try Self.validate(document.reflections)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try atomicWrite(encoder.encode(document), to: file)
        }
        return document.reflections
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        let temporary = directory.appendingPathComponent(".focus-reflections-\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SessionReflectionError("无法建立本轮想法临时文件") }
        defer {
            close(fd)
            unlink(temporary.path)
        }
        guard fchmod(fd, 0o600) == 0 else { throw SessionReflectionError("无法保护本轮想法文件") }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SessionReflectionError("本轮想法写入失败，原文件未改动") }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw SessionReflectionError("本轮想法写入失败，原文件未改动") }
        guard rename(temporary.path, destination.path) == 0 else {
            throw SessionReflectionError("无法保存本轮想法，原文件未改动")
        }
    }
}
