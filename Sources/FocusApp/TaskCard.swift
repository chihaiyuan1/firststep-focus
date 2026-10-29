import SwiftUI
import FocusCore

struct TaskCard:View {
    @ObservedObject var model:AppModel
    let task:FocusTask
    let onEdit:()->Void
    let onDelete:()->Void
    @State private var editing=false
    @State private var stepID:String?
    @State private var title=""
    @State private var deleteStep:FocusSubtask?
    @State private var expanded=true
    @State private var scheduling=false
    private let sage=Color(red:0.38,green:0.46,blue:0.32)
    private var locked:Bool {model.state.session?.taskID==task.id}
    private var progress:TaskFocusProgress {model.state.taskProgress(taskID:task.id)}
    private var linkedEntries:[TimeEntry] { model.timeEntries.filter { $0.deletedAt == nil && $0.taskID == task.id }.sorted { ($0.day, $0.startMinute) > ($1.day, $1.startMinute) } }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:12) {
                Button {model.selectTask(task.id)} label: {Image(systemName:task.completed ? "checkmark.circle.fill" : model.selectedTask==task.id ? "largecircle.fill.circle" : "circle").font(.system(size:20)).foregroundStyle(sage)}.buttonStyle(.plain).disabled(task.completed || model.state.session != nil).accessibilityLabel("选择任务 \(task.title)")
                VStack(alignment:.leading,spacing:5) {
                    Text(task.title).font(.system(size:14,weight:.medium)).strikethrough(task.completed)
                    PomodoroProgressView(completed:progress.completedPomodoros,estimated:task.estimatedPomodoros,isCompleted:task.completed)
                    HStack(spacing:12) {
                        Text("累计专注 \(focusDuration(progress.focusSeconds))")
                        if let estimate=task.estimatedPomodoros,progress.completedPomodoros>estimate {Text("比预估多 \(progress.completedPomodoros-estimate) 轮，可继续专注").foregroundStyle(Color(red:0.67,green:0.47,blue:0.30))}
                    }.font(.system(size:10)).foregroundStyle(.secondary)
                        .help("累计投入包含主任务与小任务，同一轮只计算一次。提前结束保留实际专注时长，不增加完整番茄。")
                    if !task.nextStep.isEmpty {Text(task.nextStep).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(2)}
                    if !task.steps.isEmpty {Text("\(task.steps.filter(\.completed).count)/\(task.steps.count) 个小任务已完成").font(.system(size:11)).foregroundStyle(sage)}
                    else if task.day != FocusCore.FocusState.day(at:model.now) {Text("之前未完成，继续也可以").font(.system(size:10)).foregroundStyle(.secondary)}
                }
                Spacer()
                if !task.steps.isEmpty {Button {expanded.toggle()} label:{Image(systemName:expanded ? "chevron.up" : "chevron.down")}.buttonStyle(.plain).accessibilityLabel(expanded ? "收起小任务" : "展开小任务")}
                Menu {
                    Button("AI 帮我拆解") {model.openAI(taskID:task.id)}.disabled(task.completed)
                    Button("添加小任务") {stepID=nil;title="";editing=true}.disabled(task.completed || task.steps.count>=30)
                    Divider()
                    Button(task.completed ? "恢复为未完成" : "标记主任务完成") {_=model.send(Command("completeTask",taskID:task.id))}
                    Button("修改主任务",action:onEdit)
                    Button("安排日期或提醒") {scheduling=true}
                    Button("移到今天") {_=model.send(Command("moveToday",taskID:task.id))}
                    Divider();Button("删除主任务",role:.destructive,action:onDelete)
                } label:{Image(systemName:"ellipsis").frame(width:20)}.menuStyle(.borderlessButton).frame(width:24).disabled(locked)
            }
            if expanded && !task.steps.isEmpty {
                Divider().opacity(0.5)
                ForEach(Array(task.steps.enumerated()),id:\.element.id) {index,step in
                    HStack(alignment:.top,spacing:10) {
                        Button {_=model.send(Command("completeSubtask",taskID:task.id,subtaskID:step.id))} label:{Image(systemName:step.completed ? "checkmark.square.fill" : "square").foregroundStyle(sage)}.buttonStyle(.plain).disabled(locked || task.completed).accessibilityLabel("\(step.completed ? "恢复" : "完成")小任务 \(step.title)")
                        Button {model.selectTask(task.id,subtaskID:step.id)} label: {
                            HStack(alignment:.top,spacing:7) {
                                Text("\(index+1).").foregroundStyle(.secondary)
                                Text(step.title).strikethrough(step.completed).multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading)
                                if model.selectedTask==task.id && model.selectedSubtask==step.id {Text("已选中").font(.system(size:10)).foregroundStyle(sage)}
                            }.font(.system(size:12)).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(step.completed || task.completed || model.state.session != nil).accessibilityLabel("选择小任务 \(step.title)")
                        Menu {
                            Button("修改小任务") {stepID=step.id;title=step.title;editing=true}
                            Button("删除小任务",role:.destructive) {deleteStep=step}
                        } label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).frame(width:20).disabled(locked)
                    }.padding(9).background(model.selectedTask==task.id && model.selectedSubtask==step.id ? sage.opacity(0.09) : .clear,in:RoundedRectangle(cornerRadius:8))
                }
                Text(task.steps.allSatisfy(\.completed) && !task.completed ? "小任务都完成了，可以在菜单中标记主任务完成。" : "点击文字选中小任务；勾选表示事情做完了。").font(.system(size:10)).foregroundStyle(.secondary)
            }
            if !linkedEntries.isEmpty {
                DisclosureGroup("关联时间记录（\(linkedEntries.count)）") {
                    VStack(alignment:.leading,spacing:6) {
                        ForEach(linkedEntries) { entry in
                            Text("\(entry.day) \(String(format:"%02d:%02d–%02d:%02d",entry.startMinute/60,entry.startMinute%60,entry.endMinute/60,entry.endMinute%60)) · \(entry.title)")
                        }
                        Text("手动记录与专注可能重叠，不相加。").foregroundStyle(.secondary)
                    }.font(.system(size:11)).frame(maxWidth:.infinity,alignment:.leading).padding(.top,6)
                }.font(.system(size:11)).foregroundStyle(sage)
            }
        }.padding(16).background(.white.opacity(model.selectedTask==task.id ? 0.95 : 0.55),in:RoundedRectangle(cornerRadius:12))
        .sheet(isPresented:$scheduling) {ScheduleEditor(model:model,id:task.id,title:task.title,isInbox:false,day:task.scheduledDay,reminderAt:task.reminderAt)}
        .sheet(isPresented:$editing) {
            VStack(alignment:.leading,spacing:18) {
                Text(stepID==nil ? "添加一个能开始的小任务" : "修改小任务").font(.title3)
                TextField("例如：列出需要准备的三份资料",text:$title).textFieldStyle(.roundedBorder)
                HStack {Spacer();Button("取消") {editing=false};Button("保存") {
                    let command = stepID.map {Command("editSubtask",taskID:task.id,title:title,subtaskID:$0)} ?? Command("appendSubtasks",taskID:task.id,subtaskTitles:[title])
                    if model.send(command) {editing=false}
                }.keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
            }.padding(28).frame(width:430)
        }
        .alert("删除这个小任务？",isPresented:Binding(get:{deleteStep != nil},set:{if !$0 {deleteStep=nil}})) {
            Button("取消",role:.cancel) {deleteStep=nil}
            Button("删除",role:.destructive) {if let step=deleteStep {_=model.send(Command("deleteSubtask",taskID:task.id,subtaskID:step.id))};deleteStep=nil}
        } message:{Text("已经产生的专注记录会保留。")}
    }
    private func focusDuration(_ value:Double)->String {
        let seconds=Int(max(0,value).rounded(.down))
        if seconds==0 {return "0 分钟"}
        if seconds<60 {return "\(seconds) 秒"}
        let minutes=seconds/60
        if minutes<60 {return "\(minutes) 分钟"}
        let hours=minutes/60,remainder=minutes%60
        return remainder==0 ? "\(hours) 小时" : "\(hours) 小时 \(remainder) 分钟"
    }
}
