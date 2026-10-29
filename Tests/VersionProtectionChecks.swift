import Foundation
@main struct VersionProtectionChecks {
    static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let state = try StateStore(directory:dir).transact(command:Command("addInbox",title:"未来任务"),now:100000)
        precondition(state.schema == 6, "state needs new schema for backward protection")
        let entry = try TimeEntry(day:"2026-10-29",startMinute:540,endMinute:600,title:"记录",taskID:"task")
        _ = try TimeLogStore(directory:dir).upsert(entry)
        let raw = try Data(contentsOf:dir.appendingPathComponent("time-records.json"))
        let timeDoc = try JSONSerialization.jsonObject(with:raw) as! [String:Any]
        precondition(timeDoc["schema"] as? Int == 3, "time log needs new schema")
        let journal = AIJournalEntry(day:"2026-10-26",kind:"weeklyReview",taskID:nil,title:"周复盘",turns:[AITurn(role:"user",content:"测试")],reply:AssistantReply(kind:"review",message:"完成"))
        _ = try AIJournalStore(directory:dir).append(journal)
        let journalRaw = try Data(contentsOf:dir.appendingPathComponent("ai-journal.json"))
        let journalDoc = try JSONSerialization.jsonObject(with:journalRaw) as! [String:Any]
        precondition(journalDoc["schema"] as? Int == 2, "journal needs new schema")
        print("PASS: data versions prevent older readers from discarding new fields")
    }
}
