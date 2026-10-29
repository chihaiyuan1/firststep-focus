import Foundation
@main struct HourlyFocusChecks {
    static func main() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 8*3600)!
        let iso = ISO8601DateFormatter()
        func timestamp(_ s: String) -> Double { iso.date(from: s)!.timeIntervalSince1970 }
        let now = Date(timeIntervalSince1970: timestamp("2026-10-29T08:00:00Z"))
        func record(_ id: String, _ start: String, _ seconds: Double, _ finished: Bool = true) -> FocusRecord {
            FocusRecord(id: id, taskID: "t", title: "T", startAt: timestamp(start), endAt: timestamp(start)+seconds, focusSeconds: seconds, finished: finished, accessCount: 0)
        }
        let records = [record("in", "2026-10-29T01:50:00Z", 1200), record("early", "2026-10-29T01:10:00Z", 300, false), record("old", "2026-10-20T01:00:00Z", 900), record("future", "2026-10-30T01:00:00Z", 900)]
        let values = HourlyFocusStatistics(records: records, ending: now, days: 7, calendar: c)
        precondition(values.seconds.count == 24 && values.seconds[9] == 1500)
        precondition(values.seconds.reduce(0,+) == 1500)
        let wider = HourlyFocusStatistics(records: records, ending: now, days: 28, calendar: c)
        precondition(wider.seconds[9] == 2400)
        print("PASS: local hour, interrupted focus, start-hour attribution and bounded range")
    }
}
