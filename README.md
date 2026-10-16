# 先做一刻 · FirstStep

<p align="center"><img src="assets/AppIcon.png" width="128" alt="先做一刻图标"></p>

本地运行的 macOS 专注工具：任务、悬浮番茄钟、Chrome 分心网站屏蔽，以及每天 07:00–20:00 的手动时间记录。MIT 开源。

Mac 自用的轻量专注工具：写下今天的核心任务，选 15 / 25 / 30 / 45 分钟开始。右上角悬浮小窗显示当前任务与倒计时；Chrome 扩展暂时屏蔽雪球、X、微博。

## 首次使用

下载或克隆本仓库后安装。需要 macOS 13+、Swift Command Line Tools、Python 3；测试额外需要 Node.js 18+。当前在 Apple Silicon Mac 上验证，Intel 尚未实机验证。

```sh
xcode-select --install
python3 --version
```

如果已安装 Command Line Tools，可跳过第一条。

1. 双击本目录的 `安装.command`。应用安装到 `~/Applications/先做一刻.app`，随后自动打开。
2. 按 [安装说明](安装说明.md) 在自己的 Chrome 中加载本地扩展。已安装并连接的用户可以跳过。
3. 应用显示「Chrome 已连接」后，添加任务、选中任务，点击开始。扩展未连接时只能计时，界面会明确提示。

扩展目录：`~/Library/Application Support/FirstStep/ChromeExtension`。
Chrome 中打开 `chrome://extensions` → 开启「开发者模式」→「加载已解压的扩展程序」。文件选择框按 ⌘⇧G，输入上面的完整路径并选择该文件夹。Chrome 不必关闭；我们不接管你的浏览器。

无痕窗口需要在扩展详情中单独允许；其他 Chrome 用户配置需要分别加载。其他浏览器不在本版本的限制范围内。

## 使用约定

- 默认 15 分钟，下一步可不填。任务保留，未完成的任务次日仍可继续。
- 开始后，已经打开的相关网站也会进入拦截页；结束后恢复原网址。
- 临时访问：点击临时访问 → 可选填写原因 → 开始等待 30 秒 → 再次确认后，单站开放 5 分钟。不会自动放行。
- 提前结束和正常退出：先等待 30 秒，再确认。关闭主窗口不会结束计时。
- 浮窗可以拖动；菜单栏的倒计时可以重新打开主窗口。不会强制自动开始下一轮。
- 记录只保存在本机。临时放行时段从记录的专注时间中扣除；这表示可用时段，不监视你是否实际浏览。
- 主动停用扩展仍能绕过。扩展断连时按已知截止时间解除；电脑休眠期间不会唤醒电脑，恢复后重新核对时间。

## 时间记录

左侧点击「时间记录」即可使用。默认显示周一至周日，可以切换单日，或通过日期控件、前后箭头和「今天」回看其他日期。

- 每天 07:00–20:00；点击空白或拖选时间段，填写事情、日期、起止时间、颜色和可选备注，再保存。
- 点击已有记录修改。拖动卡片移动时间；周视图可横向拖到另一日。拉动上下边缘调整起止，拖动按半小时对齐；手工填写支持分钟精度。
- 重叠记录并排显示。删除后可点击「撤销」。
- 完全手动填写，不会把番茄钟记录自动放入日历。

「时间记录」是全天活动的手动回顾；「专注记录」是番茄钟自动生成的明细。两者可以涵盖同一段时间，时长不应相加，也无需把每轮番茄钟重新抄入时间记录。左下角「今天已专注」只按番茄钟记录计算。

## 数据和卸载

专注任务与记录：`~/Library/Application Support/FirstStep/state.json`；手动时间记录：同目录下的 `time-records.json`。退出应用后可复制此目录备份。不要在专注进行中手动修改数据。

卸载：先结束专注；在 Chrome 删除「先做一刻 · 专注守护」扩展；退出并移除 `~/Applications/先做一刻.app`。本地主机配置位于 `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.dayuan.firststep.json`，可移除。个人记录默认保留在 FirstStep 目录，是否删除由你决定。

## 构建和验证

运行要求 macOS 13+，源码使用 Swift 5.9+。已在 Apple Silicon / macOS 26.6.2、Swift 6.4 CLT + macOS 26.5 SDK 构建；脚本自动选择 SDK 和当前架构的构建路径。部分 SDK 27 CLT 缺少 SwiftUI 宏插件时，会尝试已安装的同目录 26.5 SDK，也可用 `FIRSTSTEP_SWIFT_SDK=/path/to/MacOSX.sdk` 指定。无 npm 依赖，不需要 Xcode 完整版。

```sh
./scripts/test-core.sh
./scripts/test-time-log.sh
./scripts/build.sh
node --test Tests/*.test.mjs
python3 Tests/native_protocol.py
./scripts/test-app-model.sh
./scripts/install.sh
```

应用使用本地 ad-hoc 签名，仅供本机使用，没有 Apple 公证。测试结果及实机验证范围见 `docs/verification.md`。

实现：SwiftUI / AppKit + Chrome Manifest V3 + Native Messaging。Swift 状态机负责等待和放行；文件锁与原子写入避免多进程覆盖。扩展只申请受限站点权限，不读取工作网站正文；不修改系统 hosts 文件。

接口依据（核查日期 2026-10-16）：[Chrome DNR](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest)、[Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)。


## 开源与贡献

代码采用 [MIT License](LICENSE)。应用图标由 AI 生成，选用的紫色版本保存在 `assets/AppIcon.png`。欢迎通过 Issue 描述问题、复现步骤、系统/Chrome 版本；提交记录或截图前请自行移除个人信息。

本仓库只包含程序、图标、测试和说明，不包含用户的任务、时间记录、浏览器配置或授权信息。
