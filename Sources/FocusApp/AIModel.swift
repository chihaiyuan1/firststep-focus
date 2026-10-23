import SwiftUI
import AppKit
import FocusCore
import FocusAI

@MainActor final class AIModel: ObservableObject {
    @Published var accounts:[ChatGPTAccount]=[]
    @Published var accountID=""
    @Published var models:[ChatGPTModel]=[]
    @Published var modelID=""
    @Published var busy=false
    @Published var signingIn=false
    @Published var status=""
    @Published var error:String?
    @Published var journalError:String?
    @Published var reply:AssistantReply?
    @Published var steps:[String]=[]
    @Published var answer=""
    @Published var round=0
    @Published var kind="task"
    @Published var reviewDate=Date()
    @Published var taskID=""
    @Published var journal:[AIJournalEntry]=[]
    @Published var adopted=false
    private(set) var expectedTaskVersion=""
    private(set) var turns:[AITurn]=[]
    private var title=""
    private var contextDay=""
    private var requestTask:Task<Void,Never>?
    private var requestID=UUID()
    private var loadTask:Task<Void,Never>?
    private var loadID=UUID()
    private var loaded=false
    let service:ChatGPTService
    let journalStore:AIJournalStore
    private let preferences:URL
    init(directory:URL) {
        service=ChatGPTService(directory:directory.appendingPathComponent("AI"))
        journalStore=AIJournalStore(directory:directory)
        preferences=directory.appendingPathComponent("ai-preferences.json")
        if let data=try? Data(contentsOf:preferences),let prefs=try? JSONDecoder().decode([String:String].self,from:data) {
            accountID=prefs["account"] ?? "";modelID=prefs["model"] ?? ""
        }
        reloadJournal()
    }
    var connected:Bool {accounts.contains {$0.id==accountID && $0.isAuthorized} && !modelID.isEmpty && models.contains {$0.id==modelID} }
    var canSend:Bool {connected && !busy && !signingIn}
    var day:String {TimeGrid.dayKey(reviewDate)}
    func loadIfNeeded() {if !loaded {loaded=true;reloadAccounts()}}
    func reloadJournal() {
        do {journal=try journalStore.read();journalError=nil} catch {journalError=error.localizedDescription}
    }
    func reloadAccounts(select:String?=nil) {
        loadTask?.cancel();loadID=UUID();let id=loadID
        loadTask=Task {
            do {
                let values=try await service.accounts()
                guard !Task.isCancelled,loadID==id else {return}
                accounts=values
                if let select {accountID=select}
                if !values.contains(where:{$0.id==accountID}) {accountID=values.first(where:{$0.isAuthorized})?.id ?? values.first?.id ?? ""}
                guard values.contains(where:{$0.id==accountID && $0.isAuthorized}) else {models=[];modelID="";return}
                let selected=accountID
                let available=try await service.models(accountID:selected)
                guard !Task.isCancelled,loadID==id,accountID==selected else {return}
                models=available
                if !available.contains(where:{$0.id==modelID}) {modelID=available.first(where:{$0.id=="gpt-6.1-sol"})?.id ?? available.first?.id ?? ""}
                savePreferences();status="ChatGPT 已连接"
            } catch {if !Task.isCancelled,loadID==id {models=[];modelID="";self.error=error.localizedDescription}}
        }
    }
    func switchAccount() {cancel();models=[];modelID="";reloadAccounts()}
    func savePreferences() {
        if let data=try? JSONEncoder().encode(["account":accountID,"model":modelID]) {
            do {try data.write(to:preferences,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:preferences.path)} catch {self.error="默认模型设置未保存，下次打开可重新选择。"}
        }
    }
    func signIn(newAccount:Bool=false) {
        cancel();signingIn=true;error=nil;let generation=requestID
        let chosen = newAccount || accountID.isEmpty ? nil : accountID
        requestTask=Task {
            do {
                let url=try await service.beginSignIn(accountID:chosen)
                guard !Task.isCancelled,requestID==generation else {await service.cancelSignIn();return}
                guard NSWorkspace.shared.open(url) else {await service.cancelSignIn();throw FocusError("无法打开登录页，请检查默认浏览器设置")}
                status="请在官方页面完成登录授权"
                let account=try await service.completeSignIn()
                guard !Task.isCancelled,requestID==generation else {return}
                signingIn=false;reloadAccounts(select:account.id)
            } catch {if requestID==generation {if !Task.isCancelled {self.error=error.localizedDescription};signingIn=false}}
        }
    }
    func signOut() {
        cancel();loadTask?.cancel();loadID=UUID();let id=accountID;busy=true
        requestTask=Task {
            do {try await service.signOut(accountID:id);status="本机已退出 ChatGPT"} catch {self.error=error.localizedDescription}
            busy=false;models=[];modelID="";reloadAccounts()
        }
    }
    func cancel() {
        requestID=UUID();requestTask?.cancel();requestTask=nil;busy=false;signingIn=false
    }
    func reset() {cancel();reply=nil;steps=[];answer="";round=0;turns=[];expectedTaskVersion="";adopted=false;error=nil;status=""}
    func prepareTask(_ task:FocusTask) {
        reset();kind="task";taskID=task.id;title=task.title;expectedTaskVersion=task.editVersion
        contextDay=TimeGrid.dayKey(Date());turns=[AITurn(role:"user",content:AssistantPrompts.taskContext(task))]
    }
    func prepareReview(state:FocusCore.FocusState,entries:[TimeEntry]) {
        let supplement=answer.trimmingCharacters(in:.whitespacesAndNewlines)
        reset();kind="review";contextDay=day;title="\(day) 每日复盘"
        let context=AssistantPrompts.reviewContext(state:state,entries:entries,day:day)
        turns=[AITurn(role:"user",content:context+(supplement.isEmpty ? "" : "\n用户补充："+supplement))]
    }
    func ask() {send(stage:"questions",includeAnswer:round>0)}
    func suggest() {send(stage:"suggestion",includeAnswer:true)}
    private func send(stage:String,includeAnswer:Bool) {
        guard canSend,!turns.isEmpty else {return}
        if stage=="questions",round>=2 {error="已经聊过两轮，可以生成建议了。";return}
        var input=turns
        if includeAnswer {input.append(AITurn(role:"user",content:answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "请基于已有信息给出建议，未知项保留待确认。" : answer))}
        guard input.allSatisfy({$0.content.count<=16000}),input.count<=10 else {error="本次记录较多，请减少补充文字或选择一个更具体的任务。";return}
        busy=true;error=nil;status=stage=="questions" ? "正在想两个值得问的问题…" : "正在整理你的建议…"
        requestID=UUID();let generation=requestID, selectedAccount=accountID,selectedModel=modelID,currentKind=kind
        requestTask=Task {
            do {
                let raw=try await service.respond(accountID:selectedAccount,model:selectedModel,instructions:AssistantPrompts.instructions(kind:currentKind,stage:stage),messages:input.map {AIMessage(role:$0.role,content:$0.content)})
                try Task.checkCancellation()
                guard requestID==generation else {return}
                let result=try AssistantReply.parse(raw)
                let expected=stage=="questions" ? "questions" : (currentKind=="task" ? "taskPlan" : "review")
                guard result.kind==expected else {throw FocusError("AI 没有按当前步骤回答，请重试。")}
                turns=input+[AITurn(role:"assistant",content:raw)]
                reply=result;steps=result.steps;answer="";adopted=false
                if result.kind=="questions" {round+=1;status="第 \(round) 轮 · 想清楚一点再开始"}
                else {
                    let entry=AIJournalEntry(day:contextDay,kind:currentKind,taskID:currentKind=="task" ? taskID : nil,title:title,turns:turns,reply:result)
                    do {journal=try journalStore.append(entry);journalError=nil;status=currentKind=="review" ? "复盘已保存在本机" : "草案已生成，修改后再采用"}
                    catch {journalError=error.localizedDescription;status="建议已生成，但本地保存失败"}
                }
                busy=false
            } catch {if requestID==generation {busy=false;if !Task.isCancelled {self.error=error.localizedDescription;status="这次没有生成完整结果，可以重试"}}}
        }
    }
}
