import SwiftUI
import FocusCore
import FocusAI

@MainActor final class ChatModel:ObservableObject {
    typealias Responder=(String,String,String,[AIMessage]) async throws -> String
    @Published private(set) var conversations:[ChatConversation]=[]
    @Published private(set) var selectedID:String?
    @Published private(set) var messages:[ChatMessage]=[]
    @Published private(set) var pendingQuestion:ChatMessage?
    @Published private(set) var busy=false
    @Published private(set) var needsSave=false
    @Published var draft=""
    @Published var error:String?
    @Published private(set) var status=""
    private var revision=0
    private var conversationTitle="新的对话"
    private var request:Task<Void,Never>?
    private var generation=UUID()
    private let store:ChatStore
    private let responder:Responder
    private struct Completed {
        let id:String,title:String,revision:Int,question:ChatMessage,answer:ChatMessage
    }
    private var unsaved:Completed?
    var title:String {conversationTitle}
    init(directory:URL,responder:@escaping Responder) {
        store=ChatStore(directory:directory);self.responder=responder
        reloadHistory()
    }
    convenience init(directory:URL,service:ChatGPTService) {
        self.init(directory:directory,responder:{account,model,instructions,messages in
            try await service.respond(accountID:account,model:model,instructions:instructions,messages:messages)
        })
    }
    @discardableResult func reloadHistory()->Bool {
        do {conversations=try store.read();return true} catch {self.error=error.localizedDescription;return false}
    }
    func newConversation() {
        cancel();selectedID=nil;messages=[];revision=0;conversationTitle="新的对话"
        draft="";needsSave=false;unsaved=nil;error=nil;status=""
    }
    func open(_ id:String) {
        guard !needsSave else {return}
        guard reloadHistory() else {return}
        guard let item=conversations.first(where:{$0.id==id}) else {return}
        cancel();selectedID=id;messages=item.messages;revision=item.revision
        conversationTitle=item.title;draft="";error=nil;status="已打开本机对话"
    }
    func cancel() {
        let wasBusy=busy
        generation=UUID();request?.cancel();request=nil
        if let pendingQuestion {draft=pendingQuestion.content}
        pendingQuestion=nil;busy=false
        if wasBusy {status="已取消，问题已保留"}
    }
    func send(state:FocusCore.FocusState,entries:[TimeEntry],accountID:String,modelID:String,now:Date=Date(),reflections:[SessionReflection]=[]) {
        guard !busy,!needsSave,!accountID.isEmpty,!modelID.isEmpty else {return}
        do {
            let context=try ChatDayContext.capture(state:state,entries:entries,now:now,reflections:reflections)
            let question=draft.trimmingCharacters(in:.whitespacesAndNewlines)
            let turns=try ChatPrompts.messages(history:messages,question:question,context:context)
            let id=selectedID ?? UUID().uuidString
            let title=selectedID==nil ? String(question.prefix(30)) : conversationTitle
            let expected=revision
            let pending=ChatMessage(role:"user",content:question,createdAt:now.timeIntervalSince1970,context:context)
            pendingQuestion=pending;draft="";busy=true;error=nil;status="正在结合今天的记录思考…"
            generation=UUID();let current=generation
            request=Task {
                do {
                    let answer=try await responder(accountID,modelID,ChatPrompts.instructions,turns.map {AIMessage(role:$0.role,content:$0.content)})
                    try Task.checkCancellation()
                    guard generation==current else {return}
                    let text=answer.trimmingCharacters(in:.whitespacesAndNewlines)
                    guard !text.isEmpty,text.count<=16000 else {throw FocusError("回复为空或过长，请重新提问")}
                    let response=ChatMessage(role:"assistant",content:text)
                    messages.append(contentsOf:[pending,response]);selectedID=id;conversationTitle=title
                    pendingQuestion=nil;busy=false
                    unsaved=Completed(id:id,title:title,revision:expected,question:pending,answer:response)
                    saveCompleted()
                } catch {
                    guard generation==current else {return}
                    pendingQuestion=nil;busy=false;draft=question
                    if !Task.isCancelled {self.error=error.localizedDescription;status="这次没有生成完整回答，问题已保留，可再次发送"}
                }
            }
        } catch {self.error=error.localizedDescription}
    }
    func retrySave() {saveCompleted()}
    private func saveCompleted() {
        guard let value=unsaved else {return}
        do {
            conversations=try store.appendExchange(id:value.id,title:value.title,expectedRevision:value.revision,question:value.question,answer:value.answer)
            revision=conversations.first(where:{$0.id==value.id})?.revision ?? value.revision+1
            unsaved=nil;needsSave=false;error=nil;status="对话已保存在本机"
        } catch {
            needsSave=true;self.error=error.localizedDescription
            status="完整回答已显示，但还未保存；请重试保存或复制留存"
        }
    }
}
