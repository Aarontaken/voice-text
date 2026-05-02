# Hold Control Recording Trigger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current press-once hotkey behavior with “hold Control to record, release Control to stop,” including a hold threshold, preparing/recording floating state, and a start-recording sound.

**Architecture:** Add a small global modifier-key observer dedicated to Control hold detection. Keep `RecordingController` as the recording state owner, and connect the observer to `start()`/`stop()` without changing ASR protocol, login, text insertion, or recognition result handling. Extend the existing floating preview UI so it can show “preparing” and “recording/listening” states before streaming text appears.

**Tech Stack:** Native macOS Swift, AppKit, `NSEvent` global/local modifier monitoring, existing `RecordingController`, existing `RecognitionPreviewWindowController`, `NSSound`.

---

## Scope

Implement only the recording trigger and recording-state feedback changes:

- Long press `Control` for a small threshold before recording starts.
- While `Control` is held after threshold, recording stays active.
- Releasing `Control` stops recording.
- Show a floating “准备中...” state while waiting for connection/audio startup.
- Show a recording/listening state while recording even before ASR preview text arrives.
- Play a short system sound when recording actually starts.
- Do not change ASR message parsing, final text insertion, login, cookie refresh, punctuation rules, or settings credential flow.

## File Structure

- Create `Sources/VoiceTextApp/HoldControlKeyService.swift`
  - Owns global/local modifier-key monitoring.
  - Detects Control press and release.
  - Starts only after a threshold timer fires.
  - Calls injected `onHoldBegan` and `onHoldEnded` closures.
- Modify `Sources/VoiceTextApp/RecordingController.swift`
  - Add idempotent `startFromHold()` and `stopFromHold()` wrappers if needed.
  - Keep existing `start()`/`stop()` behavior unchanged.
  - Emit preview-state text on start/connected/recording/failure.
  - Play recording-start sound when audio capture begins.
- Modify `Sources/VoiceTextApp/RecognitionPreviewWindowController.swift`
  - Add state-aware display methods: preparing, listening, text preview, hidden.
  - Keep the existing floating panel and non-activating behavior.
- Modify `Sources/VoiceTextApp/AppDelegate.swift`
  - Replace default registration of `GlobalHotkeyService` with `HoldControlKeyService`.
  - Wire hold begin to `recordingController.start()`.
  - Wire hold end to `recordingController.stop()`.
  - Keep `GlobalHotkeyService.swift` in the repo as fallback code, but do not register it by default.
- Modify `Sources/VoiceTextApp/StatusBarController.swift`
  - Update menu shortcut text from `Control + Option + V` to `按住 Control 说话，松开结束`.
- Modify `Sources/VoiceTextApp/SettingsWindowController.swift`
  - Update shortcut display text to `按住 Control 说话，松开结束`.
  - Remove or disable “恢复默认” behavior if it only resets numeric hotkey values; it is no longer meaningful for hold-Control mode.

---

### Task 1: Add Hold Control Key Observer

**Files:**

- Create: `Sources/VoiceTextApp/HoldControlKeyService.swift`
- Verify: source typecheck command below
- **Step 1: Create `HoldControlKeyService.swift` with threshold-based hold detection**

```swift
import AppKit
import VoiceTextCore

final class HoldControlKeyService {
    private let holdThreshold: TimeInterval
    private let onHoldBegan: () -> Void
    private let onHoldEnded: () -> Void

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var holdTimer: Timer?
    private var isControlDown = false
    private var didTriggerHold = false

    init(
        holdThreshold: TimeInterval = 0.25,
        onHoldBegan: @escaping () -> Void,
        onHoldEnded: @escaping () -> Void
    ) {
        self.holdThreshold = holdThreshold
        self.onHoldBegan = onHoldBegan
        self.onHoldEnded = onHoldEnded
    }

    deinit {
        unregister()
    }

    func register() {
        unregister()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
        VoiceTextLogger.log("Hold Control key service registered threshold=\(holdThreshold)")
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
        cancelPendingHold()
        isControlDown = false
        didTriggerHold = false
    }

    private func handle(_ event: NSEvent) {
        let controlIsDown = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control)
        if controlIsDown == isControlDown {
            return
        }

        isControlDown = controlIsDown
        if controlIsDown {
            scheduleHoldTrigger()
        } else {
            finishHoldIfNeeded()
        }
    }

    private func scheduleHoldTrigger() {
        cancelPendingHold()
        didTriggerHold = false
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            guard let self, self.isControlDown, !self.didTriggerHold else { return }
            self.didTriggerHold = true
            VoiceTextLogger.log("Hold Control key began")
            self.onHoldBegan()
        }
    }

    private func finishHoldIfNeeded() {
        cancelPendingHold()
        guard didTriggerHold else { return }
        didTriggerHold = false
        VoiceTextLogger.log("Hold Control key ended")
        onHoldEnded()
    }

    private func cancelPendingHold() {
        holdTimer?.invalidate()
        holdTimer = nil
    }
}
```

- **Step 2: Typecheck**

Run:

```bash
swiftc -typecheck -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" Sources/VoiceTextCore/*.swift && mkdir -p .build/typecheck && swiftc -emit-module -module-name VoiceTextCore -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" Sources/VoiceTextCore/*.swift -emit-module-path .build/typecheck/VoiceTextCore.swiftmodule && swiftc -typecheck -sdk "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" -I .build/typecheck Sources/VoiceTextApp/*.swift
```

Expected: exit code `0`.

---

### Task 2: Wire Hold Control Into App Startup

**Files:**

- Modify: `Sources/VoiceTextApp/AppDelegate.swift`
- Modify: `Sources/VoiceTextApp/GlobalHotkeyService.swift` only if needed; default should be not registered
- **Step 1: Replace stored hotkey service property**

In `AppDelegate`, replace:

```swift
private var hotkeyService: GlobalHotkeyService?
```

with:

```swift
private var holdControlKeyService: HoldControlKeyService?
```

- **Step 2: Replace default hotkey registration in `applicationDidFinishLaunching`**

Replace the current `GlobalHotkeyService` block:

```swift
let hotkeyService = GlobalHotkeyService(
    keyCode: configuration.hotkeyKeyCode,
    modifiers: configuration.hotkeyModifiers
) { [weak controller] in
    controller?.toggle()
}
hotkeyService.register()
```

with:

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

- **Step 3: Store the hold service**

Replace:

```swift
self.hotkeyService = hotkeyService
```

with:

```swift
self.holdControlKeyService = holdControlKeyService
```

- **Step 4: Remove settings save hotkey update**

In `openSettings()`, remove:

```swift
self?.hotkeyService?.update(keyCode: configuration.hotkeyKeyCode, modifiers: configuration.hotkeyModifiers)
```

Keep:

```swift
self?.recordingController?.update(configuration: configuration)
self?.statusController?.updateHotkeyDescription(Self.hotkeyDescription(for: configuration))
```

Then adjust `hotkeyDescription(for:)` in Task 5.

- **Step 5: Typecheck**

Run the same typecheck command from Task 1.

Expected: exit code `0`.

---

### Task 3: Add Preparing and Recording Preview States

**Files:**

- Modify: `Sources/VoiceTextApp/RecognitionPreviewWindowController.swift`
- Modify: `Sources/VoiceTextApp/RecordingController.swift`
- **Step 1: Add state display API to preview window**

In `RecognitionPreviewWindowController`, add:

```swift
func showPreparing() {
    show(title: "准备中", text: "正在连接语音识别...")
}

func showListening() {
    show(title: "正在录音", text: "请开始说话")
}

func showPreview(text: String) {
    show(title: "正在识别", text: text)
}
```

Replace existing `func show(text: String)` with a private state-aware method:

```swift
private func show(title: String, text: String) {
    let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedText.isEmpty else {
        hide()
        return
    }

    titleLabel.stringValue = title
    textLabel.stringValue = normalizedText
    window.setContentSize(preferredSize(for: normalizedText))
    positionWindow()
    window.orderFrontRegardless()
}
```

To support this, move `titleLabel` from a local variable to a property:

```swift
private let titleLabel = NSTextField(labelWithString: "正在识别")
```

Then remove the local `let titleLabel = ...` inside `makeContentView()`.

- **Step 2: Update `AppDelegate` preview callback**

Replace:

```swift
if let text, !text.isEmpty {
    previewWindowController?.show(text: text)
} else {
    previewWindowController?.hide()
}
```

with a richer callback after Task 3 Step 3 changes the closure type.

- **Step 3: Change `RecordingController.onPreviewChange` to support states**

Add this enum near `RecordingState` in `RecordingController.swift`:

```swift
enum RecognitionPreviewState: Equatable {
    case hidden
    case preparing
    case listening
    case preview(String)
}
```

Change:

```swift
var onPreviewChange: ((String?) -> Void)?
```

to:

```swift
var onPreviewChange: ((RecognitionPreviewState) -> Void)?
```

- **Step 4: Emit preparing/listening/preview states**

In `start()` replace:

```swift
onPreviewChange?(nil)
```

with:

```swift
onPreviewChange?(.preparing)
```

In `stop()` and `fail(_:)`, replace:

```swift
onPreviewChange?(nil)
```

with:

```swift
onPreviewChange?(.hidden)
```

In `startAudioCapture()`, after audio capture starts successfully and before/after `state = .recording`, add:

```swift
onPreviewChange?(.listening)
playRecordingStartedSound()
```

In non-final recognition handling, replace:

```swift
onPreviewChange?(result.text)
```

with:

```swift
onPreviewChange?(.preview(result.text))
```

Before final insertion, replace any preview clearing with:

```swift
onPreviewChange?(.hidden)
```

- **Step 5: Update `AppDelegate` callback switch**

Use:

```swift
controller.onPreviewChange = { [weak previewWindowController] state in
    DispatchQueue.main.async {
        switch state {
        case .hidden:
            previewWindowController?.hide()
        case .preparing:
            previewWindowController?.showPreparing()
        case .listening:
            previewWindowController?.showListening()
        case let .preview(text):
            previewWindowController?.showPreview(text: text)
        }
    }
}
```

- **Step 6: Typecheck**

Run the same typecheck command from Task 1.

Expected: exit code `0`.

---

### Task 4: Add Recording Start Sound

**Files:**

- Modify: `Sources/VoiceTextApp/RecordingController.swift`
- **Step 1: Add a small sound helper**

Add this private method inside `RecordingController`:

```swift
private func playRecordingStartedSound() {
    NSSound(named: NSSound.Name("Tink"))?.play()
}
```

Because this file currently imports `Foundation`, change imports at the top from:

```swift
import Foundation
import VoiceTextCore
```

to:

```swift
import AppKit
import Foundation
import VoiceTextCore
```

- **Step 2: Ensure sound only plays after recording actually starts**

Call `playRecordingStartedSound()` only in `startAudioCapture()` after `audioCapture.start(...)` succeeds. Do not play it on Control key down, because recording may still fail to connect.

- **Step 3: Typecheck**

Run the same typecheck command from Task 1.

Expected: exit code `0`.

---

### Task 5: Update Menu and Settings Text

**Files:**

- Modify: `Sources/VoiceTextApp/AppDelegate.swift`
- Modify: `Sources/VoiceTextApp/StatusBarController.swift`
- Modify: `Sources/VoiceTextApp/SettingsWindowController.swift`
- **Step 1: Change app hotkey description**

In `AppDelegate.hotkeyDescription(for:)`, replace the dynamic key-code implementation body with:

```swift
return "按住 Control 说话，松开结束"
```

Keep the function signature to avoid broader changes:

```swift
private static func hotkeyDescription(for configuration: ASRConfiguration) -> String
```

- **Step 2: Update settings hotkey display**

In `SettingsWindowController`, remove editable hotkey state if it is no longer used for registration:

```swift
private var hotkeyKeyCode = SettingsWindowController.defaultHotkeyKeyCode
private var hotkeyModifiers = SettingsWindowController.defaultHotkeyModifiers
```

or leave it only for backward-compatible config saving. The displayed value must be:

```swift
hotkeyValueLabel.stringValue = "按住 Control 说话，松开结束"
```

Replace the reset button title/action with no button, or remove `resetButton` from `hotkeyRow()` entirely:

```swift
stack.addArrangedSubview(labelView)
stack.addArrangedSubview(hotkeyValueLabel)
return stack
```

- **Step 3: Keep saved config compatible**

When building `baseConfig` in `SettingsWindowController.loginAndSave()`, keep existing saved key fields so old config files do not churn:

```swift
hotkeyKeyCode: previousConfig.hotkeyKeyCode,
hotkeyModifiers: previousConfig.hotkeyModifiers
```

The hold-Control behavior is now controlled by `HoldControlKeyService`, not by these numeric fields.

- **Step 4: Typecheck**

Run the same typecheck command from Task 1.

Expected: exit code `0`.

---

### Task 6: Build, Restart, and Manual Verify

**Files:**

- No code changes unless verification fails.
- **Step 1: Build app bundle**

Run:

```bash
./scripts/build_app_bundle.sh
```

Expected:

```text
Built /Users/wangzhigang/a-idea/voice-text/build/VoiceText.app
```

The existing `xcrun --show-sdk-platform-path` warning may still appear before the manual fallback build. That warning is already known and is acceptable if the script exits `0`.

- **Step 2: Restart app**

Run:

```bash
: > /tmp/voicetext.log; pkill -f "VoiceTextApp" || true; sleep 1; open -n build/VoiceText.app; sleep 2; pgrep -fl "VoiceTextApp|VoiceText" || true
```

Expected:

```text
<pid> /Users/wangzhigang/a-idea/voice-text/build/VoiceText.app/Contents/MacOS/VoiceTextApp
```

- **Step 3: Verify logs**

Read `/tmp/voicetext.log`. Expected lines after startup:

```text
Hold Control key service registered threshold=0.25
```

When pressing Control for less than 250ms:

```text

```

No recording start should appear.

When holding Control longer than 250ms:

```text
Hold Control key began
Recording start requested
```

When releasing Control:

```text
Hold Control key ended
Recording stop requested
```

- **Step 4: Manual interaction checklist**

Manual checks:

- Tap Control quickly: recording must not start.
- Hold Control for about 0.25s: preparing floating UI appears.
- Once audio capture starts: floating UI changes to recording/listening and a short sound plays.
- While speaking: streaming preview text replaces the listening text.
- Release Control: recording stops and floating UI hides.
- Final recognized text is inserted only after `msgType=1`.
- Existing status bar menu still opens settings and quits normally.

---

## Self-Review

**Spec coverage:** The plan covers delayed long-press detection, hold-to-record, release-to-stop, preparing/recording floating feedback, start sound, and limits scope to trigger/end behavior plus required feedback.

**Placeholder scan:** No placeholders remain. Each task names exact files, exact code snippets, and exact verification commands.

**Type consistency:** `HoldControlKeyService`, `RecognitionPreviewState`, `RecognitionPreviewWindowController.showPreparing/showListening/showPreview`, and `RecordingController.onPreviewChange` signatures are consistently referenced across tasks.

**Commit policy:** No commit step is included because repository policy for this session is to create commits only when explicitly requested by the user.