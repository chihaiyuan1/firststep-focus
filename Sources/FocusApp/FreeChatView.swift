import SwiftUI
import AppKit
import FocusCore

struct FreeChatView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var assistant:AIModel
    @ObservedObject var chat:ChatModel
    @State private var history=false
    @State private var confirmNew=false
    private let purple=Color(red:0.41,green:0.32,blue:0.66)
    var body:some View {
        let result=Result {try ChatDayContext.capture(state:model.state,entries:model.timeEntries,now:Date(timeIntervalSince1970:model.now))}
        let context=try? result.get()
        return VStack(alignment:.leading,spacing:16) {
            HStack {
                VStack(alignment:.leading,spacing:5) {Text("自由对话").font(.system(size:18,weight:.semibold));Text(chat.title).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)}
                Spacer()
                Button("对话记录") {chat.reloadHistory();history=true}.disabled(chat.busy || chat.needsSave)
                Button {if chat.needsSave {confirmNew=true} else {chat.newConversation()}} label:{Label("新建对话",systemImage:"square.and.pencil")}
            }.buttonStyle(.borderless)
            if let context {source(context)}
            else if case .failure(let error)=result {Label(error.localizedDescription,systemImage:"exclamationmark.circle").font(.system(size:12)).foregroundStyle(.orange)}
            ScrollViewReader {proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        if chat.messages.isEmpty && chat.pendingQuestion==nil {
                            VStack(alignment:.leading,spacing:10) {Label("有问题，随时聊一聊",systemImage:"bubble.left.and.bubble.right").font(.system(size:16,weight:.medium)).foregroundStyle(purple);Text("可以问今天先做什么、怎样调整安排，也可以聊你遇到的其他问题。无需选择任务，可以一直追问。").font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(4)}.padding(24).frame(maxWidth:.infinity,alignment:.leading)
                        }
                        ForEach(chat.messages) {message in bubble(message).id(message.id)}
                        if let question=chat.pendingQuestion {bubble(question).id(question.id)}
                        if chat.busy {HStack(spacing:9) {ProgressView().controlSize(.small);Text("正在结合今天的记录思考…").font(.system(size:12)).foregroundStyle(.secondary)}.padding(.horizontal,18)}
                        Color.clear.frame(height:1).id("bottom")
                    }.padding(14)
                }.frame(height:280).background(.white.opacity(0.8),in:RoundedRectangle(cornerRadius:14))
                .onChange(of:chat.messages.count) {_ in proxy.scrollTo("bottom",anchor:.bottom)}
                .onChange(of:chat.busy) {_ in proxy.scrollTo("bottom",anchor:.bottom)}
                .onAppear {proxy.scrollTo("bottom",anchor:.bottom)}
            }
            if let error=chat.error {
                HStack(alignment:.top,spacing:8) {Image(systemName:"exclamationmark.circle");Text(error).textSelection(.enabled);Spacer();Button("收起") {chat.error=nil}.buttonStyle(.plain)}.font(.system(size:12)).foregroundStyle(.orange)
            }
            if chat.needsSave {HStack {Text(chat.status).font(.system(size:11)).foregroundStyle(.secondary);Spacer();Button("重新保存") {chat.retrySave()}}}
            VStack(alignment:.leading,spacing:10) {
                TextEditor(text:$chat.draft).font(.system(size:13)).frame(height:80).padding(8).background(.white,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(purple.opacity(0.2))).accessibilityLabel("自由对话输入").disabled(chat.busy || assistant.busy || assistant.signingIn)
                HStack {
                    Text(chat.busy ? "仅完整回复会保存" : chat.status.isEmpty ? "⌘↵ 发送，回车换行" : chat.status).font(.system(size:10)).foregroundStyle(.secondary)
                    Spacer()
                    if chat.busy {Button("取消") {chat.cancel()}.buttonStyle(SoftButton())}
                    else {Button("发送") {chat.send(state:model.state,entries:model.timeEntries,accountID:assistant.accountID,modelID:assistant.modelID)}.buttonStyle(SoftButton(primary:true)).keyboardShortcut(.return,modifiers:.command).disabled(!assistant.canSend || chat.needsSave || context==nil || chat.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
                }
            }
            Text("点击发送时附上今天的记录和本对话最近 5 轮问答；完整历史保存在本机。AI 不会自动修改任务、日程或启动番茄钟。使用当前所选 ChatGPT 模型与套餐额度。").font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(4)
        }
        .sheet(isPresented:$history) {historySheet}
        .alert("当前回答尚未保存",isPresented:$confirmNew) {Button("留在这里",role:.cancel) {};Button("另开新对话") {chat.newConversation()}} message:{Text("新建后将清空当前页面，建议先重新保存或复制回答。已保存的历史不会删除。")}
    }
    private func source(_ context:ChatDayContext)->some View {
        DisclosureGroup {
            contextDetails(context)
        } label:{VStack(alignment:.leading,spacing:4) {Text("默认附上今天 · \(context.day)").font(.system(size:12,weight:.medium));Text("\(context.taskCount) 件任务 · \(context.timeEntryCount) 条时间记录 · \(context.focusCount) 条专注记录").font(.system(size:10)).foregroundStyle(.secondary)}}
        .padding(14).background(purple.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
    }
    private func bubble(_ message:ChatMessage)->some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {Text(message.role=="user" ? "你" : "AI 助手").font(.system(size:11,weight:.semibold)).foregroundStyle(message.role=="user" ? .secondary : purple);Spacer();Button {NSPasteboard.general.clearContents();NSPasteboard.general.setString(message.content,forType:.string)} label:{Image(systemName:"doc.on.doc")}.buttonStyle(.plain).accessibilityLabel("复制\(message.role=="user" ? "问题" : "回答")")}
            if message.role=="assistant" {Text(.init(message.content)).font(.system(size:13)).lineSpacing(5).textSelection(.enabled)}
            else {Text(message.content).font(.system(size:13)).lineSpacing(5).textSelection(.enabled)}
            if let context=message.context {DisclosureGroup("附上 \(context.day) 的记录") {contextDetails(context)}.font(.system(size:10)).foregroundStyle(.secondary)}
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(message.role=="user" ? purple.opacity(0.06) : .white,in:RoundedRectangle(cornerRadius:12))
    }
    private var historySheet:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Text("对话记录").font(.title3);Spacer();Button("关闭") {history=false}}
            if chat.conversations.isEmpty {Text("发起一次对话后，完整问答会自动保存在这里。").foregroundStyle(.secondary).frame(maxHeight:.infinity)}
            else {ScrollView {VStack(spacing:10) {ForEach(chat.conversations) {item in
                Button {chat.open(item.id);history=false} label:{VStack(alignment:.leading,spacing:6) {Text(item.title).font(.system(size:13,weight:.medium)).lineLimit(2);HStack {Text(Date(timeIntervalSince1970:item.updatedAt),format:.dateTime.month().day().hour().minute());Text("\(item.messages.count/2) 轮问答")}.font(.system(size:10)).foregroundStyle(.secondary)}.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.black.opacity(0.035),in:RoundedRectangle(cornerRadius:10)).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("打开对话 \(item.title)，\(item.messages.count/2) 轮问答")
            }}}}
        }.padding(24).frame(width:500,height:460)
    }
    private func contextDetails(_ context:ChatDayContext)->some View {
        VStack(alignment:.leading,spacing:7) {ForEach(Array(context.previewLines.enumerated()),id:\.offset) {_,line in Text(line).textSelection(.enabled)}}.font(.system(size:11)).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.top,10)
    }
}
