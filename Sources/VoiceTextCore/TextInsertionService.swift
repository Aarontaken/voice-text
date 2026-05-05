import AppKit
import ApplicationServices
import Foundation

/// 文本插入策略融合了常见开源实践（例如 [vox-ops](https://github.com/EricGrill/vox-ops) ClipboardInjector / AccessibilityInjector）：
/// - 以前台应用为根查询 `kAXFocusedUIElementAttribute`，避免仅依赖 system-wide 焦点在部分场景下不稳定。
/// - 剪贴板模拟粘贴使用 `CGEventSource(stateID: .combinedSessionState)` 与 `.cgAnnotatedSessionEventTap`，更易投递到当前前台应用（含终端模拟器）。
/// - 粘贴前后保留短延迟，并在结束后恢复剪贴板内容。
public final class TextInsertionService {
    public enum InsertionError: Error {
        case accessibilityPermissionMissing
        case noFocusedElement
        case pasteboardWriteFailed
    }

    /// 这类应用里无障碍「写入选区/整值」常不可靠，直接与浏览器、编辑器等区分，优先走剪贴板 + 合成 ⌘V（与多数开源语音/效率工具一致）。
    private static let bundleIDsPreferringClipboardOnly: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "org.wezfurlong.wezterm",
        "co.zeit.hyper",
        "org.tabby",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
    ]

    public init() {}

    public func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func insert(_ text: String) throws {
        guard !text.isEmpty else { return }

        let isTrusted = ensureAccessibilityPermission(prompt: false)
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let clipboardFirst = bundleID.map { Self.bundleIDsPreferringClipboardOnly.contains($0) } ?? false

        VoiceTextLogger.log(
            "Text insertion accessibilityTrusted=\(isTrusted) frontmostBundle=\(bundleID ?? "nil") clipboardFirst=\(clipboardFirst)"
        )

        if clipboardFirst {
            try pastePreservingPasteboard(text)
            VoiceTextLogger.log("Text insertion clipboard-first path count=\(text.count)")
            return
        }

        if isTrusted, insertViaFrontmostAccessibility(text) {
            VoiceTextLogger.log("Text inserted with accessibility count=\(text.count)")
            return
        }

        VoiceTextLogger.log("Text insertion falling back to paste count=\(text.count)")
        try pastePreservingPasteboard(text)
    }

    /// 以前台应用的 accessibility 树根查找焦点元素（与 system-wide 方式互补，终端等场景更稳）。
    private func insertViaFrontmostAccessibility(_ text: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            VoiceTextLogger.log("Text AX no frontmost application")
            return false
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRaw: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRaw)
        guard focusErr == .success, let focusedRaw else {
            VoiceTextLogger.log("Text AX focused element failed result=\(focusErr.rawValue)")
            return false
        }
        guard CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else {
            VoiceTextLogger.log("Text AX focused value is not AXUIElement")
            return false
        }
        let axElement = focusedRaw as! AXUIElement

        var selectedRange: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)
        if rangeErr == .success {
            let setErr = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            VoiceTextLogger.log("Text AX selectedText after rangeProbe result=\(setErr.rawValue)")
            if setErr == .success {
                return true
            }
        }

        let setDirectErr = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        VoiceTextLogger.log("Text AX selectedText direct result=\(setDirectErr.rawValue)")
        if setDirectErr == .success {
            return true
        }

        var valueRef: CFTypeRef?
        let copyValueErr = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef)
        guard copyValueErr == .success, let currentValue = valueRef as? String else {
            VoiceTextLogger.log("Text AX value copy failed result=\(copyValueErr.rawValue)")
            return false
        }

        let newValue = currentValue + text
        let setValueErr = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, newValue as CFTypeRef)
        VoiceTextLogger.log("Text AX value append result=\(setValueErr.rawValue)")
        return setValueErr == .success
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

    private func pastePreservingPasteboard(_ text: String) throws {
        let snapshot = snapshotGeneralPasteboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restoreGeneralPasteboard(snapshot: snapshot)
            throw InsertionError.pasteboardWriteFailed
        }

        usleep(100_000)

        sendAnnotatedCommandV()

        usleep(300_000)

        restoreGeneralPasteboard(snapshot: snapshot)
        VoiceTextLogger.log("Text pasted count=\(text.count)")
    }

    private func sendAnnotatedCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            VoiceTextLogger.log("Text paste CGEvent create failed")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        usleep(10_000)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
