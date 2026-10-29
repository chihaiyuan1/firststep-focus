import Foundation
import Darwin

/// Locally synthesized PCM. Pure sine partials and a long envelope avoid a sharp bell strike.
public enum CompletionChime {
    public static let duration: Double = 2.5
    public static func wavData() -> Data {
        let sampleRate = 44_100
        let frameCount = Int(duration * Double(sampleRate))
        let pcmBytes = frameCount * 2
        var data = Data(capacity: 44 + pcmBytes)
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); append32(UInt32(36 + pcmBytes))
        data.append(contentsOf: "WAVEfmt ".utf8); append32(16)
        append16(1); append16(1); append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2)); append16(2); append16(16)
        data.append(contentsOf: "data".utf8); append32(UInt32(pcmBytes))

        // C5/E5/G5, with quieter upper notes and no metallic upper harmonics.
        let notes: [(frequency: Double, weight: Double)] = [
            (523.251, 0.58), (659.255, 0.27), (783.991, 0.15)
        ]
        for frame in 0..<frameCount {
            let time = Double(frame) / Double(sampleRate)
            let remaining = Double(frameCount - 1 - frame) / Double(sampleRate)
            let attack = sin(min(1, time / 0.18) * .pi / 2)
            let release = sin(min(1, remaining / 0.65) * .pi / 2)
            let envelope = attack * attack * release * release * exp(-0.85 * time)
            let tone = notes.reduce(0.0) { sum, note in
                sum + note.weight * sin(2 * .pi * note.frequency * time)
            }
            let value = Int16((0.28 * envelope * tone * Double(Int16.max)).rounded())
            append16(UInt16(bitPattern: value))
        }
        return data
    }
}

private struct CompletionReminderDocument: Codable {
    var schema = 1
    var soundEnabled = true
}

private struct CompletionReminderSchema: Decodable { let schema: Int }
private struct CompletionReminderStoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Independent of the shared timer state and native bridge; it never creates a JSON on read.
public final class CompletionReminderPreferencesStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func read() throws -> Bool { try transaction(nil) }
    @discardableResult public func setSoundEnabled(_ enabled: Bool) throws -> Bool { try transaction(enabled) }

    private func transaction(_ enabled: Bool?) throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = directory.appendingPathComponent("completion-reminders.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw failure("无法打开结束铃声设置锁") }
        defer { close(descriptor) }
        guard fchmod(descriptor, 0o600) == 0, flock(descriptor, LOCK_EX) == 0 else {
            throw failure("无法锁定结束铃声设置")
        }
        defer { flock(descriptor, LOCK_UN) }

        let file = directory.appendingPathComponent("completion-reminders.json")
        var document = CompletionReminderDocument()
        var status = stat()
        if lstat(file.path, &status) == 0 {
            guard status.st_mode & S_IFMT == S_IFREG else {
                throw failure("结束铃声设置不是普通文件，已保留原文件：\(file.path)")
            }
            let bytes: Data
            let version: Int
            do {
                bytes = try Data(contentsOf: file)
                version = try JSONDecoder().decode(CompletionReminderSchema.self, from: bytes).schema
            } catch { throw failure("结束铃声设置无法读取，已保留原文件：\(file.path)") }
            guard version == 1 else { throw failure("结束铃声设置版本不兼容，已保留原文件，请先升级应用。") }
            do { document = try JSONDecoder().decode(CompletionReminderDocument.self, from: bytes) }
            catch { throw failure("结束铃声设置无法读取，已保留原文件：\(file.path)") }
        } else if errno != ENOENT {
            throw failure("无法读取结束铃声设置，已保留原文件：\(file.path)")
        }
        if let enabled {
            document.soundEnabled = enabled
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try atomicWrite(encoder.encode(document), to: file)
        }
        return document.soundEnabled
    }

    /// Create the replacement with 0600 before writing, then rename under the same file lock.
    private func atomicWrite(_ data: Data, to file: URL) throws {
        let temporary = directory.appendingPathComponent(".completion-reminders-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw failure("无法保存结束铃声设置") }
        defer { close(descriptor); unlink(temporary.path) }
        guard fchmod(descriptor, 0o600) == 0 else { throw failure("无法保护结束铃声设置文件") }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: written), bytes.count - written)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw failure("无法完整保存结束铃声设置") }
                written += count
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, file.path) == 0 else {
            throw failure("无法完成结束铃声设置保存，原设置已保留。")
        }
    }

    private func failure(_ message: String) -> CompletionReminderStoreError {
        CompletionReminderStoreError(message: message)
    }
}
