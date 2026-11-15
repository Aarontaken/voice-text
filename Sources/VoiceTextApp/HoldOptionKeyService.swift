import AppKit
import CoreGraphics
import VoiceTextCore

/// 长按 **Option (Alt)** 开始/结束语音识别；短按 **Control** 两次切换「常亮」录音（与 `ControlKeyTapTracker` 配合）。
final class HoldOptionKeyService {
    private let holdThreshold: TimeInterval
    private var tapTracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)
    private let onHoldBegan: () -> Void
    private let onHoldEnded: () -> Void
    private let onDoubleTap: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var holdTimer: Timer?
    private var optionPressBeganAt: TimeInterval?
    private var controlPressBeganAt: TimeInterval?
    private var isOptionPressed = false
    private var isControlPressed = false
    private var didBeginHold = false
    private var isLockedRecording = false
    private var optionReleaseRecheckWorkItem: DispatchWorkItem?

    init(
        holdThreshold: TimeInterval,
        onHoldBegan: @escaping () -> Void,
        onHoldEnded: @escaping () -> Void,
        onDoubleTap: @escaping () -> Void
    ) {
        self.holdThreshold = holdThreshold
        self.onHoldBegan = onHoldBegan
        self.onHoldEnded = onHoldEnded
        self.onDoubleTap = onDoubleTap
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
        VoiceTextLogger.log("Hold Option + Control tap monitor registered")
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
        optionReleaseRecheckWorkItem?.cancel()
        optionReleaseRecheckWorkItem = nil
        optionPressBeganAt = nil
        controlPressBeganAt = nil
        isOptionPressed = false
        isControlPressed = false
        didBeginHold = false
        isLockedRecording = false
        tapTracker.reset()
    }

    func resetTriggerState() {
        holdTimer?.invalidate()
        holdTimer = nil
        optionReleaseRecheckWorkItem?.cancel()
        optionReleaseRecheckWorkItem = nil
        optionPressBeganAt = nil
        controlPressBeganAt = nil
        isOptionPressed = false
        isControlPressed = false
        didBeginHold = false
        isLockedRecording = false
        tapTracker.reset()
    }

    private func handle(_ event: NSEvent) {
        let rawOption = event.modifierFlags.contains(.option)
        let rawControl = event.modifierFlags.contains(.control)
        let hardwareOption = isHardwareOptionDown()
        let hardwareControl = isHardwareControlDown()

        // 逐句落字用的合成 ⌘V 也会产生 flagsChanged，且 flags 里没有仍被按住的 Option。
        // 用 HID 硬件状态兜底，避免实时模式插入一句话后误判为「松手」，把 ASR 停掉。
        if rawOption != hardwareOption || rawControl != hardwareControl {
            VoiceTextLogger.log(
                "Modifier mismatch rawOption=\(rawOption) hardwareOption=\(hardwareOption) rawControl=\(rawControl) hardwareControl=\(hardwareControl)"
            )
        }

        let optionPressed = rawOption || hardwareOption
        let controlPressed = rawControl || hardwareControl

        if !rawOption && hardwareOption {
            scheduleOptionReleaseRecheck()
        }

        if optionPressed && !isOptionPressed {
            optionReleaseRecheckWorkItem?.cancel()
            handleOptionPressed()
        } else if !optionPressed && isOptionPressed {
            handleOptionReleased()
        }

        if controlPressed && !isControlPressed {
            isControlPressed = true
            controlPressBeganAt = eventTimestamp()
        } else if !controlPressed && isControlPressed {
            handleControlReleasedForDoubleTap()
            isControlPressed = false
        }
    }

    /// 物理按键状态：`hidSystemState` 不受我们合成的粘贴事件影响。
    private func isHardwareKeyDown(_ keyCode: CGKeyCode) -> Bool {
        CGEventSource.keyState(.hidSystemState, key: keyCode)
    }

    private func isHardwareOptionDown() -> Bool {
        isHardwareKeyDown(58) || isHardwareKeyDown(61)
    }

    private func isHardwareControlDown() -> Bool {
        isHardwareKeyDown(59) || isHardwareKeyDown(62)
    }

    /// 合成事件会先把 flags 报成松开；稍后再看硬件状态，真松开才结束录音。
    private func scheduleOptionReleaseRecheck() {
        optionReleaseRecheckWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isOptionPressed else { return }
            guard !self.isHardwareOptionDown() else { return }
            VoiceTextLogger.log("Hold Option ended (hardware recheck)")
            self.handleOptionReleased()
        }
        optionReleaseRecheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func handleOptionPressed() {
        optionReleaseRecheckWorkItem?.cancel()
        isOptionPressed = true
        optionPressBeganAt = eventTimestamp()
        didBeginHold = false
        holdTimer?.invalidate()
        guard !isLockedRecording else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            guard let self, self.isOptionPressed else { return }
            self.didBeginHold = true
            self.tapTracker.reset()
            VoiceTextLogger.log("Hold Option began")
            self.onHoldBegan()
        }
    }

    private func handleOptionReleased() {
        optionReleaseRecheckWorkItem?.cancel()
        optionReleaseRecheckWorkItem = nil
        isOptionPressed = false
        holdTimer?.invalidate()
        holdTimer = nil
        optionPressBeganAt = nil
        if didBeginHold {
            didBeginHold = false
            VoiceTextLogger.log("Hold Option ended")
            onHoldEnded()
        }
    }

    private func handleControlReleasedForDoubleTap() {
        let pressDuration = eventTimestamp() - (controlPressBeganAt ?? eventTimestamp())
        controlPressBeganAt = nil
        guard !didBeginHold else { return }

        guard tapTracker.recordTap(pressDuration: pressDuration, releaseTime: eventTimestamp()) else { return }
        if isLockedRecording {
            isLockedRecording = false
            VoiceTextLogger.log("Double Control stopped locked recording")
            onDoubleTap()
        } else {
            isLockedRecording = true
            VoiceTextLogger.log("Double Control started locked recording")
            onDoubleTap()
        }
    }

    private func eventTimestamp() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
