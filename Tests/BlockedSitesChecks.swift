import Foundation

func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
func rejects(_ body: () throws -> Void) { do { try body(); fatalError("Expected rejection") } catch {} }

@main struct BlockedSitesChecks {
    static func main() throws {
        for (input, expected) in [
            (" https://www.BILIBILI.com/video/a?token=secret#x ", "bilibili.com"),
            ("https://www.www.example.com/a", "example.com"),
            ("example.com/path", "example.com"), ("news.example.com:8080/a", "news.example.com"),
            ("https://例子.中国/a", "xn--fsqu00a.xn--fiqs8s"), ("https://example.com./", "example.com")
        ] { check(try BlockedSite.normalizedDomain(input) == expected, "Normalization: \(input)") }
        for input in ["", "chrome://extensions", "ftp://example.com", "https://user:pass@example.com", "https://foo..com", "https://-bad.com", "localhost", "127.0.0.1", "[::1]", "https://example.com:99999", "https://bad domain.com", "com", "https://example.com\\@evil.com"] {
            rejects { _ = try BlockedSite.normalizedDomain(input) }
        }
        var state = FocusState()
        check(state.effectiveBlockedSites.count == 3, "Default groups")
        try state.apply(Command("addBlockedSite", site: "https://www.bilibili.com/video/a"), now: 1000)
        check(state.effectiveBlockedSites.last?.site == "bilibili.com", "Custom domain saved")
        check(state.canonicalBlockedSite("live.bilibili.com") == "bilibili.com", "Subdomain match")
        check(state.canonicalBlockedSite("bilibili.com.evil.com") == nil, "Suffix boundary")
        check(state.canonicalBlockedSite("mobile.twitter.com") == "x.com", "Default alias")
        rejects { try state.apply(Command("addBlockedSite", site: "bilibili.com"), now: 1000) }
        rejects { try state.apply(Command("addBlockedSite", site: "m.bilibili.com"), now: 1000) }
        try state.apply(Command("addBlockedSite", site: "news.example.com"), now: 1000)
        rejects { try state.apply(Command("addBlockedSite", site: "example.com"), now: 1000) }
        try state.apply(Command("addTask", title: "Test"), now: 1000)
        try state.apply(Command("start", taskID: state.tasks[0].id, minutes: 15), now: 1000)
        rejects { try state.apply(Command("addBlockedSite", site: "douyin.com"), now: 1010) }
        rejects { try state.apply(Command("removeBlockedSite", site: "bilibili.com"), now: 1010) }
        try state.apply(Command("requestAccess", site: "live.bilibili.com"), now: 1010)
        check(state.pending?.site == "bilibili.com", "Custom temporary access group")
        rejects { try state.apply(Command("confirmAccess", requestID: state.pending?.id), now: 1039) }
        try state.apply(Command("confirmAccess", requestID: state.pending?.id), now: 1040)
        check(state.session?.allowances.last?.endAt == 1340, "Five-minute access")
        state.tick(now: 1900)
        try state.apply(Command("removeBlockedSite", site: "bilibili.com"), now: 1901)
        check(state.canonicalBlockedSite("bilibili.com") == nil, "Remove outside focus")
        for site in state.effectiveBlockedSites { try state.apply(Command("removeBlockedSite", site: site.site), now: 1901) }
        check(state.effectiveBlockedSites.isEmpty, "Explicit empty list is retained")
        state = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(state))
        check(state.effectiveBlockedSites.isEmpty, "Empty round trip")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("state.json")
        try Data("{\"schema\":1,\"tasks\":[],\"history\":[]}".utf8).write(to: file)
        let store = StateStore(directory: directory)
        let migrated = try store.transact(now: 1000)
        check(migrated.schema == 3 && migrated.effectiveBlockedSites.count == 3, "Legacy schema migration")
        _ = try store.transact(command: Command("addBlockedSite", site: "bilibili.com"), now: 1000)
        check(try store.transact(now: 1001).canonicalBlockedSite("bilibili.com") == "bilibili.com", "Persistence")
        let longHost = String(repeating: "a", count: 60) + "." + String(repeating: "b", count: 60) + ".example"
        _ = try store.transact(command: Command("addBlockedSite", site: longHost), now: 1001)
        check(try store.transact(now: 1001).canonicalBlockedSite(longHost) == longHost, "Long valid DNS name round trip")
        var full = FocusState()
        full.blockedSites = (0..<100).map { BlockedSite(site: "site\($0).example", name: "site\($0).example", domains: ["site\($0).example"]) }
        rejects { try full.apply(Command("addBlockedSite", site: "extra.example"), now: 1001) }
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        json["blockedSites"] = [["site":"bad..com","name":"Bad","domains":["bad..com"]]]
        let invalid = try JSONSerialization.data(withJSONObject: json)
        try invalid.write(to: file)
        rejects { _ = try store.transact(now: 1001) }
        check(try Data(contentsOf: file) == invalid, "Invalid site config preserved")
        print("PASS: website normalization, aliases, list editing, focus lock, delayed custom access, migration and persistence")
    }
}
