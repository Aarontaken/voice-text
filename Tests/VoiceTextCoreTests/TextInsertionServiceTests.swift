import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import VoiceTextCore

final class TextInsertionServiceTests: XCTestCase {
    // MARK: - 投递路线
    //
    // AX（kAXSelectedText）写入在 Chromium/Electron 里会「返回成功但不落字」，实测命中
    // VSCode、Chrome、Codex 等一大票 App；而按 App 维护白名单永远追不上。
    // 业界（YAP / parrot / Talkify / openless）的做法是：**一律剪贴板 + ⌘V**。

    func testEveryAppUsesClipboardPaste() {
        XCTAssertEqual(TextInsertionService.route(secureInputEnabled: false), .clipboardPaste)
    }

    func testSecureInputAlwaysRoutesToClipboardOnly() {
        // 安全键盘输入期间合成按键会被系统全局吞掉，不能假装粘贴成功。
        XCTAssertEqual(TextInsertionService.route(secureInputEnabled: true), .clipboardOnly)
    }

    // MARK: - 合成 ⌘V

    func testPasteCommandPostsFourEventsSoChromiumKeepsTheShortcut() {
        // Chromium/Electron 从原始事件流重建修饰键状态：只给 V 带 .maskCommand 标志而不真正
        // 按下 Command，粘贴会静默失败。必须发完整的四个事件。
        let events = TextInsertionService.makePasteEvents()

        XCTAssertEqual(events.count, 4)
        // 修饰键的按下/松开天然是 flagsChanged 事件，和物理按 Command 一致。
        XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(
            events.map { CGKeyCode($0.getIntegerValueField(.keyboardEventKeycode)) },
            [CGKeyCode(kVK_Command), CGKeyCode(kVK_ANSI_V), CGKeyCode(kVK_ANSI_V), CGKeyCode(kVK_Command)]
        )
        XCTAssertTrue(events[0].flags.contains(.maskCommand))
        XCTAssertTrue(events[1].flags.contains(.maskCommand))
        XCTAssertTrue(events[2].flags.contains(.maskCommand))
        XCTAssertFalse(events[3].flags.contains(.maskCommand), "最后一个事件必须真正松开 Command")
    }

    func testPasteCommandUsesDeviceDependentLeftCommandBit() {
        // YAP 记录：Qt / Java 应用只认设备相关的「左 Command 物理按下」位。
        let events = TextInsertionService.makePasteEvents()
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0].flags.rawValue & 0x8, 0x8, "Command down 需要带 NX_DEVICELCMDKEYMASK")
    }

    // MARK: - 剪贴板恢复时机

    func testClipboardRestoreDelayToleratesAsyncChromiumPasteboardReads() {
        // YAP 实测：Chromium 异步读剪贴板，0.1s 恢复太紧（粘贴静默无输出），0.5s 才稳。
        XCTAssertGreaterThanOrEqual(TextInsertionService.clipboardRestoreDelay, 0.5)
    }

    func testPrePasteDelayIsKeptShortButNonZero() {
        let delay = TextInsertionService.prePasteDelay
        XCTAssertGreaterThan(delay, 0)
        XCTAssertLessThanOrEqual(delay, 0.2)
    }
}
