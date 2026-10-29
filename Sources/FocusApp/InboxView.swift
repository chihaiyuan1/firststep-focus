import SwiftUI
import FocusCore

private let inboxInk = Color(red: 0.17, green: 0.20, blue: 0.16)
private let inboxQuiet = Color(red: 0.50, green: 0.53, blue: 0.47)
private let inboxSage = Color(red: 0.38, green: 0.46, blue: 0.32)
private let inboxPaper = Color(red: 0.96, green: 0.96, blue: 0.93)

struct InboxView: View {
    @ObservedObject var model: AppModel
    @State private var title = ""
    @State private var editing: InboxItem?
    @State private var scheduling: InboxItem?
    @SwiftUI.FocusState private var captureFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("收集箱").font(.system(size: 26, weight: .semibold))
                Text("先记下来，想做时再安排到今天。").font(.system(size: 13)).foregroundStyle(inboxQuiet)
            }
            HStack(spacing: 12) {
                TextField("记下一件事，按回车收进来", text: $title).textFieldStyle(.roundedBorder).font(.system(size: 14)).focused($captureFocused).onSubmit { capture() }
                Button { capture() } label: { Label("收进来", systemImage: "plus") }.buttonStyle(SoftButton(primary: true)).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(20).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            if model.lastDeletedInboxID != nil {
                HStack(spacing: 8) { Text("已删除一件事。").foregroundStyle(inboxQuiet); Button("撤销删除") { model.undoInboxDeletion() }.buttonStyle(.plain).foregroundStyle(inboxSage) }.font(.system(size: 12))
            }
            if model.inboxItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 32)).foregroundStyle(inboxSage)
                    Text("想到的事，先放在这里").font(.system(size: 15, weight: .medium))
                    Text("不用现在就做。准备好时，再移到「今天的事」。").font(.system(size: 12)).foregroundStyle(inboxQuiet)
                }.frame(maxWidth: .infinity).padding(.vertical, 52)
            } else {
                HStack { Text("暂存的事").font(.system(size: 14, weight: .medium)); Spacer(); Text("\(model.inboxItems.count) 件").font(.system(size: 11)).foregroundStyle(inboxQuiet) }
                LazyVStack(spacing: 12) {
                    ForEach(model.inboxItems) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "tray").font(.system(size: 17)).foregroundStyle(inboxSage)
                            Text(item.title).font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            if let day = item.scheduledDay { Text(day).font(.system(size: 10)).foregroundStyle(inboxQuiet) }
                            Button("移到今天") { _ = model.moveInboxToToday(item.id) }.buttonStyle(SoftButton())
                            Menu {
                                Button("修改标题") { editing = item }
                                Button("安排日期或提醒") { scheduling = item }
                                Button("删除", role: .destructive) { model.removeInboxItem(item.id) }
                            } label: { Image(systemName: "ellipsis").frame(width: 20) }.menuStyle(.borderlessButton).frame(width: 24).accessibilityLabel("操作 \(item.title)")
                        }.padding(16).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            Text("定期回看，把准备做的事写成一个能开始的动作。所有内容仅保存在本机。").font(.system(size: 11)).foregroundStyle(inboxQuiet).lineSpacing(4)
        }.foregroundStyle(inboxInk)
        .sheet(item: $editing) { item in InboxTitleEditor(model: model, item: item) }
        .sheet(item: $scheduling) { item in ScheduleEditor(model: model, id: item.id, title: item.title, isInbox: true, day: item.scheduledDay, reminderAt: item.reminderAt) }
    }
    private func capture() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if model.send(Command("addInbox", title: title)) { title = ""; captureFocused = true }
    }
}

private struct InboxTitleEditor: View {
    @ObservedObject var model: AppModel
    let item: InboxItem
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @SwiftUI.FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("修改标题").font(.system(size: 23, weight: .semibold))
            TextField("这件事是什么？", text: $title).textFieldStyle(.roundedBorder).font(.system(size: 14)).focused($focused).onSubmit { save() }
            Text("可以把它写成一个能开始的动作。").font(.system(size: 12)).foregroundStyle(inboxQuiet)
            HStack { Spacer(); Button("取消") { dismiss() }.buttonStyle(SoftButton()); Button("保存") { save() }.buttonStyle(SoftButton(primary: true)).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(30).frame(width: 440).background(inboxPaper).foregroundStyle(inboxInk)
        .onAppear { title = item.title; focused = true }
    }
    private func save() { if model.send(Command("editInbox", taskID: item.id, title: title)) { dismiss() } }
}
