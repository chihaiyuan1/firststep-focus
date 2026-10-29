import AppKit
import Combine
import FocusCore

@MainActor public final class CompletionReminderModel: ObservableObject {
    @Published public private(set) var soundEnabled = true
    @Published public private(set) var error: String?

    private let store: CompletionReminderPreferencesStore
    // Keep one player alive for the whole model lifetime. A new request replaces its playback.
    private let sound: NSSound?
    private var hardStopTask: Task<Void, Never>?
    private var preferenceError: String?
    private var playbackError: String?

    public init(directory: URL) {
        store = CompletionReminderPreferencesStore(directory: directory)
        sound = NSSound(data: CompletionChime.wavData())
        sound?.loops = false
        if sound == nil { playbackError = "结束铃声暂时无法准备，请重新启动应用后再试。" }
        do { soundEnabled = try store.read() }
        catch { preferenceError = error.localizedDescription }
        refreshError()
    }

    public func setSoundEnabled(_ enabled: Bool) {
        do {
            soundEnabled = try store.setSoundEnabled(enabled)
            preferenceError = nil
            if !enabled { stop() }
        } catch { preferenceError = error.localizedDescription }
        refreshError()
    }

    /// Re-read the persisted switch so a failed or externally changed preference is respected.
    public func playEnd() {
        do {
            soundEnabled = try store.read()
            preferenceError = nil
        } catch {
            preferenceError = error.localizedDescription
            stop(); refreshError()
            return
        }
        refreshError()
        guard soundEnabled else { stop(); return }
        playOnce()
    }

    /// Explicit user preview does not change the switch, timer state, or any focus records.
    public func preview() { playOnce() }

    public func stop() {
        hardStopTask?.cancel()
        hardStopTask = nil
        sound?.stop()
    }

    private func playOnce() {
        stop()
        guard let sound else {
            playbackError = "结束铃声暂时无法准备，请重新启动应用后再试。"
            refreshError(); return
        }
        sound.loops = false
        sound.currentTime = 0
        guard sound.play() else {
            playbackError = "结束铃声暂时无法播放，请检查系统声音输出后再试。"
            refreshError(); return
        }
        playbackError = nil
        refreshError()
        // The WAV ends at 2.5s itself; cancellation also caps a misbehaving player at 2.5s.
        hardStopTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 2_500_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func refreshError() { error = preferenceError ?? playbackError }

    deinit {
        hardStopTask?.cancel()
        sound?.stop()
    }
}
