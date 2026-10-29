import SwiftUI
import AppKit
import FocusCore

struct AIView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var assistant:AIModel
    @State private var history:AIJournalEntry?
    @State private var accountExpanded=false
    private let purple=Color(red:0.41,green:0.32,blue:0.66)
    private var tasks:[FocusTask] {model.todayTasks.filter {!$0.completed}}
    private var chosen:FocusTask? {tasks.first {$0.id==assistant.taskID}}
    private var daily:DailyForest {DailyForest(records:model.state.history,on:assistant.reviewDate)}
    var body:some View {
        VStack(alignment:.leading,spacing:assistant.kind=="chat" ? 12 : 22) {
            HStack {
                VStack(alignment:.leading,spacing:7) {Text("AI 助手").font(.system(size:26,weight:.semibold));Text("把事情想具体，把下一步变轻一点。").font(.system(size:13)).foregroundStyle(.secondary)}
                Spacer()
                Label(assistant.connected ? "ChatGPT 已连接" : "连接 ChatGPT",systemImage:assistant.connected ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark").font(.system(size:11)).foregroundStyle(purple)
            }
            accountCard
            Picker("助手功能",selection:$assistant.kind) {Text("任务拆解").tag("task");Text("每日复盘").tag("review");Text("每周复盘").tag("weeklyReview");Text("自由对话").tag("chat")}.pickerStyle(.segmented).frame(maxWidth:550)
            if assistant.kind=="task" {taskSource} else if assistant.kind=="review" {reviewSource} else if assistant.kind=="weeklyReview" {weeklyReviewSource} else {FreeChatView(model:model,assistant:assistant,chat:assistant.chat)}
            if let error=assistant.error {HStack(alignment:.top) {Image(systemName:"exclamationmark.circle");Text(error).textSelection(.enabled);Spacer();Button("收起") {assistant.error=nil}.buttonStyle(.plain)}.font(.system(size:12)).foregroundStyle(Color(red:0.64,green:0.32,blue:0.16)).padding(14).background(.orange.opacity(0.06),in:RoundedRectangle(cornerRadius:12))}
            if assistant.busy || assistant.signingIn {HStack {ProgressView().controlSize(.small);Text(assistant.status).font(.system(size:12));Spacer();Button("取消") {assistant.cancel()}}.padding(16).background(.white.opacity(0.7),in:RoundedRectangle(cornerRadius:12))}
            if assistant.kind != "chat",let reply=assistant.reply {replyCard(reply)}
            if assistant.kind != "chat",let error=assistant.journalError {Label(error,systemImage:"externaldrive.badge.exclamationmark").font(.system(size:11)).foregroundStyle(.orange)}
            if assistant.kind=="review" || assistant.kind=="weeklyReview" {reviewHistory}
            if assistant.kind != "chat" {Text("点击后才会发送本次任务或所选日期的记录与回答。AI 建议供你修改采用；不会自动调整任务、日程或启动番茄钟。Plus 套餐额度与其他接入应用共享。").font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4)}
        }
        .onAppear {assistant.loadIfNeeded();useRequestedTask();if assistant.accounts.isEmpty {accountExpanded=true};if assistant.taskID.isEmpty {assistant.taskID=tasks.first?.id ?? ""}}
        .onChange(of:model.aiTaskID) {_ in useRequestedTask()}
        .onChange(of:assistant.connected) {connected in if connected {accountExpanded=false}}
        .onChange(of:assistant.kind) {_ in assistant.reset()}
        .onChange(of:assistant.taskID) {_ in if assistant.kind=="task" {assistant.reset()}}
        .onChange(of:assistant.day) {_ in if assistant.kind=="review" || assistant.kind=="weeklyReview" {assistant.reset()}}
        .sheet(item:$history) {entry in
            VStack(alignment:.leading,spacing:16) {
                HStack {Text(entry.title).font(.title3);Spacer();Button("关闭") {history=nil}}
                Text(Date(timeIntervalSince1970:entry.createdAt),format:.dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        Text(entry.reply.message).textSelection(.enabled).lineSpacing(5)
                        ForEach(Array(entry.reply.steps.enumerated()),id:\.offset) {i,step in Text("\(i+1). \(step)").textSelection(.enabled)}
                        if let source=entry.turns.first(where:{$0.role=="user"})?.content,source.hasPrefix("{") {
                            DisclosureGroup("生成时附上的已保存想法") {
                                VStack(alignment:.leading,spacing:8) {
                                    ForEach(Array(AssistantPrompts.reflectionPreviewLines(context:source).enumerated()),id:\.offset) {_,line in Text(line).textSelection(.enabled)}
                                }.font(.system(size:11)).padding(.top,8)
                            }
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }.padding(28).frame(width:560,height:530)
        }
    }
    private var accountCard:some View {
        DisclosureGroup(isExpanded:$accountExpanded) {
            VStack(alignment:.leading,spacing:12) {
                if !assistant.accounts.isEmpty {
                    Picker("账号",selection:$assistant.accountID) {ForEach(assistant.accounts) {account in Text(account.label+(account.isAuthorized ? "" : "（已退出）")).tag(account.id)}}
                        .disabled(assistant.busy || assistant.signingIn || assistant.chat.busy).onChange(of:assistant.accountID) {_ in assistant.switchAccount()}
                }
                if !assistant.models.isEmpty {Picker("模型",selection:$assistant.modelID) {ForEach(assistant.models) {item in Text(item.name).tag(item.id)}}.disabled(assistant.busy || assistant.chat.busy).onChange(of:assistant.modelID) {_ in assistant.modelSelectionChanged()}}
                HStack {
                    Button(assistant.accounts.contains(where:{$0.id==assistant.accountID && $0.isAuthorized}) ? "重新连接" : "Continue with ChatGPT") {assistant.signIn()}.buttonStyle(SoftButton(primary:true))
                    if !assistant.accounts.isEmpty {Button("添加账号") {assistant.signIn(newAccount:true)}.buttonStyle(SoftButton())}
                    if assistant.accounts.contains(where:{$0.id==assistant.accountID && $0.isAuthorized}) {Button("退出账号") {assistant.signOut()}.buttonStyle(.borderless)}
                }.disabled(assistant.busy || assistant.signingIn || assistant.chat.busy)
                HStack {Button("刷新连接") {assistant.error=nil;assistant.reloadAccounts()};Button("查看 ChatGPT 用量") {NSWorkspace.shared.open(URL(string:"https://chatgpt.com/settings/usage")!)}}.font(.system(size:11)).buttonStyle(.link).disabled(assistant.busy || assistant.signingIn || assistant.chat.busy)
                Text("使用官方 ChatGPT 账号授权，无需 API Key。授权保存在本机；退出账号不删除任务和复盘。").font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(.top,14)
        } label:{Label("账号与模型",systemImage:"person.crop.circle").font(.system(size:12,weight:.medium))}
        .padding(assistant.kind=="chat" ? 10 : 16).background(purple.opacity(0.06),in:RoundedRectangle(cornerRadius:14))
        .onChange(of:assistant.accounts.count) {count in if count==0 {accountExpanded=true}}
    }
    private var taskSource:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("先选一件想推进的事").font(.system(size:16,weight:.semibold))
            if tasks.isEmpty {Text("先到「今天的事」添加或恢复一个任务，再回来一起拆解。").font(.system(size:13)).foregroundStyle(.secondary);Button("去添加任务") {model.page="today"}.buttonStyle(SoftButton())}
            else {
                Picker("主任务",selection:$assistant.taskID) {Text("请选择").tag("");ForEach(tasks) {task in Text(task.title).tag(task.id)}}.labelsHidden().disabled(assistant.busy)
                Text("先聊 1–2 轮，弄清目标和困难；再把建议变成你能开始的小任务。").font(.system(size:12)).foregroundStyle(.secondary)
                if assistant.reply==nil && !assistant.busy {
                    Button("先聊一聊") {if let task=chosen {assistant.prepareTask(task);assistant.ask()}}.buttonStyle(SoftButton(primary:true)).disabled(!assistant.canSend || chosen==nil || model.state.session?.taskID==assistant.taskID)
                    if model.state.session?.taskID==assistant.taskID {Text("这一轮结束后，再拆解当前任务。").font(.caption).foregroundStyle(.secondary)}
                }
            }
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.75),in:RoundedRectangle(cornerRadius:16))
    }
    private var reviewSource:some View {
        let reflectionContext=assistant.reviewSourceContext ?? AssistantPrompts.reviewContext(state:model.state,entries:model.timeEntries,day:assistant.day,reflections:model.reflections)
        return VStack(alignment:.leading,spacing:14) {
            HStack {Text("回看这一天").font(.system(size:16,weight:.semibold));Spacer();DatePicker("复盘日期",selection:$assistant.reviewDate,in:...Date(),displayedComponents:.date).labelsHidden().disabled(assistant.busy)}
            HStack(spacing:30) {metric("专注时长","\(daily.focusMinutes) 分钟");metric("完成番茄钟","\(daily.completedCount) 个");metric("手动时间记录","\(model.timeEntries.filter {$0.day==assistant.day && $0.deletedAt==nil}.count) 条")}
            DisclosureGroup("将使用这一天的任务、专注、时间记录和已保存想法") {
                VStack(alignment:.leading,spacing:8) {
                    ForEach(AssistantPrompts.reviewTasks(state:model.state,day:assistant.day,entries:model.timeEntries)) {task in
                        Text("任务 · \(task.title)")
                        ForEach(task.steps) {step in Text("  小任务 · \(step.title)")}
                    }
                    ForEach(daily.records) {record in Text("专注 · \(record.displayTitle) · \(Int(record.focusSeconds/60)) 分钟")}
                    ForEach(model.timeEntries.filter {$0.day==assistant.day && $0.deletedAt==nil}) {entry in Text("\(time(entry.startMinute))–\(time(entry.endMinute)) · \(entry.title)"+(entry.taskID == nil ? "" : " · 关联任务："+(entry.linkedTaskTitle(tasks:model.state.tasks) ?? "原任务名称未知"))+(entry.note.isEmpty ? "" : "\n\(entry.note)"))}
                    ForEach(Array(AssistantPrompts.reflectionPreviewLines(context:reflectionContext).enumerated()),id:\.offset) {_,line in Text(line).textSelection(.enabled)}
                    Text("记录可能重叠，不相加；任务完成状态以目前保存的状态为准。想法是用户主观记录，草稿不发送。")
                }.font(.system(size:11)).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.top,10)
            }.font(.system(size:12))
            if assistant.reply==nil && !assistant.busy {
                Text("想补充今天的成果、困难或临时安排吗？（选填）").font(.system(size:12))
                input
                Button("开始复盘") {
                    do {
                        let reflections=try model.reflectionsForAI()
                        if assistant.prepareReview(state:model.state,entries:model.timeEntries,reflections:reflections) {assistant.ask()}
                    } catch {assistant.error=error.localizedDescription}
                }.buttonStyle(SoftButton(primary:true)).disabled(!assistant.canSend)
            }
        }.padding(20).background(.white.opacity(0.75),in:RoundedRectangle(cornerRadius:16))
    }
    private var weeklyReviewSource: some View {
        let stats = FocusStatistics(records: model.state.history, on: assistant.reviewDate, scope: .week)
        let weekStart = TimeGrid.dayKey(stats.interval.start), weekEnd = TimeGrid.dayKey(stats.interval.end)
        let completionCount = model.state.completionHistory.filter { $0.completedAt.map { $0 >= stats.interval.start.timeIntervalSince1970 && $0 < stats.interval.end.timeIntervalSince1970 } == true }.count
        let logCount = model.timeEntries.filter { $0.deletedAt == nil && $0.day >= weekStart && $0.day < weekEnd }.count
        let source = assistant.reviewSourceContext ?? AssistantPrompts.weeklyReviewContext(state:model.state, entries:model.timeEntries, on:assistant.reviewDate, reflections:model.reflections)
        return VStack(alignment:.leading, spacing:14) {
            HStack { Text("回看这一周").font(.system(size:16,weight:.semibold)); Spacer(); DatePicker("选择周内日期", selection:$assistant.reviewDate, in:...Date(), displayedComponents:.date).labelsHidden().disabled(assistant.busy) }
            Text("\(weekStart) 至 \(TimeGrid.dayKey(Calendar.current.date(byAdding:.day,value:-1,to:stats.interval.end) ?? stats.interval.start)) · 周一至周日").font(.system(size:12)).foregroundStyle(.secondary)
            HStack(spacing:24) { metric("专注时长","\(Int(stats.totalFocusSeconds / 60)) 分钟"); metric("完成番茄钟","\(stats.completedCount) 个"); metric("完成记录","\(completionCount) 条"); metric("时间记录","\(logCount) 条") }
            DisclosureGroup("查看将发送的本周资料") {
                ScrollView { VStack(alignment:.leading,spacing:6) { ForEach(Array(AssistantPrompts.weeklyReviewPreviewLines(context:source).enumerated()),id:\.offset) { _, line in Text(line).textSelection(.enabled) } }.font(.system(size:11)).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:220).padding(.top,8)
                Text("包括本周完成记录、相关任务及计划在所选周或更早、目前未完成的旧任务的当前状态、专注、手动时间记录和已保存的想法；不包含习惯。完成任务的番茄数和时长是截至完成时的历史累计，记录可能重叠，不相加。") .font(.system(size:11)).foregroundStyle(.secondary)
            }
            if assistant.reply == nil && !assistant.busy {
                Text("想补充这一周的成果或困难吗？（选填）").font(.system(size:12)); input
                Button("开始每周复盘") {
                    do {
                        model.refreshTimeLog(force:true)
                        if let error = model.timeLogError { throw FocusError(error) }
                        let thoughts = try model.reflectionsForAI()
                        if assistant.prepareWeeklyReview(state:model.state, entries:model.timeEntries, reflections:thoughts) { assistant.ask() }
                    } catch { assistant.error = error.localizedDescription }
                }.buttonStyle(SoftButton(primary:true)).disabled(!assistant.canSend || model.stateUnavailable)
            }
        }.padding(20).background(.white.opacity(0.75),in:RoundedRectangle(cornerRadius:16))
    }
    @ViewBuilder private func replyCard(_ reply:AssistantReply)->some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Label(reply.kind=="questions" ? "先弄清楚两件事" : reply.kind=="taskPlan" ? "可以这样开始" : (assistant.kind=="weeklyReview" ? "这一周的复盘" : "这一天的复盘"),systemImage:"sparkles").font(.system(size:16,weight:.semibold)).foregroundStyle(purple);Spacer();if !assistant.busy {Button("重新开始") {assistant.reset()}.font(.system(size:11)).buttonStyle(.plain)}}
            Text(reply.message).font(.system(size:13)).lineSpacing(5).textSelection(.enabled)
            if reply.kind=="questions" {
                ForEach(Array(reply.questions.enumerated()),id:\.offset) {i,question in Text("\(i+1). \(question)").font(.system(size:14,weight:.medium)).textSelection(.enabled)}
                input
                HStack {
                    Button(assistant.kind=="task" ? "根据回答给建议" : "生成复盘") {assistant.suggest()}.buttonStyle(SoftButton(primary:true)).disabled(!assistant.canSend)
                    if assistant.round<2 {Button("再问我一轮") {assistant.ask()}.buttonStyle(SoftButton()).disabled(!assistant.canSend || assistant.answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
                }
                Text("第 \(assistant.round) 轮 / 最多 2 轮。也可以不补充，让 AI 将未知项保留待确认。").font(.system(size:10)).foregroundStyle(.secondary)
            } else if reply.kind=="taskPlan" {
                Text("可以修改、删除建议的小任务，再加入主任务。已有小任务会保留。").font(.system(size:12)).foregroundStyle(.secondary)
                ForEach(assistant.steps.indices,id:\.self) {index in
                    HStack {Text("\(index+1).").foregroundStyle(.secondary);TextField("一个具体动作",text:$assistant.steps[index]).textFieldStyle(.roundedBorder);Button {assistant.steps.remove(at:index)} label:{Image(systemName:"minus.circle")}.buttonStyle(.plain).accessibilityLabel("移除建议 \(index+1)")}.disabled(assistant.adopted || assistant.busy)
                }
                Button(assistant.adopted ? "已加入主任务" : "采用这些小任务") {
                    guard let task=chosen, !assistant.steps.isEmpty else {return}
                    if model.send(Command("appendSubtasks",taskID:task.id,subtaskTitles:assistant.steps,expectedTaskVersion:assistant.expectedTaskVersion)) {assistant.adopted=true;model.selectTask(task.id)}
                }.buttonStyle(SoftButton(primary:true)).disabled(assistant.adopted || assistant.busy || assistant.steps.isEmpty || chosen==nil || model.state.session?.taskID==assistant.taskID)
                if assistant.adopted {Button("去选一个小任务开始") {model.page="today"}.buttonStyle(.link)}
            } else {
                if !reply.steps.isEmpty {Text(assistant.kind=="weeklyReview" ? "下周可以先做" : "明天可以先做").font(.system(size:13,weight:.semibold));ForEach(Array(reply.steps.enumerated()),id:\.offset) {i,step in Text("\(i+1). \(step)").font(.system(size:13)).textSelection(.enabled)}}
                Text("依据发起复盘时的记录生成；新增记录后可以重新复盘，旧版本仍会保留。").font(.system(size:11)).foregroundStyle(.secondary)
            }
            Text(assistant.status).font(.system(size:11)).foregroundStyle(.secondary)
        }.padding(22).background(.white,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(purple.opacity(0.14)))
    }
    private var reviewHistory:some View {
        let key = assistant.kind == "weeklyReview" ? TimeGrid.dayKey(FocusStatisticsScope.week.interval(containing:assistant.reviewDate).start) : assistant.day
        let entries=assistant.journal.filter {$0.kind==assistant.kind && $0.day==key}
        return VStack(alignment:.leading,spacing:10) {
            if !entries.isEmpty {Text(assistant.kind == "weeklyReview" ? "这一周保存的复盘" : "这一天保存的复盘").font(.system(size:13,weight:.semibold));ForEach(entries) {entry in Button {history=entry} label:{HStack {Image(systemName:"doc.text");Text(Date(timeIntervalSince1970:entry.createdAt),format:.dateTime.hour().minute());Text(entry.reply.message.replacingOccurrences(of:"\n",with:" ")).lineLimit(1);Spacer();Image(systemName:"chevron.right")}.font(.system(size:12)).padding(12).background(.white.opacity(0.6),in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain)}}
        }
    }
    private var input:some View {TextEditor(text:$assistant.answer).font(.system(size:13)).frame(height:75).padding(6).background(.white,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(.gray.opacity(0.2))).disabled(assistant.busy).accessibilityLabel("回答或补充")}
    private func metric(_ title:String,_ value:String)->some View {VStack(alignment:.leading,spacing:5) {Text(title).font(.system(size:10)).foregroundStyle(.secondary);Text(value).font(.system(size:18,weight:.medium,design:.rounded))}}
    private func time(_ minutes:Int)->String {String(format:"%02d:%02d",minutes/60,minutes%60)}
    private func useRequestedTask() {if let id=model.aiTaskID {assistant.reset();assistant.kind="task";assistant.taskID=id;model.aiTaskID=nil}}
}
