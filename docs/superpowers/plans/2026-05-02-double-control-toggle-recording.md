# Double Control Toggle Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second recording trigger so users can double-tap `Control` to start recording, keep recording while browsing files, and double-tap `Control` again to stop.

**Architecture:** Keep `RecordingController` as the single owner of ASR connection, audio capture, preview state, and text insertion. Replace the current hold-only Control observer with a Control trigger service that supports two trigger modes: hold mode and lock mode. Put double-tap timing logic in a small `VoiceTextCore` value type so it can be tested without AppKit or global keyboard events.

**Tech Stack:** Native macOS Swift, AppKit `NSEvent` modifier monitoring, Swift Package Manager tests, existing `RecordingController`, existing status bar/settings UI.

---

## Scope

Implement only trigger behavior and user-facing trigger descriptions:

- Keep the existing behavior: hold `Control` to start recording, release `Control` to stop.
- Add locked recording behavior: double-tap `Control` to start recording, then double-tap `Control` again to stop.
- While locked recording is active, pressing or holding `Control` must not accidentally stop recording on key release.
- If recording ends externally through the menu, ASR disconnect, failure, or settings reload, clear the trigger service's active mode.
- Do not change ASR protocol parsing, audio encoding, login, cookie refresh, text insertion, punctuation rules, or preview window styling.

## File Structure

- Create `Sources/VoiceTextCore/ControlKeyTapTracker.swift`
  - Pure timing helper for deciding whether two short `Control` taps form a double tap.
  - Does not know about AppKit, recording, or global event monitors.
- Create `Tests/VoiceTextCoreTests/ControlKeyTapTrackerTests.swift`
  - Unit tests for single tap, valid double tap, slow second tap, and long press exclusion.
- Rename `Sources/VoiceTextApp/HoldControlKeyService.swift` to `Sources/VoiceTextApp/ControlKeyRecordingTriggerService.swift`
  - Owns AppKit global/local `.flagsChanged` monitors.
  - Supports `.hold` and `.locked` recording modes.
  - Calls injected start/stop closures with the trigger mode.
- Modify `Sources/VoiceTextApp/AppDelegate.swift`
  - Store `ControlKeyRecordingTriggerService`.
  - Wire trigger starts to `RecordingController.start()`.
  - Wire trigger stops to `RecordingController.stop()`.
  - Reset trigger mode when recording reaches `.idle` or `.error`.
- Modify `Sources/VoiceTextApp/StatusBarController.swift`
  - Update menu text to mention both trigger modes.
- Modify `Sources/VoiceTextApp/SettingsWindowController.swift`
  - Update settings subtitle and hotkey label to mention both trigger modes.
- Modify `README.md`
  - Update usage/config docs so they no longer describe the trigger as only a generic global shortcut.

---

### Task 1: Add Pure Double-Tap Tracker

**Files:**

- Create: `Sources/VoiceTextCore/ControlKeyTapTracker.swift`
- Create: `Tests/VoiceTextCoreTests/ControlKeyTapTrackerTests.swift`
- **Step 1: Write failing tests**

Create `Tests/VoiceTextCoreTests/ControlKeyTapTrackerTests.swift`:

```swift
import XCTest
@testable import VoiceTextCore

final class ControlKeyTapTrackerTests: XCTestCase {
    func testSingleShortTapDoesNotTriggerDoubleTap() {
        var tracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)

        let didDoubleTap = tracker.recordTap(pressDuration: 0.08, releaseTime: 10.0)

        XCTAssertFalse(didDoubleTap)
    }

    func testTwoShortTapsWithinIntervalTriggerDoubleTap() {
        var tracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)

        XCTAssertFalse(tracker.recordTap(pressDuration: 0.07, releaseTime: 10.0))
        XCTAssertTrue(tracker.recordTap(pressDuration: 0.06, releaseTime: 10.25))
    }

    func testSecondTapAfterIntervalStartsNewSequence() {
        var tracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)

        XCTAssertFalse(tracker.recordTap(pressDuration: 0.07, releaseTime: 10.0))
        XCTAssertFalse(tracker.recordTap(pressDuration: 0.06, releaseTime: 10.5))
        XCTAssertTrue(tracker.recordTap(pressDuration: 0.06, releaseTime: 10.75))
    }

    func testLongPressDoesNotCountAsTap() {
        var tracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)

        XCTAssertFalse(tracker.recordTap(pressDuration: 0.08, releaseTime: 10.0))
        XCTAssertFalse(tracker.recordTap(pressDuration: 0.4, releaseTime: 10.2))
        XCTAssertFalse(tracker.recordTap(pressDuration: 0.08, releaseTime: 10.4))
    }

    func testResetClearsPendingTap() {
        var tracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)

        XCTAssertFalse(tracker.recordTap(pressDuration: 0.08, releaseTime: 10.0))
        tracker.reset()

        XCTAssertFalse(tracker.recordTap(pressDuration: 0.08, releaseTime: 10.2))
    }
}
```

- **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter ControlKeyTapTrackerTests
```

Expected: fail to compile with an error equivalent to `cannot find 'ControlKeyTapTracker' in scope`.

- **Step 3: Add minimal tracker implementation**

Create `Sources/VoiceTextCore/ControlKeyTapTracker.swift`:

```swift
import Foundation

public struct ControlKeyTapTracker {
    private let doubleTapInterval: TimeInterval
    private let maxTapDuration: TimeInterval
    private var lastTapReleaseTime: TimeInterval?

    public init(doubleTapInterval: TimeInterval, maxTapDuration: TimeInterval) {
        self.doubleTapInterval = doubleTapInterval
        self.maxTapDuration = maxTapDuration
    }

    public mutating func recordTap(pressDuration: TimeInterval, releaseTime: TimeInterval) -> Bool {
        guard pressDuration <= maxTapDuration else {
            reset()
            return false
        }

        if let lastTapReleaseTime, releaseTime - lastTapReleaseTime <= doubleTapInterval {
            reset()
            return true
        }

        lastTapReleaseTime = releaseTime
        return false
    }

    public mutating func reset() {
        lastTapReleaseTime = nil
    }
}
```

- **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter ControlKeyTapTrackerTests
```

Expected: exit code `0`, with `ControlKeyTapTrackerTests` passing.

- **Step 5: Commit**

Run:

```bash
git add Sources/VoiceTextCore/ControlKeyTapTracker.swift Tests/VoiceTextCoreTests/ControlKeyTapTrackerTests.swift
git commit -m "test: add control key double-tap tracker"
```

Expected: commit succeeds.

---

### Task 2: Replace Hold-Only Service With Dual-Mode Trigger Service

**Files:**

- Rename: `Sources/VoiceTextApp/HoldControlKeyService.swift` to `Sources/VoiceTextApp/ControlKeyRecordingTriggerService.swift`
- **Step 1: Rename the file**

Run:

```bash
git mv Sources/VoiceTextApp/HoldControlKeyService.swift Sources/VoiceTextApp/ControlKeyRecordingTriggerService.swift
```

Expected: file is renamed and still tracked by git.

- **Step 2: Replace the service implementation**

Replace the full contents of `Sources/VoiceTextApp/ControlKeyRecordingTriggerService.swift` with:

```swift
import AppKit
import VoiceTextCore

enum ControlRecordingTriggerMode {
    case hold
    case locked
}

final class ControlKeyRecordingTriggerService {
    private let holdThreshold: TimeInterval
    private let onRecordingStart: (ControlRecordingTriggerMode) -> Void
    private let onRecordingStop: (ControlRecordingTriggerMode) -> Void

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var holdTimer: Timer?
    private var tapTracker: ControlKeyTapTracker
    private var isControlPressed = false
    private var controlPressTime: TimeInterval?
    private var didBeginHold = false
    private var activeMode: ControlRecordingTriggerMode?

    init(
        holdThreshold: TimeInterval,
        doubleTapInterval: TimeInterval,
        maxTapDuration: TimeInterval,
        onRecordingStart: @escaping (ControlRecordingTriggerMode) -> Void,
        onRecordingStop: @escaping (ControlRecordingTriggerMode) -> Void
    ) {
        self.holdThreshold = holdThreshold
        self.tapTracker = ControlKeyTapTracker(
            doubleTapInterval: doubleTapInterval,
            maxTapDuration: maxTapDuration
        )
        self.onRecordingStart = onRecordingStart
        self.onRecordingStop = onRecordingStop
    }

    deinit {
        unregister()
    }

    func register() {
        unregister()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
        VoiceTextLogger.log("Control key recording trigger registered")
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        holdTimer?.invalidate()
        holdTimer = nil
        tapTracker.reset()
        isControlPressed = false
        controlPressTime = nil
        didBeginHold = false
        activeMode = nil
    }

    func recordingDidEndExternally() {
        guard activeMode != nil else { return }
        VoiceTextLogger.log("Control key trigger mode reset after external recording end")
        activeMode = nil
        didBeginHold = false
        tapTracker.reset()
    }

    private func handle(_ event: NSEvent) {
        let controlPressed = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.control)

        if controlPressed && !isControlPressed {
            handleControlPressed(at: event.timestamp)
        } else if !controlPressed && isControlPressed {
            handleControlReleased(at: event.timestamp)
        }
    }

    private func handleControlPressed(at timestamp: TimeInterval) {
        isControlPressed = true
        controlPressTime = timestamp
        didBeginHold = false
        holdTimer?.invalidate()
        holdTimer = nil

        guard activeMode == nil else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            self?.beginHoldRecordingIfStillPressed()
        }
    }

    private func handleControlReleased(at timestamp: TimeInterval) {
        isControlPressed = false
        holdTimer?.invalidate()
        holdTimer = nil

        if didBeginHold && activeMode == .hold {
            didBeginHold = false
            activeMode = nil
            tapTracker.reset()
            VoiceTextLogger.log("Hold Control recording ended")
            onRecordingStop(.hold)
            return
        }

        didBeginHold = false
        let pressDuration = timestamp - (controlPressTime ?? timestamp)
        controlPressTime = nil

        guard tapTracker.recordTap(pressDuration: pressDuration, releaseTime: timestamp) else {
            return
        }

        toggleLockedRecording()
    }

    private func beginHoldRecordingIfStillPressed() {
        guard isControlPressed, activeMode == nil, !didBeginHold else { return }
        didBeginHold = true
        activeMode = .hold
        tapTracker.reset()
        VoiceTextLogger.log("Hold Control recording began")
        onRecordingStart(.hold)
    }

    private func toggleLockedRecording() {
        if activeMode == .locked {
            activeMode = nil
            VoiceTextLogger.log("Double Control tap recording ended")
            onRecordingStop(.locked)
        } else if activeMode == nil {
            activeMode = .locked
            VoiceTextLogger.log("Double Control tap recording began")
            onRecordingStart(.locked)
        }
    }
}
```

- **Step 3: Typecheck the renamed service**

Run:

```bash
swiftc -typecheck -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" Sources/VoiceTextCore/*.swift && mkdir -p .build/typecheck && swiftc -emit-module -module-name VoiceTextCore -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" Sources/VoiceTextCore/*.swift -emit-module-path .build/typecheck/VoiceTextCore.swiftmodule && swiftc -typecheck -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" -I .build/typecheck Sources/VoiceTextApp/*.swift
```

Expected: fail because `AppDelegate` still references `HoldControlKeyService`.

- **Step 4: Commit**

Run this after Task 3 passes, not immediately after Step 3:

```bash
git add Sources/VoiceTextApp/ControlKeyRecordingTriggerService.swift
git add -u Sources/VoiceTextApp/HoldControlKeyService.swift
git commit -m "feat: add dual-mode control key trigger service"
```

Expected: commit succeeds after the AppDelegate wiring task is complete.

---

### Task 3: Wire Dual-Mode Trigger Into AppDelegate

**Files:**

- Modify: `Sources/VoiceTextApp/AppDelegate.swift`
- **Step 1: Replace the stored service property**

In `AppDelegate`, replace:

```swift
private var holdControlKeyService: HoldControlKeyService?
```

with:

```swift
private var controlKeyRecordingTriggerService: ControlKeyRecordingTriggerService?
```

- **Step 2: Reset trigger mode when recording ends outside the trigger service**

Replace the `controller.onStateChange` assignment with:

```swift
controller.onStateChange = { [weak self, weak statusController] state in
    DispatchQueue.main.async {
        statusController?.update(state: state)
        switch state {
        case .idle, .error:
            self?.controlKeyRecordingTriggerService?.recordingDidEndExternally()
        case .connecting, .recording:
            break
        }
    }
}
```

- **Step 3: Replace hold-only service setup**

In `applicationDidFinishLaunching`, replace:

```swift
let holdControlKeyService = HoldControlKeyService(
    holdThreshold: 0.25,
    onHoldBegan: { [weak controller] in
        controller?.start()
    },
    onHoldEnded: { [weak controller] in
        controller?.stop()
    }
)
holdControlKeyService.register()
```

with:

```swift
let controlKeyRecordingTriggerService = ControlKeyRecordingTriggerService(
    holdThreshold: 0.25,
    doubleTapInterval: 0.35,
    maxTapDuration: 0.22,
    onRecordingStart: { [weak controller] mode in
        VoiceTextLogger.log("Recording start requested by trigger mode=\(mode)")
        controller?.start()
    },
    onRecordingStop: { [weak controller] mode in
        VoiceTextLogger.log("Recording stop requested by trigger mode=\(mode)")
        controller?.stop()
    }
)
controlKeyRecordingTriggerService.register()
```

- **Step 4: Store the new service**

In `applicationDidFinishLaunching`, replace:

```swift
self.holdControlKeyService = holdControlKeyService
```

with:

```swift
self.controlKeyRecordingTriggerService = controlKeyRecordingTriggerService
```

- **Step 5: Update the hotkey description**

Replace `hotkeyDescription(for:)` with:

```swift
private static func hotkeyDescription(for configuration: ASRConfiguration) -> String {
    "按住 Control 说话，松开结束；或双击 Control 开始/结束"
}
```

- **Step 6: Typecheck**

Run:

```bash
swiftc -typecheck -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" Sources/VoiceTextCore/*.swift && mkdir -p .build/typecheck && swiftc -emit-module -module-name VoiceTextCore -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" Sources/VoiceTextCore/*.swift -emit-module-path .build/typecheck/VoiceTextCore.swiftmodule && swiftc -typecheck -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" -I .build/typecheck Sources/VoiceTextApp/*.swift
```

Expected: exit code `0`.

- **Step 7: Commit Tasks 2 and 3 together**

Run:

```bash
git add Sources/VoiceTextApp/AppDelegate.swift Sources/VoiceTextApp/ControlKeyRecordingTriggerService.swift
git add -u Sources/VoiceTextApp/HoldControlKeyService.swift
git commit -m "feat: support double-control recording toggle"
```

Expected: commit succeeds.

---

### Task 4: Update UI Copy

**Files:**

- Modify: `Sources/VoiceTextApp/StatusBarController.swift`
- Modify: `Sources/VoiceTextApp/SettingsWindowController.swift`
- **Step 1: Update status bar default text**

In `StatusBarController`, replace the two hold-only strings:

```swift
private let hotkeyItem = NSMenuItem(title: "快捷键：按住 Control 说话，松开结束", action: nil, keyEquivalent: "")
private var hotkeyDescription = "按住 Control 说话，松开结束"
```

with:

```swift
private let hotkeyItem = NSMenuItem(title: "快捷键：按住 Control 说话，松开结束；或双击 Control 开始/结束", action: nil, keyEquivalent: "")
private var hotkeyDescription = "按住 Control 说话，松开结束；或双击 Control 开始/结束"
```

- **Step 2: Update settings subtitle**

In `SettingsWindowController.buildContent()`, replace:

```swift
let subtitle = NSTextField(labelWithString: "登录后按住 Control 说话，松开结束。")
```

with:

```swift
let subtitle = NSTextField(labelWithString: "登录后可按住 Control 说话，也可双击 Control 开始/结束。")
```

- **Step 3: Update settings trigger label**

In `SettingsWindowController.hotkeyDescription(keyCode:modifiers:)`, replace:

```swift
"按住 Control 说话，松开结束"
```

with:

```swift
"按住 Control 说话，松开结束；或双击 Control 开始/结束"
```

- **Step 4: Typecheck**

Run:

```bash
swiftc -typecheck -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" Sources/VoiceTextCore/*.swift && mkdir -p .build/typecheck && swiftc -emit-module -module-name VoiceTextCore -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" Sources/VoiceTextCore/*.swift -emit-module-path .build/typecheck/VoiceTextCore.swiftmodule && swiftc -typecheck -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" -I .build/typecheck Sources/VoiceTextApp/*.swift
```

Expected: exit code `0`.

- **Step 5: Commit**

Run:

```bash
git add Sources/VoiceTextApp/StatusBarController.swift Sources/VoiceTextApp/SettingsWindowController.swift
git commit -m "docs: describe both control recording triggers in app UI"
```

Expected: commit succeeds.

---

### Task 5: Update README

**Files:**

- Modify: `README.md`
- **Step 1: Update product description**

In `README.md`, replace:

```markdown
VoiceText 是一个轻量 macOS 状态栏语音输入工具。它通过全局快捷键启动录音，把音频流发送到公司 ASR WebSocket 服务，并将识别结果插入当前焦点输入框。
```

with:

```markdown
VoiceText 是一个轻量 macOS 状态栏语音输入工具。它支持按住 `Control` 说话、松开结束，也支持双击 `Control` 开始录音、再次双击 `Control` 结束录音。录音期间会把音频流发送到公司 ASR WebSocket 服务，并将识别结果插入当前焦点输入框。
```

- **Step 2: Update config docs**

In `README.md`, replace:

```markdown
- `hotkeyKeyCode` / `hotkeyModifiers`：默认 `Option + Space`
```

with:

```markdown
- `hotkeyKeyCode` / `hotkeyModifiers`：历史配置字段，当前默认录音方式为按住 `Control` 或双击 `Control`
```

- **Step 3: Commit**

Run:

```bash
git add README.md
git commit -m "docs: document double-control recording mode"
```

Expected: commit succeeds.

---

### Task 6: Full Verification

**Files:**

- Verify: `Sources/VoiceTextCore/ControlKeyTapTracker.swift`
- Verify: `Tests/VoiceTextCoreTests/ControlKeyTapTrackerTests.swift`
- Verify: `Sources/VoiceTextApp/ControlKeyRecordingTriggerService.swift`
- Verify: `Sources/VoiceTextApp/AppDelegate.swift`
- Verify: `Sources/VoiceTextApp/StatusBarController.swift`
- Verify: `Sources/VoiceTextApp/SettingsWindowController.swift`
- Verify: `README.md`
- **Step 1: Run unit tests**

Run:

```bash
swift test
```

Expected: exit code `0`.

- **Step 2: Typecheck app target**

Run:

```bash
swiftc -typecheck -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" Sources/VoiceTextCore/*.swift && mkdir -p .build/typecheck && swiftc -emit-module -module-name VoiceTextCore -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" Sources/VoiceTextCore/*.swift -emit-module-path .build/typecheck/VoiceTextCore.swiftmodule && swiftc -typecheck -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" -I .build/typecheck Sources/VoiceTextApp/*.swift
```

Expected: exit code `0`.

- **Step 3: Build app bundle**

Run:

```bash
./scripts/build_app_bundle.sh
```

Expected output includes:

```text
Built /Users/wangzhigang/a-idea/voice-text/build/VoiceText.app
```

- **Step 4: Launch the app with a fresh log**

Run:

```bash
: > /tmp/voicetext.log; pkill -f "VoiceTextApp" || true; sleep 1; open -n build/VoiceText.app; sleep 2; pgrep -fl "VoiceTextApp|VoiceText" || true
```

Expected output includes a running `VoiceTextApp` process.

- **Step 5: Verify startup log**

Read `/tmp/voicetext.log`.

Expected line:

```text
Control key recording trigger registered
```

- **Step 6: Manual test hold mode**

Perform this sequence:

```text
Press and hold Control for more than 0.25 seconds.
Confirm the floating preview appears.
Release Control.
Confirm recording stops and the floating preview hides.
```

Expected log lines:

```text
Hold Control recording began
Recording start requested by trigger mode=hold
Recording start requested
Hold Control recording ended
Recording stop requested by trigger mode=hold
Recording stop requested
```

- **Step 7: Manual test locked double-tap mode**

Perform this sequence:

```text
Double-tap Control quickly.
Browse or click files while speaking.
Confirm recording remains active after Control is released.
Double-tap Control quickly again.
Confirm recording stops and the floating preview hides.
```

Expected log lines:

```text
Double Control tap recording began
Recording start requested by trigger mode=locked
Recording start requested
Double Control tap recording ended
Recording stop requested by trigger mode=locked
Recording stop requested
```

- **Step 8: Manual test conflict behavior**

Perform this sequence:

```text
Double-tap Control to start locked recording.
Press and hold Control for more than 0.25 seconds.
Release Control.
Confirm recording remains active.
Double-tap Control to stop locked recording.
```

Expected: the hold press during locked recording does not emit `Hold Control recording ended` and does not stop recording.

- **Step 9: Final commit if verification changed files**

Run:

```bash
git status --short
```

Expected: no uncommitted changes. If verification generated intentional source or doc changes, add and commit only those files with:

```bash
git add <changed-source-or-doc-files>
git commit -m "chore: finish double-control recording verification"
```

---

## Self-Review

**Spec coverage:** This plan keeps the existing hold-to-record scenario and adds the requested double-`Control` start/stop scenario for hands-free browsing while recognition continues. It also covers the important conflict case where holding `Control` during locked recording must not stop the locked session.

**Placeholder scan:** The plan contains concrete file paths, commands, expected outputs, and code blocks for each source change. It avoids deferred implementation language.

**Type consistency:** `ControlKeyTapTracker`, `ControlKeyRecordingTriggerService`, `ControlRecordingTriggerMode.hold`, `ControlRecordingTriggerMode.locked`, and `recordingDidEndExternally()` are named consistently across tasks.