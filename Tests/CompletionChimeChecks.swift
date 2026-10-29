import Foundation
import Darwin

private var failures: [String] = []
private var checks = 0
private func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    checks += 1
    do { if try !condition() { failures.append(name) } }
    catch { failures.append("\(name): \(error.localizedDescription)") }
}
private func rejects(_ name: String, _ body: () throws -> Void) {
    checks += 1
    do { try body(); failures.append(name) } catch {}
}
private func little16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
}
private func little32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 |
        UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
}
private func rms(_ samples: [Double], _ range: Range<Int>) -> Double {
    sqrt(samples[range].reduce(0) { $0 + $1 * $1 } / Double(range.count))
}
private func spectralAmplitude(_ samples: [Double], frequency: Double, sampleRate: Double) -> Double {
    var real = 0.0, imaginary = 0.0
    for (index, sample) in samples.enumerated() {
        let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
        real += sample * cos(phase)
        imaginary -= sample * sin(phase)
    }
    return 2 * hypot(real, imaginary) / Double(samples.count)
}

@main struct CompletionChimeChecks {
    static func main() throws {
        // Catches a wrong format/length, clipped mix, abrupt edges, or harsh extra partials.
        let wav = CompletionChime.wavData()
        check(wav.count == 220_544, "2.5 seconds of 44.1 kHz mono PCM plus WAV header")
        if wav.count >= 44 {
            check(String(data: wav[0..<4], encoding: .ascii) == "RIFF", "RIFF container")
            check(little32(wav, 4) == UInt32(wav.count - 8), "RIFF declared byte length")
            check(String(data: wav[8..<12], encoding: .ascii) == "WAVE", "WAVE format")
            check(String(data: wav[12..<16], encoding: .ascii) == "fmt ", "PCM format chunk")
            check(little32(wav, 16) == 16 && little16(wav, 20) == 1, "uncompressed PCM")
            check(little16(wav, 22) == 1 && little16(wav, 34) == 16, "mono 16-bit samples")
            check(little32(wav, 24) == 44_100 && little32(wav, 28) == 88_200 && little16(wav, 32) == 2, "consistent sample rate and byte alignment")
            check(String(data: wav[36..<40], encoding: .ascii) == "data", "audio data chunk")
            check(little32(wav, 40) == UInt32(wav.count - 44), "audio chunk exact byte length")
            let rate = Double(little32(wav, 24))
            let samples = stride(from: 44, to: wav.count - 1, by: 2).map {
                Double(Int16(bitPattern: little16(wav, $0))) / 32_768
            }
            check(rate > 0 && Double(samples.count) / rate == 2.5 && CompletionChime.duration == 2.5, "header and advertised duration both exactly 2.5 seconds")
            if samples.count == 110_250 {
                let peak = samples.map(abs).max() ?? 0
                check(peak > 0.12 && peak < 0.32, "audible moderate peak without clipping")
                check(samples.first == 0 && samples.last == 0, "silent endpoints prevent clicks")
                check(rms(samples, 0..<441) < rms(samples, 4_410..<8_820) * 0.10, "smooth attack over the first 10 ms")
                check(rms(samples, 108_045..<110_250) < rms(samples, 66_150..<70_560) * 0.05, "smooth release over final 50 ms")
                let pitches = [523.251, 659.255, 783.991].map { spectralAmplitude(samples, frequency: $0, sampleRate: rate) }
                check(pitches.allSatisfy { $0 > 0.003 }, "soft C5 E5 G5 fundamental pitches are present")
                check(spectralAmplitude(samples, frequency: 4_000, sampleRate: rate) < (pitches.min() ?? 0) * 0.01, "no piercing high partial in generated tone")
                print(String(format: "Signal: duration=%.3fs, peak=%.5f (%.1fdBFS), rms=%.5f, samples=%d", Double(samples.count) / rate, peak, 20 * log10(peak), rms(samples, 0..<samples.count), samples.count))
            }
        }

        // Catches eager file creation, a lost setting after restart, or insecure permissions.
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("firststep-chime-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: directory) }
        let store = CompletionReminderPreferencesStore(directory: directory)
        let file = directory.appendingPathComponent("completion-reminders.json")
        check(try store.read(), "new installation defaults to end sound on")
        check(!fm.fileExists(atPath: file.path), "read never creates a preferences JSON")
        check(try !store.setSoundEnabled(false), "disable returns persisted value")
        check(try !CompletionReminderPreferencesStore(directory: directory).read(), "disabled preference survives reload")
        check(try store.setSoundEnabled(true), "enable returns persisted value")
        check(try CompletionReminderPreferencesStore(directory: directory).read(), "enabled preference survives reload")
        check(try (fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "preferences file stays owner-only")
        check(try (fm.attributesOfItem(atPath: directory.appendingPathComponent("completion-reminders.lock").path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "preference lock stays owner-only")

        // Catches an overwrite of unreadable or unsupported user settings.
        let fixtures: [(String, String)] = [
            ("broken JSON", "broken, preserve these bytes"),
            ("future schema", "{\"schema\":2,\"soundEnabled\":false,\"future\":\"preserve\"}"),
            ("missing enabled value", "{\"schema\":1}"),
            ("invalid enabled value", "{\"schema\":1,\"soundEnabled\":\"yes\"}")
        ]
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, json) in fixtures {
            let bytes = Data(json.utf8)
            try bytes.write(to: file)
            rejects("\(name) rejects read") { _ = try store.read() }
            rejects("\(name) rejects write") { _ = try store.setSoundEnabled(true) }
            check(try Data(contentsOf: file) == bytes, "\(name) keeps original bytes")
        }

        // The file lock must serialize reads/writes rather than exposing partial JSON.
        try Data("{\"schema\":1,\"soundEnabled\":true}".utf8).write(to: file)
        let errorLock = NSLock()
        var concurrentErrors: [String] = []
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            do {
                let instance = CompletionReminderPreferencesStore(directory: directory)
                _ = try instance.setSoundEnabled(index.isMultiple(of: 2))
                _ = try instance.read()
            } catch {
                errorLock.lock(); concurrentErrors.append(error.localizedDescription); errorLock.unlock()
            }
        }
        check(concurrentErrors.isEmpty, "concurrent preferences remain readable")
        check(try store.setSoundEnabled(false) == false && CompletionReminderPreferencesStore(directory: directory).read() == false, "last explicit preference wins after concurrency")
        let leftovers = try fm.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".completion-reminders-") }
        check(leftovers.isEmpty, "atomic writes leave no temporary files")

        if failures.isEmpty { print("PASS: \(checks) completion chime signal and preference checks (no audio playback)") }
        else { failures.forEach { print("FAIL: \($0)") }; exit(1) }
    }
}
