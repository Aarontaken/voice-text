import AppKit
import VoiceTextCore

final class HoldControlKeyService {
    /// macOS virtual key codes for cursor arrows (system may handle Control+Arrow before some NSEvent paths).
    private static let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]

    private let holdThreshold: TimeInterval
    private var tapTracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)
    private let onHoldBegan: () -> Void
    private let onHoldEnded: () -> Void
    private let onDoubleTap: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var holdTimer: Timer?
    private var pressBeganAt: TimeInterval?
    private var isControlPressed = false
    private var didBeginHold = false
    private var isLockedRecording = false
    private var suppressTapUntilControlReleased = false
    private var keyDownGlobalMonitor: Any?
    private var keyDownLocalMonitor: Any?
    private var workspaceSpaceObserver: NSObjectProtocol?

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
        VoiceTextLogger.log(
            "Hold Control flags monitor registered global=\(globalMonitor != nil) local=\(localMonitor != nil)"
        )
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
        removeHoldSessionInputObservers()
        pressBeganAt = nil
        isControlPressed = false
        didBeginHold = false
        isLockedRecording = false
        suppressTapUntilControlReleased = false
        tapTracker.reset()
    }

    func resetTriggerState() {
        holdTimer?.invalidate()
        holdTimer = nil
        removeHoldSessionInputObservers()
        pressBeganAt = nil
        isControlPressed = false
        didBeginHold = false
        isLockedRecording = false
        suppressTapUntilControlReleased = false
        tapTracker.reset()
    }

    private func handle(_ event: NSEvent) {
        let controlPressed = event.modifierFlags.contains(.control)
        if controlPressed && !isControlPressed {
            handleControlPressed()
        } else if !controlPressed && isControlPressed {
            handleControlReleased()
        }
        if didBeginHold, controlPressed, isControlPressed {
            let raw = UInt64(event.modifierFlags.rawValue)
            if HoldControlExtraModifierDetector.shouldCancelHoldBecauseAddedModifiers(deviceIndependentRaw: raw) {
                cancelActiveHoldDueToCombo(reasonLog: "Hold Control cancelled: extra modifier flags")
            }
        }
    }

    private func handleControlPressed() {
        isControlPressed = true
        pressBeganAt = eventTimestamp()
        didBeginHold = false
        holdTimer?.invalidate()
        guard !isLockedRecording else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            guard let self, self.isControlPressed else { return }
            self.didBeginHold = true
            self.tapTracker.reset()
            VoiceTextLogger.log("Hold Control key began")
            self.installHoldSessionInputObservers()
            self.onHoldBegan()
        }
    }

    private func cancelActiveHoldDueToCombo(reasonLog: String) {
        guard didBeginHold else { return }
        VoiceTextLogger.log(reasonLog)
        removeHoldSessionInputObservers()
        didBeginHold = false
        suppressTapUntilControlReleased = true
        onHoldEnded()
    }

    private func installHoldSessionInputObservers() {
        guard keyDownGlobalMonitor == nil, keyDownLocalMonitor == nil else { return }
        keyDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if Thread.isMainThread {
                self.handleKeyDownDuringHold(event)
            } else {
                DispatchQueue.main.sync {
                    self.handleKeyDownDuringHold(event)
                }
            }
        }
        keyDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let work = { self.handleKeyDownDuringHold(event) }
            if Thread.isMainThread {
                work()
            } else {
                DispatchQueue.main.sync(execute: work)
            }
            return event
        }
        VoiceTextLogger.log(
            "Hold keyDown monitors installed global=\(keyDownGlobalMonitor != nil) local=\(keyDownLocalMonitor != nil) (global nil usually means Accessibility off)"
        )
        installWorkspaceSpaceObserver()
    }

    private func installWorkspaceSpaceObserver() {
        guard workspaceSpaceObserver == nil else { return }
        workspaceSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            self?.cancelHoldIfActiveSpaceChangedDuringHold()
        }
        VoiceTextLogger.log("Hold Control installed NSWorkspace.activeSpaceDidChange observer")
    }

    private func cancelHoldIfActiveSpaceChangedDuringHold() {
        guard didBeginHold, isControlPressed else { return }
        cancelActiveHoldDueToCombo(reasonLog: "Hold Control cancelled: active space changed")
    }

    private func removeHoldSessionInputObservers() {
        if let keyDownGlobalMonitor {
            NSEvent.removeMonitor(keyDownGlobalMonitor)
            self.keyDownGlobalMonitor = nil
        }
        if let keyDownLocalMonitor {
            NSEvent.removeMonitor(keyDownLocalMonitor)
            self.keyDownLocalMonitor = nil
        }
        if let workspaceSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceSpaceObserver)
            self.workspaceSpaceObserver = nil
        }
    }

    private func handleKeyDownDuringHold(_ event: NSEvent) {
        guard didBeginHold, isControlPressed else { return }
        if event.isARepeat { return }
        if event.keyCode == 59 || event.keyCode == 62 { return }

        let isArrow = Self.arrowKeyCodes.contains(event.keyCode)
        let controlInEvent = event.modifierFlags.contains(.control)
        if controlInEvent || isArrow {
            VoiceTextLogger.log(
                "Hold keyDown keyCode=\(event.keyCode) controlInEvent=\(controlInEvent) isArrow=\(isArrow) rawFlags=\(event.modifierFlags.rawValue)"
            )
        }

        guard controlInEvent || isArrow else { return }
        if isArrow {
            cancelActiveHoldDueToCombo(
                reasonLog: "Hold Control cancelled: arrow key during hold (keyCode=\(event.keyCode))"
            )
        } else {
            cancelActiveHoldDueToCombo(
                reasonLog: "Hold Control cancelled: keyDown while Control held (keyCode=\(event.keyCode))"
            )
        }
    }

    private func handleControlReleased() {
        isControlPressed = false
        holdTimer?.invalidate()
        holdTimer = nil
        removeHoldSessionInputObservers()

        if suppressTapUntilControlReleased {
            suppressTapUntilControlReleased = false
            pressBeganAt = nil
            tapTracker.reset()
            return
        }

        let pressDuration = eventTimestamp() - (pressBeganAt ?? eventTimestamp())
        pressBeganAt = nil
        if didBeginHold {
            VoiceTextLogger.log("Hold Control key ended")
            onHoldEnded()
            didBeginHold = false
            return
        }

        guard tapTracker.recordTap(pressDuration: pressDuration, releaseTime: eventTimestamp()) else { return }
        if isLockedRecording {
            isLockedRecording = false
            VoiceTextLogger.log("Double Control key stopped locked recording")
            onDoubleTap()
        } else {
            isLockedRecording = true
            VoiceTextLogger.log("Double Control key started locked recording")
            onDoubleTap()
        }
    }

    private func eventTimestamp() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
