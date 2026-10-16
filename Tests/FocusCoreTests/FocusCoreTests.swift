import Foundation

final class FocusCoreTests {
    func testStoragePreservesConcurrentWritesAndRefusesCorruption() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(directory: dir)
        _ = try store.transact(command: Command("addTask", title: "保留我"), now: 1000)
        XCTAssertEqual(try store.transact(now: 1001).tasks.first?.title, "保留我")
        let lock = NSLock(); var errors: [String] = []
        DispatchQueue.concurrentPerform(iterations: 20) { i in
            do { _ = try StateStore(directory: dir).transact(command: Command("addTask", title: "任务 \(i)"), now: 1002) }
            catch { lock.lock(); errors.append(error.localizedDescription); lock.unlock() }
        }
        XCTAssertEqual(errors.count, 0)
        XCTAssertEqual(try store.transact(now: 1003).tasks.count, 21)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let broken = Data("broken JSON, do not overwrite".utf8)
        let file = dir.appendingPathComponent("state.json")
        try broken.write(to: file)
        XCTAssertThrowsError(try store.transact(now: 1004))
        XCTAssertEqual(try Data(contentsOf: file), broken)
    }
    func started(minutes: Int = 15) throws -> FocusState {
        var s = FocusState()
        try s.apply(Command("addTask", title: "写开头", nextStep: "三句话"), now: 1_000)
        XCTAssertEqual(s.tasks.count, 1)
        guard let task = s.tasks.first else { throw FocusError("missing task") }
        try s.apply(Command("start", taskID: task.id, minutes: minutes), now: 1_000)
        return s
    }
    func testRejectsBlankTaskAndUnsupportedDuration() throws {
        var s = FocusState()
        XCTAssertThrowsError(try s.apply(Command("addTask", title: "  \n"), now: 1_000))
        try s.apply(Command("addTask", title: "任务"), now: 1_000)
        XCTAssertThrowsError(try s.apply(Command("start", taskID: s.tasks.first?.id, minutes: 0), now: 1_000))
    }
    func testDeadlineSurvivesRoundTripAndEndsExactlyOnce() throws {
        let original = try started()
        var s = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(s.session?.endAt, 1_900)
        s.tick(now: 1_899); XCTAssertNotNil(s.session)
        s.tick(now: 9_000); XCTAssertNil(s.session)
        XCTAssertEqual(s.history.count, 1)
        XCTAssertEqual(s.history.first?.focusSeconds, 900)
        XCTAssertEqual(s.history.first?.endAt, 1_900)
        s.tick(now: 10_000); XCTAssertEqual(s.history.count, 1)
    }
    func testAllPresetsAndNoConcurrentSession() throws {
        for duration in [15,25,30,45] {
            var s = try started(minutes: duration)
            XCTAssertEqual(s.session?.endAt, 1_000 + Double(duration * 60))
            XCTAssertThrowsError(try s.apply(Command("start", taskID: s.tasks[0].id, minutes: 15), now: 1_001))
        }
    }
    func testAccessRequiresWaitAndGrantsOnlyFiveMinutes() throws {
        var s = try started()
        try s.apply(Command("requestAccess", site: "twitter.com"), now: 1_010)
        let request = s.pending?.id
        XCTAssertEqual(s.pending?.site, "x.com")
        XCTAssertThrowsError(try s.apply(Command("confirmAccess", requestID: request), now: 1_039))
        try s.apply(Command("confirmAccess", requestID: request), now: 1_040)
        XCTAssertEqual(s.session?.allowances.first?.site, "x.com")
        XCTAssertEqual(s.session?.allowances.first?.endAt, 1_340)
        XCTAssertNil(s.pending)
        XCTAssertThrowsError(try s.apply(Command("confirmAccess", requestID: request), now: 1_050))
        s.tick(now: 1_900)
        XCTAssertEqual(s.history.first?.focusSeconds, 600)
    }
    func testCannotGrantUnknownSitesOrReuseRequestAcrossSessions() throws {
        var s = try started()
        XCTAssertThrowsError(try s.apply(Command("requestAccess", site: "work.com"), now: 1_010))
        try s.apply(Command("requestAccess", site: "weibo.cn"), now: 1_010)
        let request = s.pending?.id
        s.tick(now: 1_900)
        try s.apply(Command("start", taskID: s.tasks[0].id, minutes: 15), now: 2_000)
        XCTAssertThrowsError(try s.apply(Command("confirmAccess", requestID: request), now: 2_010))
    }
    func testStopRequiresWaitAndDoesNotCompleteTask() throws {
        var s = try started()
        try s.apply(Command("requestEnd"), now: 1_100)
        let request = s.pending?.id
        XCTAssertThrowsError(try s.apply(Command("confirmEnd", requestID: request), now: 1_129))
        try s.apply(Command("confirmEnd", requestID: request), now: 1_130)
        XCTAssertNil(s.session)
        XCTAssertEqual(s.history.first?.finished, false)
        XCTAssertEqual(s.history.first?.focusSeconds, 130)
        XCTAssertFalse(s.tasks[0].completed)
    }
    func testOverlappingAccessIsNotDoubleSubtractedAndClipsToDeadline() throws {
        var s = try started()
        try s.apply(Command("requestAccess", site: "x.com"), now: 1_010)
        try s.apply(Command("confirmAccess", requestID: s.pending?.id), now: 1_040)
        try s.apply(Command("requestAccess", site: "weibo.com"), now: 1_050)
        try s.apply(Command("confirmAccess", requestID: s.pending?.id), now: 1_080)
        s.tick(now: 1_900)
        XCTAssertEqual(s.history.first?.focusSeconds, 560)
        XCTAssertEqual(s.history.first?.accessCount, 2)
        s = try started()
        try s.apply(Command("requestAccess", site: "xueqiu.com"), now: 1_850)
        try s.apply(Command("confirmAccess", requestID: s.pending?.id), now: 1_880)
        XCTAssertEqual(s.session?.allowances[0].endAt, 1_900)
    }
    func testTaskEditsAndDeletionAreProtectedDuringFocus() throws {
        var s = try started()
        let id = s.tasks[0].id
        XCTAssertThrowsError(try s.apply(Command("deleteTask", taskID: id), now: 1_010))
        XCTAssertThrowsError(try s.apply(Command("completeTask", taskID: id), now: 1_010))
        s.tick(now: 1_900)
        try s.apply(Command("completeTask", taskID: id), now: 1_901)
        XCTAssertTrue(s.tasks[0].completed)
    }
}

var failures: [String] = []
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) { if actual != expected { failures.append("\(file):\(line): \(actual) != \(expected)") } }
func XCTAssertNil<T>(_ value: T?, line: UInt = #line) { if value != nil { failures.append("line \(line): expected nil") } }
func XCTAssertNotNil<T>(_ value: T?, line: UInt = #line) { if value == nil { failures.append("line \(line): expected value") } }
func XCTAssertTrue(_ value: Bool, line: UInt = #line) { if !value { failures.append("line \(line): expected true") } }
func XCTAssertFalse(_ value: Bool, line: UInt = #line) { if value { failures.append("line \(line): expected false") } }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, line: UInt = #line) { do { _ = try expression(); failures.append("line \(line): expected error") } catch {} }

@main struct TestRunner { static func main() {
let suite = FocusCoreTests()
do { try suite.testStoragePreservesConcurrentWritesAndRefusesCorruption() } catch { failures.append("storage: \(error)") }
do { try suite.testRejectsBlankTaskAndUnsupportedDuration() } catch { failures.append("testRejectsBlankTaskAndUnsupportedDuration: \(error)") }
do { try suite.testDeadlineSurvivesRoundTripAndEndsExactlyOnce() } catch { failures.append("testDeadlineSurvivesRoundTripAndEndsExactlyOnce: \(error)") }
do { try suite.testAllPresetsAndNoConcurrentSession() } catch { failures.append("testAllPresetsAndNoConcurrentSession: \(error)") }
do { try suite.testAccessRequiresWaitAndGrantsOnlyFiveMinutes() } catch { failures.append("testAccessRequiresWaitAndGrantsOnlyFiveMinutes: \(error)") }
do { try suite.testCannotGrantUnknownSitesOrReuseRequestAcrossSessions() } catch { failures.append("testCannotGrantUnknownSitesOrReuseRequestAcrossSessions: \(error)") }
do { try suite.testStopRequiresWaitAndDoesNotCompleteTask() } catch { failures.append("testStopRequiresWaitAndDoesNotCompleteTask: \(error)") }
do { try suite.testOverlappingAccessIsNotDoubleSubtractedAndClipsToDeadline() } catch { failures.append("testOverlappingAccessIsNotDoubleSubtractedAndClipsToDeadline: \(error)") }
do { try suite.testTaskEditsAndDeletionAreProtectedDuringFocus() } catch { failures.append("testTaskEditsAndDeletionAreProtectedDuringFocus: \(error)") }
if failures.isEmpty { print("PASS: 9 core scenarios") } else { failures.forEach { print("FAIL: \($0)") }; exit(1) }
} }
