import Foundation

public struct BlockedSite: Codable, Identifiable, Equatable {
    public var site: String
    public var name: String
    public var domains: [String]
    public var id: String { site }

    public static let defaults: [BlockedSite] = [
        BlockedSite(site: "xueqiu.com", name: "雪球", domains: ["xueqiu.com"]),
        BlockedSite(site: "x.com", name: "X", domains: ["x.com", "twitter.com"]),
        BlockedSite(site: "weibo.com", name: "微博", domains: ["weibo.com", "weibo.cn"])
    ]
    public static func normalizedDomain(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 4096, !value.contains("\\"),
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: value.contains("://") ? value : "https://" + value),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil,
              parts.port == nil || (1...65535).contains(parts.port!),
              var host = parts.url?.host?.lowercased() else { throw FocusError("请粘贴有效的 http/https 网址或网站域名") }
        if host.hasSuffix(".") { host.removeLast() }
        while host.hasPrefix("www.") { host.removeFirst(4) }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard host.utf8.count <= 253, labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              labels.last!.contains(where: { $0.isLetter }) else { throw FocusError("请输入网站域名，例如 bilibili.com；不支持本机地址或 IP") }
        return host
    }
    public static func matching(_ host: String, in sites: [BlockedSite]) -> String? {
        sites.first { $0.domains.contains { host == $0 || host.hasSuffix("." + $0) } }?.site
    }
    public static func overlaps(_ a: String, _ b: String) -> Bool { a == b || a.hasSuffix("." + b) || b.hasSuffix("." + a) }
    public static func validate(_ sites: [BlockedSite]) throws {
        guard sites.count <= 100 else { throw FocusError("最多可设置 100 个网站") }
        var domains: [String] = []
        for entry in sites {
            guard try normalizedDomain(entry.site) == entry.site,
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, entry.name.count <= 253,
                  !entry.domains.isEmpty, entry.domains.count <= 5, entry.domains.contains(entry.site) else { throw FocusError("屏蔽网站设置无效") }
            for domain in entry.domains {
                guard try normalizedDomain(domain) == domain, !domains.contains(where: { overlaps($0, domain) }) else { throw FocusError("屏蔽网站存在重复或重叠的域名") }
                domains.append(domain)
            }
        }
    }
}
