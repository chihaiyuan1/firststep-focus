import Foundation

private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw FocusError(message) }
}
private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private func record(_ id: String, _ start: String, _ seconds: Double, finished: Bool = true) -> FocusRecord {
    let time = date(start).timeIntervalSince1970
    return FocusRecord(id:id,taskID:"task",title:"统计测试",startAt:time,endAt:time+2700,focusSeconds:seconds,finished:finished,accessCount:0)
}
@main struct FocusStatisticsChecks {
    static func main() throws {
        var cal = Calendar(identifier:.gregorian); cal.timeZone=TimeZone(identifier:"Asia/Shanghai")!
        let selected = date("2026-10-22T04:00:00Z")
        let records = [record("prior","2026-10-18T15:59:59Z",900),
                       record("mon","2026-10-18T16:00:00Z",1500),
                       record("wed","2026-10-21T02:00:00Z",2400),
                       record("early","2026-10-22T02:00:00Z",480,finished:false),
                       record("sunday","2026-10-25T15:59:59Z",900),
                       record("next","2026-10-25T16:00:00Z",900)]
        let week = FocusStatistics(records:records,on:selected,scope:.week,calendar:cal)
        try check(week.buckets.count==7 && week.interval.start==date("2026-10-18T16:00:00Z") && week.interval.end==date("2026-10-25T16:00:00Z"),"Natural week must be Monday through Sunday even when locale defaults to Sunday")
        try check(week.totalFocusSeconds==5280 && week.completedCount==3,"Early-ended effort contributes time but not completed count; adjacent weeks excluded")
        try check(week.buckets.map(\.focusSeconds)==[1500,0,2400,480,0,0,900],"Weekly chart must preserve all seven dates including zero days")
        try check(week.buckets.map(\.completedCount)==[1,0,1,0,0,0,1],"Completions must belong to their start day, including cross-midnight rounds")

        let octRecords=[record("before","2026-09-30T15:59:59Z",900),record("first","2026-09-30T16:00:00Z",900),
                        record("sun","2026-10-04T15:59:59Z",1500),record("mon","2026-10-04T16:00:00Z",1800),
                        record("last","2026-10-31T15:59:59Z",2700),record("after","2026-10-31T16:00:00Z",900)]
        let month=FocusStatistics(records:octRecords,on:selected,scope:.month,calendar:cal)
        try check(month.buckets.count==5 && month.totalFocusSeconds==6900 && month.completedCount==4,"October monthly bars must exclude September/November and retain both partial weeks")
        try check(month.buckets.map { cal.component(.day,from:$0.start) }==[1,5,12,19,26],"October buckets start on month day1 then each Monday")
        try check(month.buckets.map { cal.component(.day,from:cal.date(byAdding:.day,value:-1,to:$0.end)!) }==[4,11,18,25,31],"October weekly bars must end at Sunday or the month boundary")
        try check(month.buckets.map(\.focusSeconds)==[2400,1800,0,0,2700],"Records exactly on Monday midnight must not be double counted")
        try check(month.buckets.reduce(0) { $0+$1.focusSeconds }==month.totalFocusSeconds,"Bar totals must equal period total")
        for (anchor,expectedCount,expectedDays) in [("2021-02-15T04:00:00Z",4,28),("2024-02-15T04:00:00Z",5,29),("2026-08-15T04:00:00Z",6,31)] {
            let s=FocusStatistics(records:[],on:date(anchor),scope:.month,calendar:cal)
            let days=s.buckets.reduce(0) { $0+cal.dateComponents([.day],from:$1.start,to:$1.end).day! }
            try check(s.buckets.count==expectedCount && days==expectedDays,"Four/six-week and leap months must cover every date once")
            try check(s.totalFocusSeconds==0 && s.completedCount==0 && s.buckets.allSatisfy { $0.focusSeconds==0 },"Empty month must retain zero-value weekly bars")
        }
        let year=FocusStatistics(records:[],on:date("2027-01-01T04:00:00Z"),scope:.week,calendar:cal)
        try check(year.interval.start==date("2026-12-27T16:00:00Z") && year.interval.end==date("2027-01-03T16:00:00Z"),"Cross-year week must preserve Monday and Sunday in different years")
        let short=FocusStatistics(records:[record("one","2026-10-19T02:00:00Z",40,finished:false),record("two","2026-10-20T02:00:00Z",40,finished:false)],on:selected,scope:.week,calendar:cal)
        try check(short.totalFocusSeconds==80 && short.completedCount==0,"Sum raw effort before minute rounding")
        let nextMonth=FocusStatisticsScope.month.shiftedDate(from:date("2026-01-31T04:00:00Z"),by:1,calendar:cal)
        let followingMonth=FocusStatisticsScope.month.shiftedDate(from:nextMonth,by:1,calendar:cal)
        try check(nextMonth==date("2026-01-31T16:00:00Z") && followingMonth==date("2026-02-28T16:00:00Z"),"Month navigation must anchor to period starts without day-of-month drift")

        cal.timeZone=TimeZone(identifier:"America/Los_Angeles")!
        let dst=FocusStatistics(records:[record("extra","2026-11-02T07:30:00Z",900)],on:date("2026-11-01T20:00:00Z"),scope:.week,calendar:cal)
        try check(dst.interval.duration==169*3600 && dst.buckets[6].end.timeIntervalSince(dst.buckets[6].start)==25*3600 && dst.completedCount==1,"DST week must retain the full 25-hour Sunday")
        cal.timeZone=TimeZone(identifier:"America/Havana")!
        let midnightRecords=[record("monday-first-hour","2026-03-02T05:30:00Z",900),record("next-monday","2026-03-09T04:30:00Z",1500)]
        let midnight=FocusStatistics(records:midnightRecords,on:date("2026-03-08T16:00:00Z"),scope:.week,calendar:cal)
        let sameWeek=FocusStatistics(records:midnightRecords,on:date("2026-03-07T17:00:00Z"),scope:.week,calendar:cal)
        try check(midnight.interval==sameWeek.interval && midnight.interval.start==date("2026-03-02T05:00:00Z") && midnight.interval.end==date("2026-03-09T04:00:00Z"),"A skipped midnight must not shift Monday boundaries based on selected day")
        try check(midnight.totalFocusSeconds==900 && midnight.completedCount==1,"Skipped-midnight week must include Monday first hour and exclude next Monday")
        try check(midnight.buckets[6].start==date("2026-03-08T05:00:00Z") && midnight.buckets[6].end==date("2026-03-09T04:00:00Z"),"Skipped-midnight Sunday bucket must stop at next local midnight")
        let shortDay=FocusStatisticsScope.day.interval(containing:date("2026-03-08T16:00:00Z"),calendar:cal)
        try check(shortDay.duration==23*3600 && shortDay.end==date("2026-03-09T04:00:00Z"),"Skipped-midnight day must end at next day's actual start")
        try check(FocusStatisticsScope.day.shiftedDate(from:date("2026-03-08T16:00:00Z"),by:1,calendar:cal)==date("2026-03-09T04:00:00Z"),"Navigation from skipped midnight must reset to next start of day")
        let midnightMonth=FocusStatistics(records:[record("april-monday","2012-04-02T04:30:00Z",900)],on:date("2012-04-01T16:00:00Z"),scope:.month,calendar:cal)
        try check(midnightMonth.buckets.count==6 && midnightMonth.buckets[0].end==date("2012-04-02T04:00:00Z") && midnightMonth.buckets[1].focusSeconds==900,"Month starting at 01:00 must not carry that hour into Monday buckets")
        try check(FocusStatisticsScope.month.shiftedDate(from:midnightMonth.interval.start,by:1,calendar:cal)==date("2012-05-01T04:00:00Z"),"Month navigation from a skipped midnight must reset to local day start")
        print("PASS: natural week, clipped monthly weeks, net time/completions, zero days, leap/four/six-week months, midnight/year/DST boundaries and anchored navigation")
    }
}
