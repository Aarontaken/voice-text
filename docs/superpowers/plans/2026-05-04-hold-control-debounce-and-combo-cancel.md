# 长按 Control 防误触与组合键取消 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 拉长「按住 Control 才开始识别」的判定时间，并在按住 Control 已进入语音识别期间，若用户同时按下其它键（含其它修饰键或普通键），立即结束识别，避免误触与快捷键冲突。

**Architecture:** 保持 `HoldControlKeyService` 作为唯一入口：`flagsChanged` 仍负责 Control 按下/抬起；阈值仅在 `AppDelegate` 中调大。在「按住识别已生效」阶段（`didBeginHold == true` 且 Control 未松开）动态注册 `keyDown` 的全局/本地监视器，任意非忽略的 `keyDown`（且仍带 Control）即调用与松开相同的 `onHoldEnded()`；同时在同阶段的 `flagsChanged` 上检测是否新出现 Shift/Option/Command/Function 等修饰组合并走同一取消路径。取消后需吞掉随后一次 Control 松开，避免被 `ControlKeyTapTracker` 误判为双击切换。将「是否存在需取消的附加修饰键」抽成 `VoiceTextCore` 中的纯函数并写单元测试，避免 App 目标无测试包的问题。

**Tech Stack:** Swift 5.9、macOS 13+、`NSEvent` 全局/本地监视器、`VoiceTextCore` + `VoiceTextCoreTests`（SwiftPM）

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `Sources/VoiceTextCore/HoldControlExtraModifierDetector.swift`（新建） | 根据与 `NSEvent.ModifierFlags` 一致的 device-independent 原始位，判断除 Control 外是否还有会触发「组合键取消」的修饰位；供单测与 App 共用。 |
| `Tests/VoiceTextCoreTests/HoldControlExtraModifierDetectorTests.swift`（新建） | 覆盖仅 Control、Control+Shift、仅 Shift 等断言。 |
| `Sources/VoiceTextApp/HoldControlKeyService.swift`（修改） | 加长阈值由调用方传入；实现 `keyDown` 监视、修饰组合检测、`suppressNextControlRelease` 吞释放、监视器生命周期。 |
| `Sources/VoiceTextApp/AppDelegate.swift`（修改） | 将 `holdThreshold` 从 `0.25` 改为 `0.5`（秒）。 |

---

### Task 1: 纯函数「附加修饰键」检测（TDD）

**Files:**
- Create: `Sources/VoiceTextCore/HoldControlExtraModifierDetector.swift`
- Create: `Tests/VoiceTextCoreTests/HoldControlExtraModifierDetectorTests.swift`

- [ ] **Step 1: 编写失败测试**

在 `Tests/VoiceTextCoreTests/HoldControlExtraModifierDetectorTests.swift` 新建：

```swift
import XCTest
@testable import VoiceTextCore

final class HoldControlExtraModifierDetectorTests: XCTestCase {
    func testControlAloneDoesNotCancel() {
        let controlOnly = UInt64(1 << 18)
        XCTAssertFalse(
            HoldControlExtraModifierDetector.shouldCancelHoldBecauseAddedModifiers(
                deviceIndependentRaw: controlOnly
            )
        )
    }

    func testControlPlusShiftCancels() {
        let control = UInt64(1 << 18)
        let shift = UInt64(1 << 17)
        XCTAssertTrue(
            HoldControlExtraModifierDetector.shouldCancelHoldBecauseAddedModifiers(
                deviceIndependentRaw: control | shift
            )
        )
    }

    func testShiftAloneWithoutControlDoesNotCancel() {
        let shiftOnly = UInt64(1 << 17)
        XCTAssertFalse(
            HoldControlExtraModifierDetector.shouldCancelHoldBecauseAddedModifiers(
                deviceIndependentRaw: shiftOnly
            )
        )
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd /Users/wangzhigang/a-idea/voice-text && swift test --filter HoldControlExtraModifierDetectorTests`

Expected: 编译失败，`HoldControlExtraModifierDetector` 未定义。

- [ ] **Step 3: 最小实现（与测试 API 一致）**

新建 `Sources/VoiceTextCore/HoldControlExtraModifierDetector.swift`：

```swift
import Foundation

public enum HoldControlExtraModifierDetector {
    /// 与 `NSEvent.ModifierFlags` device-independent 位布局一致（不 import AppKit）。
    public static func shouldCancelHoldBecauseAddedModifiers(
        deviceIndependentRaw: UInt64
    ) -> Bool {
        let control = UInt64(1 << 18)
        guard deviceIndependentRaw & control != 0 else { return false }
        let shift = UInt64(1 << 17)
        let option = UInt64(1 << 19)
        let command = UInt64(1 << 20)
        let function = UInt64(1 << 23)
        let comboBits = shift | option | command | function
        return deviceIndependentRaw & comboBits != 0
    }
}
```

- [ ] **Step 4: 运行测试**

Run: `swift test --filter HoldControlExtraModifierDetectorTests`

Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
cd /Users/wangzhigang/a-idea/voice-text
git add Sources/VoiceTextCore/HoldControlExtraModifierDetector.swift \
        Tests/VoiceTextCoreTests/HoldControlExtraModifierDetectorTests.swift
git commit -m "feat(core): detect extra modifiers during Control hold"
```

---

### Task 2: HoldControlKeyService 组合键取消与吞掉释放

**Files:**
- Modify: `Sources/VoiceTextApp/HoldControlKeyService.swift`
- Modify: `Sources/VoiceTextApp/AppDelegate.swift`（阈值）

- [ ] **Step 1: 在 `handle(_:)` 末尾增加「按住识别中 + 仍按住 Control」分支**

在 `Sources/VoiceTextApp/HoldControlKeyService.swift` 的 `private func handle(_ event: NSEvent)` 中，在现有 `if controlPressed && !isControlPressed` / `else if !controlPressed && isControlPressed` 之后追加：

```swift
if didBeginHold, controlPressed, isControlPressed {
    let raw = UInt64(event.modifierFlags.rawValue)
    if HoldControlExtraModifierDetector.shouldCancelHoldBecauseAddedModifiers(
        deviceIndependentRaw: raw
    ) {
        cancelActiveHoldDueToCombo(reasonLog: "Hold Control cancelled: extra modifier flags")
    }
}
```

（`NSEvent.ModifierFlags.rawValue` 在 macOS 上为 `UInt`，用 `UInt64(...)` 传入检测函数。文件顶部保留 `import AppKit` 与 `import VoiceTextCore`。）

- [ ] **Step 2: 增加状态字段与取消方法**

在 `HoldControlKeyService` 类内、`isLockedRecording` 下方增加：

```swift
private var suppressTapUntilControlReleased = false
private var keyDownGlobalMonitor: Any?
private var keyDownLocalMonitor: Any?
```

增加方法（放在 `handleControlReleased` 之上或之下均可，保持 `private`）：

```swift
private func cancelActiveHoldDueToCombo(reasonLog: String) {
    guard didBeginHold else { return }
    VoiceTextLogger.log(reasonLog)
    removeKeyDownMonitors()
    didBeginHold = false
    suppressTapUntilControlReleased = true
    onHoldEnded()
}

private func installKeyDownMonitorsIfNeeded() {
    guard keyDownGlobalMonitor == nil, keyDownLocalMonitor == nil else { return }
    keyDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        DispatchQueue.main.async {
            self?.handleKeyDownDuringHold(event)
        }
    }
    keyDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        self?.handleKeyDownDuringHold(event)
        return event
    }
}

private func removeKeyDownMonitors() {
    if let keyDownGlobalMonitor {
        NSEvent.removeMonitor(keyDownGlobalMonitor)
        self.keyDownGlobalMonitor = nil
    }
    if let keyDownLocalMonitor {
        NSEvent.removeMonitor(keyDownLocalMonitor)
        self.keyDownLocalMonitor = nil
    }
}

private func handleKeyDownDuringHold(_ event: NSEvent) {
    guard didBeginHold, isControlPressed else { return }
    guard event.modifierFlags.contains(.control) else { return }
    if event.isARepeat { return }
    // 忽略左右 Control 本身的 keyDown（若系统产生），避免误关
    if event.keyCode == 59 || event.keyCode == 62 { return }
    cancelActiveHoldDueToCombo(reasonLog: "Hold Control cancelled: keyDown while Control held")
}
```

- [ ] **Step 3: 在 hold 定时器触发时安装 keyDown 监视器**

在 `handleControlPressed()` 里 `holdTimer` 的 `Timer.scheduledTimer` 闭包中，在 `self.onHoldBegan()` 之前插入：

```swift
self.installKeyDownMonitorsIfNeeded()
```

在 `handleControlReleased()` 开头 `isControlPressed = false` 之后、`holdTimer?.invalidate()` 逻辑中，当需要处理正常松开时调用 `removeKeyDownMonitors()`：

将 `handleControlReleased` 改为先处理 `suppressTapUntilControlReleased`：

```swift
private func handleControlReleased() {
    isControlPressed = false
    holdTimer?.invalidate()
    holdTimer = nil
    removeKeyDownMonitors()

    if suppressTapUntilControlReleased {
        suppressTapUntilControlReleased = false
        pressBeganAt = nil
        tapTracker.reset()
        return
    }

    let pressDuration = eventTimestamp() - (pressBeganAt ?? eventTimestamp())
    pressBeganAt = nil
    if didBeginHold {
        didBeginHold = false
        VoiceTextLogger.log("Hold Control key ended")
        onHoldEnded()
        return
    }
    // ... 保持原有 double-tap 逻辑不变
}
```

注意：若用户是**正常**松开结束识别，原先逻辑在 `didBeginHold` 分支会再次 `onHoldEnded()`。当前 `RecordingController.stop()` 应幂等；若曾组合取消已调用过 `onHoldEnded()`，此时 `didBeginHold` 已为 `false`，松开时会走 `tapTracker` 分支。需保证**组合取消后**松开不会二次 `onHoldEnded()`。

组合取消路径已设 `didBeginHold = false`，故松开会命中 `suppressTapUntilControlReleased` 分支（已在取消里设置 `suppressTapUntilControlReleased = true`）。**取消时用户仍按着 Control**，松开会进 `handleControlReleased`：`suppressTapUntilControlReleased` 为 true → 清除并 return，不触发 double-tap。**正常**结束：用户松 Control，`didBeginHold` 仍为 true 直到进入分支并置 false — 但此时不应设 `suppressTapUntilControlReleased`。正常路径 OK。

再核对：组合取消时 `isControlPressed` 在 `handleControlReleased` 之前仍为 true；`cancelActiveHoldDueToCombo` 未将 `isControlPressed` 设为 false。用户稍后松开 Control → `handle` 收到 `!controlPressed && isControlPressed` → `handleControlReleased`。此时 `suppressTapUntilControlReleased` true，清除并 return。正确。

`unregister()` 与 `resetTriggerState()` 中增加 `removeKeyDownMonitors()` 与 `suppressTapUntilControlReleased = false`。

- [ ] **Step 4: 调大阈值**

在 `Sources/VoiceTextApp/AppDelegate.swift` 将：

```swift
holdThreshold: 0.25,
```

改为：

```swift
holdThreshold: 0.5,
```

- [ ] **Step 5: 编译验证**

Run: `cd /Users/wangzhigang/a-idea/voice-text && swift build`

Expected: 成功，无 warning 相关错误。

- [ ] **Step 6: 全量测试**

Run: `swift test`

Expected: 全部 PASS。

- [ ] **Step 7: Commit**

```bash
git add Sources/VoiceTextApp/HoldControlKeyService.swift Sources/VoiceTextApp/AppDelegate.swift
git commit -m "feat(app): longer Control hold and cancel on combo keys"
```

---

### Task 3: 手动验收清单（无自动化）

**Files:** 无

- [ ] **Step 1: 运行 App，按住 Control 不足 0.5s 松开**

Expected: 不开始识别（与双击逻辑仍兼容：短按仍须满足 `ControlKeyTapTracker` 的 `maxTapDuration` 0.22s）。

- [ ] **Step 2: 按住 Control ≥0.5s，说话后松开**

Expected: 与改前行为一致，仅阈值变长。

- [ ] **Step 3: 按住 Control ≥0.5s 进入识别后，不松 Control，再按字母键（如 A）**

Expected: 识别立即停止（日志含 `keyDown while Control held`）。

- [ ] **Step 4: 同上，改为再按 Command（或其它修饰键）**

Expected: 识别停止（日志含 `extra modifier flags`）；随后仅松开 Control 不应触发双击锁定切换。

- [ ] **Step 5: Commit（若仅文档/无代码）**

若本任务无代码变更，可跳过 commit。

---

## Self-Review

**1. Spec coverage**

| 需求 | 对应 Task |
|------|-----------|
| 长按时间更长 | Task 2 Step 4：`holdThreshold: 0.5` |
| 组合其它键立即停止识别 | Task 2：`keyDown` + 附加 `flags`；Task 1：修饰位检测 |
| 避免误触双击 | `suppressTapUntilControlReleased` + `removeKeyDownMonitors` |

**2. Placeholder scan**

无 TBD；命令与代码块已写全。

**3. Type consistency**

`NSEvent.ModifierFlags.rawValue` 为 `UInt`，调用 detector 时使用 `UInt64(event.modifierFlags.rawValue)`。

---

## Execution Handoff

计划已保存到 `docs/superpowers/plans/2026-05-04-hold-control-debounce-and-combo-cancel.md`。

**可选执行方式：**

**1. Subagent-Driven（推荐）** — 每个 Task 派生子代理，任务间人工快速 review。

**2. Inline Execution** — 在本会话用 executing-plans 按勾选顺序批量改，并在 checkpoint 停顿。

你希望用哪一种？
