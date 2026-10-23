import SwiftUI
import FocusCore

private let ink = Color(red: 0.17, green: 0.20, blue: 0.16)
private let sage = Color(red: 0.38, green: 0.46, blue: 0.32)
private let paper = Color(red: 0.96, green: 0.96, blue: 0.93)
private let quiet = Color(red: 0.50, green: 0.53, blue: 0.47)

struct SoftButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundStyle(primary ? .white : ink)
            .background(primary ? sage : Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
struct MainView: View {
    @ObservedObject var model: AppModel
    @StateObject private var assistant: AIModel
    init(model: AppModel) { self.model=model; _assistant=StateObject(wrappedValue:AIModel(directory:model.store.directory)) }
    @State private var editor = false
    @State private var editing: FocusTask?
    @State private var deleteTask: FocusTask?
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) { Image(systemName: "circle.lefthalf.filled").font(.system(size: 23)); Text("先做一刻").font(.system(size: 19, weight: .semibold)) }.padding(.bottom, 6)
                Text("让开始，轻一点。").font(.system(size: 12)).foregroundStyle(quiet).padding(.bottom, 32)
                nav("today", "今天的事", "sun.max")
                nav("inbox", "收集箱", "tray")
                nav("time", "时间记录", "calendar")
                nav("history", "专注记录", "clock")
                nav("sites", "屏蔽网站", "hand.raised")
                nav("ai", "AI 助手", "sparkles")
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text("今天已专注").font(.system(size: 11)).foregroundStyle(quiet)
                    HStack(alignment: .firstTextBaseline, spacing: 4) { Text("\(model.todayMinutes)").font(.system(size: 35, weight: .light, design: .rounded)); Text("分钟").font(.system(size: 11)).foregroundStyle(quiet) }
                    Divider()
                    Label(model.extensionConnectionLabel, systemImage: model.extensionConnected ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 11)).foregroundStyle(model.extensionConnected ? sage : quiet)
                }
            }.padding(24).frame(width: 190).frame(maxHeight: .infinity).background(Color.white.opacity(0.6))
            if model.page == "time" {
                TimeLogView(model: model)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if model.page == "ai" { AIView(model: model, assistant: assistant) }
                        else if model.page == "inbox" { InboxView(model: model) }
                        else if model.page == "sites" { BlockedSitesView(model: model) }
                        else if model.page == "history" { ForestView(model: model) }
                        else { today }
                    }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.background(paper).foregroundStyle(ink).frame(minWidth: 790, minHeight: 590).preferredColorScheme(.light)
        .sheet(isPresented: $editor) { TaskEditor(model: model, task: editing) }
        .sheet(isPresented: Binding(get: { model.state.pending?.kind == "end" }, set: { if !$0 { model.cancelEnd() } })) { endSheet }
        .alert("暂时无法完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("知道了") { model.error = nil } } message: { Text(model.error ?? "") }
        .alert("删除这件事？", isPresented: Binding(get: { deleteTask != nil }, set: { if !$0 { deleteTask = nil } })) {
            Button("取消", role: .cancel) { deleteTask = nil }
            Button("删除", role: .destructive) { if let task = deleteTask { _ = model.send(Command("deleteTask", taskID: task.id)) }; deleteTask = nil }
        } message: { Text("已有的专注记录会保留。") }
    }
    private func nav(_ id: String, _ title: String, _ icon: String) -> some View {
        Button { model.page = id } label: { Label(title, systemImage: icon).font(.system(size: 13, weight: model.page == id ? .medium : .regular)).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(model.page == id ? sage.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
    }
    private var today: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Text(Date(timeIntervalSince1970: model.now), format: .dateTime.month(.twoDigits).day(.twoDigits).weekday(.wide)).font(.system(size: 12)).foregroundStyle(quiet); Text("先做好眼前这一件").font(.system(size: 26, weight: .semibold)) }
                Spacer()
                Button { editing = nil; editor = true } label: { Label("添加任务", systemImage: "plus") }.buttonStyle(SoftButton())
            }
            if let s = model.state.session {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Label("正在专注", systemImage: "circle.lefthalf.filled").font(.system(size: 12)).foregroundStyle(sage); Spacer(); Button("显示悬浮窗") { model.toggleFloat?() }.buttonStyle(.plain).font(.system(size: 12)) }
                    Text(s.displayTitle).font(.system(size: 21, weight: .medium))
                    if s.subtaskTitle != nil || !s.nextStep.isEmpty { Text(s.subtaskTitle != nil ? s.title : "下一步：\(s.nextStep)").font(.system(size: 13)).foregroundStyle(quiet) }
                    HStack(alignment: .bottom) {
                        Text(clockText(model.remaining)).font(.system(size: 62, weight: .light, design: .rounded)).monospacedDigit()
                        Spacer(); Button("提前结束") { model.requestEnd() }.buttonStyle(SoftButton())
                    }
                    ProgressView(value: min(1, max(0, (model.now - s.startAt) / (s.endAt - s.startAt)))).tint(sage)
                    connectionHint
                }.padding(24).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
            } else if let until = model.state.breakUntil {
                HStack { VStack(alignment: .leading, spacing: 10) { Text("休息一下").font(.title2); Text(clockText(until - model.now)).font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit(); Text("起身走走，网站已恢复访问。").font(.caption).foregroundStyle(quiet) }; Spacer(); Button("结束休息") { _ = model.send(Command("endBreak")) }.buttonStyle(SoftButton()) }.padding(24).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
            } else {
                if let record = model.completion {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(record.finished ? "这一轮完成了" : "这一轮已结束", systemImage: "checkmark.circle.fill").foregroundStyle(sage)
                        Text(record.displayTitle).font(.system(size: 14))
                        HStack {
                            Button(record.subtaskID == nil ? "任务完成" : "小任务完成") { model.completeFocusedTask() }.buttonStyle(SoftButton())
                            Button("休息 5 分钟") { model.completion = nil; _ = model.send(Command("startBreak")) }.buttonStyle(SoftButton())
                            Button("继续做") { model.selectTask(record.taskID, subtaskID: record.subtaskID); model.completion = nil }.buttonStyle(.plain)
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(sage.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("给这件事一小段完整的时间").font(.system(size: 13)).foregroundStyle(quiet)
                    HStack(spacing: 8) {
                        ForEach([15,25,30,45], id: \.self) { value in
                            Button { model.minutes = value } label: { Text("\(value) 分钟").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 12).background(model.minutes == value ? sage.opacity(0.14) : .white.opacity(0.8), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(model.minutes == value ? sage.opacity(0.6) : .clear)) }.buttonStyle(.plain)
                        }
                    }
                    Button { model.start() } label: { HStack { Image(systemName: "play.fill"); Text("开始 \(model.minutes) 分钟"); Spacer(); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity) }.buttonStyle(SoftButton(primary: true)).disabled(!model.canStart).opacity(model.canStart ? 1 : 0.5)
                    connectionHint
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("今天的核心任务").font(.system(size: 13, weight: .semibold)); Spacer(); Text("通常 1–3 件就好").font(.system(size: 11)).foregroundStyle(quiet) }
                if model.todayTasks.isEmpty {
                    VStack(spacing: 12) { Image(systemName: "leaf").font(.system(size: 26)).foregroundStyle(sage); Text("写下一件你想推进的事").font(.system(size: 14)); Text("可以很小，比如「先写三句话」。").font(.system(size: 12)).foregroundStyle(quiet); Button("添加第一件事") { editing = nil; editor = true }.buttonStyle(SoftButton()) }.frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                ForEach(model.todayTasks) { task in taskRow(task) }
            }
        }
    }
    private var connectionHint: some View {
        HStack(alignment: .top, spacing: 7) { Image(systemName: model.extensionConnected ? "checkmark.shield" : "exclamationmark.circle"); Text(model.extensionConnected ? (model.blockedSites.isEmpty ? "屏蔽列表为空，本轮仅计时。" : "专注期间屏蔽列表中的 \(model.blockedSites.count) 组网站。") : model.extensionConnectionHint) }.font(.system(size: 11)).foregroundStyle(model.extensionConnected ? sage : Color(red: 0.60, green: 0.43, blue: 0.25))
    }
    private func taskRow(_ task: FocusTask) -> some View {
        TaskCard(model:model,task:task,onEdit:{editing=task;editor=true},onDelete:{deleteTask=task})
    }
    private var endSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("先停一下，再决定").font(.system(size: 23, weight: .semibold))
            Text("遇到困难也没关系。可以把下一步再缩小一点，或者结束这一轮。").font(.system(size: 13)).foregroundStyle(quiet)
            let left = max(0, (model.state.pending?.readyAt ?? model.now) - model.now)
            Text(left > 0 ? "\(Int(ceil(left))) 秒" : "现在可以结束了").font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit()
            HStack { Button("继续专注") { model.cancelEnd() }.buttonStyle(SoftButton(primary: true)); Button(model.wantsQuit ? "结束并退出" : "结束这一轮") { model.confirmEnd() }.buttonStyle(SoftButton()).disabled(left > 0) }
        }.padding(32).frame(width: 440).background(paper)
    }
}
struct TaskEditor: View {
    @ObservedObject var model: AppModel
    let task: FocusTask?
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var step = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(task == nil ? "今天想推进什么？" : "把任务写具体一点").font(.system(size: 23, weight: .semibold))
            TextField("例如：写公众号文章", text: $title).textFieldStyle(.roundedBorder).font(.system(size: 15))
            Text("下一步做什么（选填）").font(.system(size: 12)).foregroundStyle(quiet)
            TextField("例如：先写开头的三句话", text: $step).textFieldStyle(.roundedBorder)
            Text("不必把整件事想明白，先确定一个能开始的动作。").font(.system(size: 12)).foregroundStyle(quiet)
            HStack { Spacer(); Button("取消") { dismiss() }.buttonStyle(SoftButton()); Button(task == nil ? "添加任务" : "保存") { if model.send(Command(task == nil ? "addTask" : "editTask", taskID: task?.id, title: title, nextStep: step)) { if task == nil { model.selectedTask = model.state.tasks.last?.id }; dismiss() } }.buttonStyle(SoftButton(primary: true)).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(32).frame(width: 460).background(paper).onAppear { title = task?.title ?? ""; step = task?.nextStep ?? "" }
    }
}
struct FloatingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Image(systemName: "circle.lefthalf.filled").foregroundStyle(sage); Text(model.state.session != nil ? "先做这一件" : (model.state.breakUntil != nil ? "休息一下" : "这一轮完成了")).font(.system(size: 11)).foregroundStyle(quiet); Spacer(); Button { model.showMain?() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11)) }.buttonStyle(.plain).help("打开主窗口") }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) { Text(model.state.session?.displayTitle ?? "给自己一点空白").font(.system(size: 13, weight: .medium)).lineLimit(2); if let session = model.state.session, !session.nextStep.isEmpty || session.subtaskTitle != nil { Text(session.subtaskTitle != nil ? session.title : session.nextStep).font(.system(size: 10)).foregroundStyle(quiet).lineLimit(2) } }
                Spacer(minLength: 10)
                Text(clockText(model.remaining)).font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit()
            }
            HStack { Circle().fill(model.extensionConnected ? sage : Color.orange.opacity(0.7)).frame(width: 5, height: 5); Text(model.state.session == nil ? "网站已恢复访问" : (model.extensionConnected ? "信息流已暂时屏蔽" : "仅计时 · Chrome 未连接")).font(.system(size: 10)).foregroundStyle(quiet); Spacer(); if model.state.session != nil { Button("结束") { model.requestEnd() }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(quiet) } }
        }.padding(17).frame(width: 310, height: 144).background(paper).foregroundStyle(ink)
    }
}
