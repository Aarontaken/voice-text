import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// 把识别结果写进当前焦点输入框。
///
/// **只有一条投递路径：剪贴板 + 合成 ⌘V。**
///
/// 为什么不再走 AX（`kAXSelectedText`）写入：Chromium / Electron 会**返回成功但不落字**
/// （`AXUIElementSetAttributeValue` 返回 `kAXErrorSuccess`，内容却没进编辑器）。
/// 实测命中 VSCode、Chrome、Codex 等；按 App 维护「坏名单」永远追不上新应用，
/// 而坏名单之外的应用会掉进这个静默失败里。
/// 业界主流（YAP / parrot / Talkify / openless；FluidVoice 的保底路径）同样是「一律粘贴」——
/// 它是唯一在原生、Electron、Web、终端里都工作的方式。
///
/// 其余关键点都来自现场踩坑：
/// - 合成 ⌘V 必须发完整四个事件并投到 `.cghidEventTap`：Chromium 会从原始事件流重建修饰键
///   状态，只给 V 带 `.maskCommand` 标志会让粘贴静默失败。
/// - 恢复剪贴板前要留足时间给**异步**读取者（Chromium），否则它拿到旧数据、粘贴无输出。
/// - 安全键盘输入 / 缺少辅助功能权限时合成按键会被系统丢弃，此时不要假装成功，
///   把识别结果留在剪贴板上交给用户。
public final class TextInsertionService {
    public enum InsertionError: Error {
        case accessibilityPermissionMissing
        case pasteboardWriteFailed
        /// 系统正处于安全键盘输入（通常是密码框），合成按键会被全局吞掉；文本已留在剪贴板。
        case secureInputActive
    }

    /// 一次插入的投递路线。
    enum InsertionRoute: Equatable {
        /// 只把文本放进剪贴板，不投递（安全输入或缺少辅助功能权限时，合成按键必然被丢弃）。
        case clipboardOnly
        /// 剪贴板 + 合成 ⌘V。现在是所有应用的唯一投递路径。
        case clipboardPaste
    }

    /// 合成 ⌘V 之前留给剪贴板服务器往返的时间。
    static let prePasteDelay: TimeInterval = 0.1

    /// 允许目标应用读取剪贴板的时间。
    ///
    /// Chromium/Electron（VSCode、Slack、Discord、Chrome）**异步**读取剪贴板，恢复太快会让它们
    /// 拿到旧数据、粘贴静默无输出（YAP 实测 0.1s 太紧、0.5s 才稳；openless 用 750ms）。
    static let clipboardRestoreDelay: TimeInterval = 0.5

    /// 四个合成事件之间的间隔，模拟真实按键节奏，避免被目标应用合并/丢弃。
    static let pasteKeyStepDelay: TimeInterval = 0.005

    /// `NX_DEVICELCMDKEYMASK`：设备相关的「左 Command 物理按下」位，Qt / Java 应用只认它。
    static let deviceLeftCommandMask: UInt64 = 0x0000_0008

    /// 决定这次插入走哪条路线。纯函数，便于单测。
    static func route(secureInputEnabled: Bool) -> InsertionRoute {
        secureInputEnabled ? .clipboardOnly : .clipboardPaste
    }

    public init() {}

    public func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 系统是否处于安全键盘输入（密码框等）。开启期间合成按键会被系统静默丢弃。
    static func isSecureEventInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    public func insert(_ text: String) throws {
        guard !text.isEmpty else { return }

        let isTrusted = ensureAccessibilityPermission(prompt: false)
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let secureInput = Self.isSecureEventInputEnabled()
        let route = Self.route(secureInputEnabled: secureInput)

        VoiceTextLogger.log(
            "Text insertion accessibilityTrusted=\(isTrusted) frontmostBundle=\(bundleID ?? "nil") secureInput=\(secureInput) route=\(route)"
        )

        // 没有辅助功能权限时合成按键会被系统丢弃；安全输入期间同理。
        // 两种情况都不要假装粘贴成功（否则文本写进剪贴板又马上恢复 = 把识别结果弄丢），
        // 直接把文本留在剪贴板上交给用户手动 ⌘V。
        if route == .clipboardOnly || !isTrusted {
            stageClipboardLeavingText(text)
            throw secureInput ? InsertionError.secureInputActive : InsertionError.accessibilityPermissionMissing
        }

        try pastePreservingPasteboard(text)
    }

    /// 每项为一块剪贴板条目的 `[类型, 数据]` 列表，便于原样恢复（类似剪贴板管理器的快照思路）。
    private func snapshotGeneralPasteboard() -> [[(NSPasteboard.PasteboardType, Data)]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
    }

    private func restoreGeneralPasteboard(snapshot: [[(NSPasteboard.PasteboardType, Data)]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        for pairs in snapshot {
            guard !pairs.isEmpty else { continue }
            let item = NSPasteboardItem()
            for (type, data) in pairs {
                item.setData(data, forType: type)
            }
            pb.writeObjects([item])
        }
    }

    /// 把文本留在剪贴板上（不做快照/恢复）：用于合成按键必然被丢弃的场景，
    /// 让用户至少能手动 ⌘V 取回识别结果。
    private func stageClipboardLeavingText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        VoiceTextLogger.log("Text left on clipboard count=\(text.count)")
    }

    private func pastePreservingPasteboard(_ text: String) throws {
        let snapshot = snapshotGeneralPasteboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restoreGeneralPasteboard(snapshot: snapshot)
            throw InsertionError.pasteboardWriteFailed
        }
        let stagedChangeCount = pasteboard.changeCount

        usleep(useconds_t(Self.prePasteDelay * 1_000_000))

        postPasteCommand()

        usleep(useconds_t(Self.clipboardRestoreDelay * 1_000_000))

        // 只在剪贴板仍是我们写进去的那一份时恢复，避免覆盖用户这期间的新复制。
        guard pasteboard.changeCount == stagedChangeCount else {
            VoiceTextLogger.log("Text pasted count=\(text.count) clipboardChangedByUser=true (kept user clipboard)")
            return
        }

        restoreGeneralPasteboard(snapshot: snapshot)
        VoiceTextLogger.log("Text pasted count=\(text.count)")
    }

    /// 合成一次 ⌘V。
    ///
    /// 两个独立开源实现的现场结论（YAP、FluidVoice）都指向同一件事：
    /// Chromium/Electron 会从原始事件流重建修饰键状态，**只给 V 带 `.maskCommand` 标志而不真正按下
    /// Command，粘贴会静默不生效**。所以这里发完整的四个事件，并投到 `.cghidEventTap`
    /// （硬件事件进入窗口服务器的位置），让 Chromium 当成真实按键处理。
    private func postPasteCommand() {
        let events = Self.makePasteEvents()
        guard !events.isEmpty else {
            VoiceTextLogger.log("Text paste CGEvent create failed")
            return
        }
        let stepMicros = useconds_t(Self.pasteKeyStepDelay * 1_000_000)
        for (index, event) in events.enumerated() {
            event.post(tap: .cghidEventTap)
            if index < events.count - 1, stepMicros > 0 {
                usleep(stepMicros)
            }
        }
    }

    /// Command down → V down → V up → Command up。
    ///
    /// 修饰键的按下/松开天然是 `.flagsChanged` 事件（和物理按 Command 一致），V 则是 `.keyDown`/`.keyUp`。
    /// 最后一个事件必须真正松开 Command：否则 HID 状态会一直认为 Command 按着，后续按键会被污染。
    static func makePasteEvents() -> [CGEvent] {
        let source = CGEventSource(stateID: .combinedSessionState)
        let commandKeyCode = CGKeyCode(kVK_Command)
        let pasteKeyCode = CGKeyCode(kVK_ANSI_V)

        guard
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: true),
            let pasteDown = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: true),
            let pasteUp = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: false)
        else { return [] }

        let commandFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | deviceLeftCommandMask)
        commandDown.flags = commandFlags
        pasteDown.flags = commandFlags
        pasteUp.flags = commandFlags
        commandUp.flags = []
        return [commandDown, pasteDown, pasteUp, commandUp]
    }
}
