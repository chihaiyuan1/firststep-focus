import Foundation

public struct AIMessage: Codable, Sendable {
    public var role: String
    public var content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}
public struct ChatGPTAccount: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let isAuthorized: Bool
}
public struct ChatGPTModel: Identifiable, Sendable {
    public let id: String
    public let name: String
    static func decodeCatalog(_ data: Data) throws -> [ChatGPTModel] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let models = root["models"] as? [[String: Any]] else { throw ChatGPTError.invalidResponse }
        var seen = Set<String>()
        let result = models.compactMap { item -> ChatGPTModel? in
            guard item["visibility"] as? String == "list", let id = item["slug"] as? String, !id.isEmpty,
                  let name = item["display_name"] as? String, !name.isEmpty, seen.insert(id).inserted else { return nil }
            return ChatGPTModel(id: id, name: name)
        }
        guard !result.isEmpty else { throw ChatGPTError.noModels }
        return result
    }
}
public enum ChatGPTError: Error, LocalizedError, Sendable {
    case unauthorized, permissionMissing, usageLimit, usageUnavailable, network, cancelled, invalidResponse
    case incompleteResponse, emptyResponse, signInRequired, invalidCallback, invalidIdentity, signInBusy, signInExpired
    case credentialStorage, noModels, server, remoteRevocationUnconfirmed, refreshNotReady
    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "ChatGPT 授权已失效，请重新连接此账号。"
        case .permissionMissing: return "此账号尚未允许使用 ChatGPT 套餐，请重新授权并允许套餐使用。"
        case .usageLimit: return "ChatGPT 套餐额度已用完，请稍后再试或在 ChatGPT 设置中查看用量。"
        case .usageUnavailable: return "ChatGPT 套餐当前不可用，请在 ChatGPT 设置中检查此应用的使用权限。"
        case .network: return "无法连接 ChatGPT，请检查网络后重试。"
        case .cancelled: return "已取消。"
        case .invalidResponse: return "ChatGPT 返回的内容格式无法识别，请重试。"
        case .incompleteResponse: return "ChatGPT 回复中断或未完成，请重新生成。"
        case .emptyResponse: return "ChatGPT 没有返回可用文字，请重试。"
        case .signInRequired: return "请先连接 ChatGPT 账号。"
        case .invalidCallback: return "授权回调校验失败，请重新发起连接。"
        case .invalidIdentity: return "ChatGPT 身份校验失败，已保留原账号，请重新连接。"
        case .signInBusy: return "已有 ChatGPT 授权正在进行，请先完成或取消。"
        case .signInExpired: return "授权等待已超时，请重新连接。"
        case .credentialStorage: return "无法安全读取或保存本机 ChatGPT 凭据，请检查应用数据目录权限。"
        case .noModels: return "此 ChatGPT 账号当前没有可选模型。"
        case .server: return "ChatGPT 服务暂时无法完成请求，请稍后重试。"
        case .remoteRevocationUnconfirmed: return "本机已退出，但未能确认远程撤销。可在 ChatGPT 设置中断开此应用。"
        case .refreshNotReady: return "ChatGPT 授权暂时不能续期，请稍后重试。"
        }
    }
    static func response(status: Int, data: Data = Data()) -> ChatGPTError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let nested = json?["error"] as? [String: Any]
        let code = nested?["code"] as? String ?? json?["error"] as? String ?? json?["code"] as? String
        return fromCode(code, status: status)
    }
    static func fromCode(_ code: String?, status: Int = 0) -> ChatGPTError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return .usageLimit
        case "subscription_sharing_usage_unavailable": return .usageUnavailable
        case "invalid_grant", "invalid_token", "token_expired", "invalid_client": return .unauthorized
        case "insufficient_scope", "access_denied": return .permissionMissing
        case "refresh_token_not_ready", "refresh_too_early": return .refreshNotReady
        default:
            switch status { case 401: return .unauthorized; case 403: return .permissionMissing; case 429: return .usageLimit; default: return .server }
        }
    }
    static func sanitized(_ error: Error) -> Error {
        if let known = error as? ChatGPTError { return known }
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return ChatGPTError.cancelled }
        return ChatGPTError.network
    }
}

extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter
    }
    static func parse(_ value: String) -> Date? { fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
}
