import AppKit
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
        optionPressBeganAt = nil
        controlPressBeganAt = nil
        isOptionPressed = false
        isControlPressed = false
        didBeginHold = false
        isLockedRecording = false
        tapTracker.reset()
    }

    private func handle(_ event: NSEvent) {
        let optionPressed = event.modifierFlags.contains(.option)
        let controlPressed = event.modifierFlags.contains(.control)

        if optionPressed && !isOptionPressed {
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

    private func handleOptionPressed() {
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
