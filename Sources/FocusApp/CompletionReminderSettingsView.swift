import SwiftUI

private let reminderInk = Color(red: 0.17, green: 0.20, blue: 0.16)
private let reminderQuiet = Color(red: 0.50, green: 0.53, blue: 0.47)
private let reminderWarning = Color(red: 0.65, green: 0.35, blue: 0.24)

struct CompletionReminderSettingsView: View {
    @ObservedObject var reminders: CompletionReminderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("专注结束提醒").font(.system(size: 17, weight: .semibold))
            HStack(spacing: 16) {
                Toggle("结束时播放柔和铃声", isOn: Binding(
                    get: { reminders.soundEnabled },
                    set: { reminders.setSoundEnabled($0) }
                )).toggleStyle(.switch)
                Spacer(minLength: 8)
                Button {
                    reminders.preview()
                } label: {
                    Label("试听", systemImage: "speaker.wave.2")
                }.buttonStyle(.bordered)
                    .accessibilityLabel("试听一次 2.5 秒结束铃声")
            }.font(.system(size: 13))
            Text("每轮结束时响一次，2.5 秒后自动停止，音量跟随系统。")
                .font(.system(size: 12)).foregroundStyle(reminderQuiet)
                .fixedSize(horizontal: false, vertical: true)
            Text("点击「试听」可听一次；不会启动专注或写入记录，关闭开关后也能试听。")
                .font(.system(size: 11)).foregroundStyle(reminderQuiet)
                .fixedSize(horizontal: false, vertical: true)
            if let error = reminders.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(reminderWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.foregroundStyle(reminderInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
    }
}
