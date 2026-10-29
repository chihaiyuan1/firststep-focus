import SwiftUI
import FocusCore

struct SessionReflectionSummary: View {
    @ObservedObject var model: AppModel
    let record: FocusRecord
    var compact = false
    private var entry: SessionReflection? { model.reflection(for: record.id) }
    private let sage = Color(red: 0.38, green: 0.46, blue: 0.32)
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("本轮想法", systemImage: "text.bubble").font(.system(size: 10, weight: .medium)).foregroundStyle(sage)
                if entry?.draft != nil { Text("有未提交草稿").font(.system(size: 9)).foregroundStyle(.secondary) }
                Spacer()
                Button(entry?.draft != nil ? "继续填写" : entry?.text.isEmpty == false ? "编辑想法" : "记录想法") {
                    model.showReflection?(record)
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(sage)
                    .accessibilityLabel("\(record.displayTitle)，填写或修改本轮想法")
            }
            if model.reflectionError != nil {
                Text("想法暂时无法读取，原文件已保留。").font(.system(size: 10)).foregroundStyle(.orange)
            } else if let text = entry?.text, !text.isEmpty {
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(compact ? 2 : 4).textSelection(.enabled)
            } else if !compact {
                Text(entry?.draft != nil ? "草稿留在本机，点击继续填写；保存后才会用于 AI。" : "这一轮有什么发现或想法？可以随时补写。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
