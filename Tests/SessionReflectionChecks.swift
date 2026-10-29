import Foundation
import Darwin

private var failures: [String] = []
private var assertions = 0

private func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    assertions += 1
    do { if try !condition() { failures.append(name) } }
    catch { failures.append("\(name): \(error)") }
}

private func rejects(_ name: String, _ body: () throws -> Void) {
    assertions += 1
    do { try body(); failures.append(name) } catch {}
}

private func scenario(_ name: String, _ body: () throws -> Void) {
    do { try body() } catch { failures.append("\(name): \(error)") }
}

private func isolatedDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("firststep-reflections-\(UUID().uuidString)")
}

private func permissions(_ url: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue & 0o777
}

@main struct SessionReflectionChecks {
    static func main() throws {
        if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--worker" {
            let store = SessionReflectionStore(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
            let index = CommandLine.arguments[3]
            _ = try store.save(recordID: "process-\(index)", text: "saved \(index)", now: 300)
            _ = try store.saveDraft(recordID: "process-\(index)", text: "  draft \(index)\n", now: 301)
            return
        }

        scenario("missing file") {
            let dir = isolatedDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = SessionReflectionStore(directory: dir)
            check(try store.read().isEmpty, "missing data starts empty")
            check(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("focus-reflections.json").path), "read does not create a data file")
        }

        scenario("saved and draft lifecycle") {
            let dir = isolatedDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = SessionReflectionStore(directory: dir)
            let initial = try store.save(recordID: "round-a", text: " \n第一行  保留空格\n第二行\n ", now: 100)
            check(initial.count == 1, "save creates one record")
            check(initial.first?.text == "第一行  保留空格\n第二行", "save trims only outer whitespace")
            check(initial.first?.id == "round-a" && initial.first?.editorText == "第一行  保留空格\n第二行", "editor falls back to saved content and stable ID")
            check(initial.first?.savedAt == 100 && initial.first?.updatedAt == 100 && initial.first?.draft == nil, "save timestamps and absent draft")

            let drafted = try store.saveDraft(recordID: "round-a", text: "  还没决定\n\n ", now: 101)
            check(drafted.first?.text == "第一行  保留空格\n第二行" && drafted.first?.savedAt == 100, "draft never replaces last saved content or saved time")
            check(drafted.first?.draft == "  还没决定\n\n " && drafted.first?.editorText == "  还没决定\n\n ", "draft preserves exact editor text")
            check(drafted.first?.updatedAt == 101, "draft updates modified timestamp")

            let skipped = try store.dismiss(recordID: "round-a", now: 102)
            check(skipped.first?.draft == "  还没决定\n\n " && skipped.first?.text == "第一行  保留空格\n第二行", "dismiss preserves draft and saved content")
            check(skipped.first?.savedAt == 100 && skipped.first?.dismissedAt == 102 && skipped.first?.updatedAt == 102, "dismiss only updates dismissed and modified timestamps")
            check(try SessionReflectionStore(directory: dir).read() == skipped, "fresh store reloads saved draft and dismiss state")

            let savedAgain = try store.save(recordID: "round-a", text: "  已想清楚  ", now: 103)
            check(savedAgain.count == 1 && savedAgain.first?.text == "已想清楚" && savedAgain.first?.draft == nil, "save overwrites one note and clears draft")
            check(savedAgain.first?.savedAt == 103, "resave updates saved time")
            _ = try store.saveDraft(recordID: "round-a", text: "", now: 104)
            let blankDraft = try store.read().first
            check(blankDraft?.draft == "" && blankDraft?.editorText == "" && blankDraft?.text == "已想清楚", "empty draft overrides editor without erasing saved note")
            let cleared = try store.save(recordID: "round-a", text: " \n\t", now: 105)
            check(cleared.first?.text == "" && cleared.first?.draft == nil && cleared.first?.savedAt == 105, "empty save deliberately clears saved note")

            let newDraft = try store.saveDraft(recordID: "round-b", text: "draft only", now: 106).first { $0.id == "round-b" }
            check(newDraft?.text == "" && newDraft?.savedAt == nil && newDraft?.draft == "draft only", "draft-only record does not become saved content")
            let newDismiss = try store.dismiss(recordID: "round-c", now: 107).first { $0.id == "round-c" }
            check(newDismiss?.text == "" && newDismiss?.savedAt == nil && newDismiss?.draft == nil && newDismiss?.dismissedAt == 107, "skip records dismissal even before any typing")
            let before = Date().timeIntervalSince1970
            let timed = try store.save(recordID: "clock", text: "now").first { $0.id == "clock" }
            let after = Date().timeIntervalSince1970
            check(timed.map { $0.updatedAt >= before && $0.updatedAt <= after && $0.savedAt == $0.updatedAt } ?? false, "omitted now uses current Unix time")
        }

        scenario("permissions and schema isolation") {
            let dir = isolatedDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            let stateFile = dir.appendingPathComponent("state.json")
            let stateBytes = Data("{\"schema\":5,\"session\":\"unchanged business state\"}".utf8)
            try stateBytes.write(to: stateFile)
            let store = SessionReflectionStore(directory: dir)
            _ = try store.save(recordID: "private", text: "local only", now: 10)
            let file = dir.appendingPathComponent("focus-reflections.json")
            check(try permissions(dir) == 0o700 && permissions(file) == 0o600, "directory and data permissions are private")
            check(try permissions(dir.appendingPathComponent("focus-reflections.lock")) == 0o600, "lock file permissions are private")
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            check(json["schema"] as? Int == 1, "independent reflection schema is one")
            check(try Data(contentsOf: stateFile) == stateBytes, "reflection operations never mutate business state")
            let bytes = try Data(contentsOf: file)
            _ = try store.read()
            check(try Data(contentsOf: file) == bytes, "read preserves exact existing bytes")
        }

        scenario("validation before filesystem transaction") {
            let dir = isolatedDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = SessionReflectionStore(directory: dir)
            rejects("reject empty save ID") { _ = try store.save(recordID: "", text: "x", now: 1) }
            rejects("reject long draft ID") { _ = try store.saveDraft(recordID: String(repeating: "x", count: 101), text: "x", now: 1) }
            rejects("reject empty dismiss ID") { _ = try store.dismiss(recordID: "", now: 1) }
            rejects("reject overlength saved text") { _ = try store.save(recordID: "a", text: String(repeating: "字", count: 8001), now: 1) }
            rejects("reject overlength draft") { _ = try store.saveDraft(recordID: "a", text: String(repeating: "字", count: 8001), now: 1) }
            rejects("reject nonfinite save time") { _ = try store.save(recordID: "a", text: "x", now: .nan) }
            rejects("reject nonfinite draft time") { _ = try store.saveDraft(recordID: "a", text: "x", now: .infinity) }
            rejects("reject nonfinite dismiss time") { _ = try store.dismiss(recordID: "a", now: -.infinity) }
            check(!FileManager.default.fileExists(atPath: dir.path), "invalid inputs do not even create lock or directory")
            let atLimit = try store.save(recordID: String(repeating: "i", count: 100), text: String(repeating: "字", count: 8000), now: 2)
            check(atLimit.first?.text.count == SessionReflection.maxTextLength, "maximum text and ID lengths are accepted")
            let bytes = try Data(contentsOf: dir.appendingPathComponent("focus-reflections.json"))
            rejects("invalid edit rejected") { _ = try store.save(recordID: "valid", text: "x", now: .nan) }
            check(try Data(contentsOf: dir.appendingPathComponent("focus-reflections.json")) == bytes, "invalid edits preserve existing bytes")
        }

        scenario("malformed and unsupported file protection") {
            let fixtures = [
                "broken, preserve this",
                "{\"schema\":2,\"reflections\":[]}",
                "{\"schema\":0,\"reflections\":[]}",
                "{\"reflections\":[]}",
                "{\"schema\":1,\"reflections\":[{\"recordID\":\"\",\"text\":\"x\",\"updatedAt\":1}]}",
                "{\"schema\":1,\"reflections\":[{\"recordID\":\"a\",\"text\":\"x\",\"updatedAt\":1e400}]}",
                "{\"schema\":1,\"reflections\":[{\"recordID\":\"a\",\"text\":\"x\",\"updatedAt\":1,\"savedAt\":1e400}]}",
                "{\"schema\":1,\"reflections\":[{\"recordID\":\"a\",\"text\":\"x\",\"updatedAt\":1,\"dismissedAt\":1e400}]}",
                "{\"schema\":1,\"reflections\":[{\"recordID\":\"\(String(repeating: "i", count: 101))\",\"text\":\"x\",\"updatedAt\":1}]}",
                "{\"schema\":1,\"reflections\":[{\"recordID\":\"a\",\"text\":\"\(String(repeating: "字", count: 8001))\",\"updatedAt\":1}]}",
                "{\"schema\":1,\"reflections\":[{\"recordID\":\"a\",\"text\":\"x\",\"draft\":\"\(String(repeating: "字", count: 8001))\",\"updatedAt\":1}]}",
                "{\"schema\":1,\"reflections\":[{\"recordID\":\"a\",\"text\":\"x\",\"updatedAt\":1},{\"recordID\":\"a\",\"text\":\"y\",\"updatedAt\":2}]}"
            ]
            for (index, fixture) in fixtures.enumerated() {
                let dir = isolatedDirectory()
                defer { try? FileManager.default.removeItem(at: dir) }
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let file = dir.appendingPathComponent("focus-reflections.json"), bytes = Data(fixture.utf8)
                try bytes.write(to: file)
                let store = SessionReflectionStore(directory: dir)
                rejects("fixture \(index) read rejects") { _ = try store.read() }
                rejects("fixture \(index) save rejects") { _ = try store.save(recordID: "new", text: "must not replace", now: 4) }
                rejects("fixture \(index) draft rejects") { _ = try store.saveDraft(recordID: "new", text: "must not replace", now: 4) }
                rejects("fixture \(index) dismiss rejects") { _ = try store.dismiss(recordID: "new", now: 4) }
                check(try Data(contentsOf: file) == bytes, "fixture \(index) original bytes preserved by all operations")
            }
        }

        scenario("concurrent writes") {
            let dir = isolatedDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let errorsLock = NSLock()
            var errors: [String] = []
            DispatchQueue.concurrentPerform(iterations: 16) { index in
                do {
                    let store = SessionReflectionStore(directory: dir)
                    _ = try store.save(recordID: "thread-\(index)", text: "saved \(index)", now: 200)
                    _ = try store.saveDraft(recordID: "thread-\(index)", text: "draft \(index)", now: 201)
                } catch {
                    errorsLock.lock(); errors.append(String(describing: error)); errorsLock.unlock()
                }
            }
            check(errors.isEmpty, "concurrent threaded operations succeed")
            let threaded = try SessionReflectionStore(directory: dir).read()
            check(threaded.count == 16 && threaded.allSatisfy { $0.text.hasPrefix("saved ") && $0.draft?.hasPrefix("draft ") == true && $0.savedAt == 200 }, "all threaded saved notes and drafts survive")
            var workers: [Process] = []
            for index in 0..<8 {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                process.arguments = ["--worker", dir.path, String(index)]
                try process.run()
                workers.append(process)
            }
            workers.forEach { $0.waitUntilExit() }
            check(workers.allSatisfy { $0.terminationStatus == 0 }, "concurrent independent processes succeed")
            let merged = try SessionReflectionStore(directory: dir).read()
            check(merged.count == 24 && Set(merged.map(\.recordID)).count == 24, "process and thread writes merge without lost records")
            check(merged.filter { $0.recordID.hasPrefix("process-") }.allSatisfy { $0.savedAt == 300 && $0.draft?.hasPrefix("  draft ") == true }, "process drafts preserve saved notes")
            check(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasSuffix(".tmp") }, "successful writes leave no atomic temporary files")
        }

        if failures.isEmpty { print("PASS: \(assertions) reflection checks (lifecycle, draft isolation, validation, privacy, corruption, threaded and process concurrency)") }
        else { failures.forEach { print("FAIL: \($0)") }; exit(1) }
    }
}
