import SwiftUI
import AppKit
import FocusCore

private let siteInk = Color(red: 0.17, green: 0.20, blue: 0.16)
private let siteQuiet = Color(red: 0.50, green: 0.53, blue: 0.47)
private let siteAccent = Color(red: 0.46, green: 0.36, blue: 0.70)

struct BlockedSitesView: View {
    @ObservedObject var model: AppModel
    @State private var input = ""
    private var locked: Bool { model.state.session != nil }
    private var preview: String? { try? BlockedSite.normalizedDomain(input) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("屏蔽网站").font(.system(size: 26, weight: .semibold))
                Text("把容易分心的网站，留到这一轮结束后。").font(.system(size: 13)).foregroundStyle(siteQuiet)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("添加一个网站").font(.system(size: 14, weight: .medium))
                HStack(spacing: 10) {
                    TextField("粘贴网址或域名，例如 bilibili.com", text: $input).textFieldStyle(.roundedBorder).font(.system(size: 13)).onSubmit { add() }
                    Button("粘贴") { input = NSPasteboard.general.string(forType: .string) ?? "" }.buttonStyle(SoftButton())
                    Button("加入屏蔽") { add() }.buttonStyle(SoftButton(primary: true)).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.blockedSites.count >= 100)
                }.disabled(locked)
                if let preview { Text("将屏蔽 \(preview) 及其子域；网址路径和参数不会保存。").font(.system(size: 12)).foregroundStyle(siteAccent) }
                else { Text("支持完整的 http/https 网址或域名；保存后屏蔽该域名及其子域。").font(.system(size: 12)).foregroundStyle(siteQuiet) }
            }.padding(20).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            if locked { Label("正在专注，这一轮结束后可修改列表。临时访问仍需等待 30 秒。", systemImage: "lock.fill").font(.system(size: 12)).foregroundStyle(siteAccent) }
            if !model.extensionConnected { Label(model.extensionConnectionHint, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Color(red: 0.60, green: 0.43, blue: 0.25)).lineSpacing(4) }
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("专注时屏蔽").font(.system(size: 14, weight: .medium)); Spacer(); Text("\(model.blockedSites.count) / 100").font(.system(size: 11)).foregroundStyle(siteQuiet) }
                if model.blockedSites.isEmpty { Text("还没有屏蔽网站。添加后，下一轮专注会使用这份列表。").font(.system(size: 13)).foregroundStyle(siteQuiet).padding(.vertical, 24) }
                ForEach(model.blockedSites) { entry in
                    HStack(spacing: 14) {
                        Image(systemName: "globe").font(.system(size: 19)).foregroundStyle(siteAccent).frame(width: 34, height: 34).background(siteAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.name).font(.system(size: 14, weight: .medium))
                            Text(entry.domains.joined(separator: "、") + " 及其子域").font(.system(size: 11)).foregroundStyle(siteQuiet).textSelection(.enabled)
                        }
                        Spacer()
                        Button { _ = model.send(Command("removeBlockedSite", site: entry.site)) } label: { Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(siteQuiet).padding(8) }.buttonStyle(.plain).disabled(locked).accessibilityLabel("移除 \(entry.site)").help("移出屏蔽列表")
                    }.padding(16).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Text("仅在专注期间屏蔽，结束后自动恢复。列表只保存在本机，不读取网页正文。").font(.system(size: 11)).foregroundStyle(siteQuiet).lineSpacing(4)
        }.foregroundStyle(siteInk)
    }
    private func add() {
        guard !locked, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if model.send(Command("addBlockedSite", site: input)) { input = "" }
    }
}
