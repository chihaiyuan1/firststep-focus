import Foundation
import CryptoKit
import Darwin

struct CredentialRecord: Codable, Sendable {
    var email: String?
    var issuer: String
    var subject: String
    var clientID: String
    var hostID: String
    var idToken: String?
    var accessToken: String?
    var refreshToken: String?
    var tokenType: String?
    var expiresIn: Double?
    var scope: String?
    var scopes: [String]?
    var savedAt: String?
    var earliestRefreshAt: RefreshDate?
    enum CodingKeys: String, CodingKey {
        case email, issuer, subject, scope, scopes
        case clientID = "client_id", hostID = "ext_agent_host_id", idToken = "id_token", accessToken = "access_token", refreshToken = "refresh_token", tokenType = "token_type", expiresIn = "expires_in", savedAt = "saved_at", earliestRefreshAt = "earliest_refresh_at"
    }
    var grantedScopes: Set<String> { Set(scope?.split(separator: " ").map(String.init) ?? scopes ?? []) }
    var authorized: Bool { !(accessToken ?? "").isEmpty && tokenType?.lowercased() == "bearer" && grantedScopes.contains("chatgpt.tokens.use.direct") && grantedScopes.contains("resource.invoke") }
    var expiresAt: Date? { guard let savedAt, let saved = ISO8601DateFormatter.parse(savedAt), let expiresIn else { return nil }; return saved.addingTimeInterval(expiresIn) }
    mutating func clearTokens() { idToken = nil; accessToken = nil; refreshToken = nil; savedAt = nil; expiresIn = nil; earliestRefreshAt = nil; scope = nil; scopes = nil; tokenType = nil }
    func account(id: String) -> ChatGPTAccount { ChatGPTAccount(id: id, label: "\(email?.isEmpty == false ? email! : "ChatGPT 账号") · \(id.suffix(6))", isAuthorized: authorized) }
    var stableID: String { "account-" + SHA256.hash(data: Data("\(issuer)\u{0}\(subject)\u{0}\(clientID)".utf8)).prefix(12).map { String(format:"%02x", $0) }.joined() }
    func validate() throws {
        guard issuer == OAuthSupport.issuer, !subject.isEmpty, !clientID.isEmpty, clientID != "dynamic_agent_client", !hostID.isEmpty else { throw ChatGPTError.credentialStorage }
    }
}
struct RefreshDate: Codable, Sendable {
    let date: Date
    init(date: Date) { self.date = date }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { date = Date(timeIntervalSince1970: number); return }
        guard let value = try? container.decode(String.self), let parsed = ISO8601DateFormatter.parse(value) else { throw ChatGPTError.invalidResponse }
        date = parsed
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(date.timeIntervalSince1970) }
}
struct CredentialStore: Sendable {
    let directory: URL
    init(directory: URL) throws {
        self.directory = directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
            var info = stat(); guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid(), chmod(directory.path, 0o700) == 0 else { throw ChatGPTError.credentialStorage }
        } catch { throw ChatGPTError.credentialStorage }
    }
    private func valid(_ id: String) -> Bool { id.range(of: "^account-[0-9a-f]{24}$", options: .regularExpression) != nil }
    func read(_ id: String) throws -> CredentialRecord {
        guard valid(id) else { throw ChatGPTError.credentialStorage }
        do { let value = try JSONDecoder().decode(CredentialRecord.self, from: readFile(id + ".json")); try value.validate(); return value }
        catch { throw ChatGPTError.credentialStorage }
    }
    func accounts() throws -> [ChatGPTAccount] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") && valid(String($0.dropLast(5))) }.sorted().map { file in
                let id = String(file.dropLast(5)); return try read(id).account(id: id)
            }
        } catch { throw ChatGPTError.credentialStorage }
    }
    func save(_ value: CredentialRecord, id: String) throws {
        guard valid(id) else { throw ChatGPTError.credentialStorage }
        try value.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeFile(try encoder.encode(value), name: id + ".json")
    }
    func hostID() throws -> String {
        let url = directory.appendingPathComponent("host.json")
        if FileManager.default.fileExists(atPath: url.path) {
            guard let object = try JSONSerialization.jsonObject(with: readFile("host.json")) as? [String: Any], let host = object["ext_agent_host_id"] as? String, !host.isEmpty else { throw ChatGPTError.credentialStorage }
            return host
        }
        // Reuse imported credentials' host rather than rotating an existing installation identity.
        let records = try accounts()
        let host = try records.first.map { try read($0.id).hostID } ?? "urn:uuid:" + UUID().uuidString.lowercased()
        try writeFile(JSONSerialization.data(withJSONObject:["ext_agent_host_id":host]), name:"host.json")
        return host
    }
    func readFile(_ name: String) throws -> Data {
        let fd = open(directory.appendingPathComponent(name).path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ChatGPTError.credentialStorage }; defer { close(fd) }
        var info = stat(); guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= 1_048_576, fchmod(fd, 0o600) == 0 else { throw ChatGPTError.credentialStorage }
        var result = Data(); var buffer = [UInt8](repeating:0, count:8192)
        while true { let count = Darwin.read(fd, &buffer, buffer.count); if count == 0 { return result }; if count < 0 { if errno == EINTR { continue }; throw ChatGPTError.credentialStorage }; result.append(contentsOf:buffer.prefix(count)); guard result.count <= 1_048_576 else { throw ChatGPTError.credentialStorage } }
    }
    func writeFile(_ data: Data, name: String) throws {
        let temporary = directory.appendingPathComponent(".credential-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ChatGPTError.credentialStorage }
        defer { close(fd); unlink(temporary.path) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < data.count { let count = Darwin.write(fd, buffer.baseAddress!.advanced(by:offset), data.count - offset); if count < 0 { if errno == EINTR { continue }; throw ChatGPTError.credentialStorage }; offset += count }
        }
        guard fsync(fd) == 0, rename(temporary.path, directory.appendingPathComponent(name).path) == 0 else { throw ChatGPTError.credentialStorage }
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC); if directoryFD >= 0 { _ = fsync(directoryFD); close(directoryFD) }
    }
    func lock() async throws -> CredentialLock {
        let fd = open(directory.appendingPathComponent(".credentials.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ChatGPTError.credentialStorage }
        var info = stat(); guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG, fchmod(fd, 0o600) == 0 else { close(fd); throw ChatGPTError.credentialStorage }
        do {
            while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                guard errno == EWOULDBLOCK || errno == EINTR else { throw ChatGPTError.credentialStorage }
                try await Task.sleep(nanoseconds:50_000_000)
            }
            try Task.checkCancellation()
            return CredentialLock(fd:fd)
        } catch { close(fd); throw error }
    }
}
final class CredentialLock: @unchecked Sendable {
    private let fd: Int32
    init(fd: Int32) { self.fd = fd }
    deinit { flock(fd, LOCK_UN); close(fd) }
}
