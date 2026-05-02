import AppKit
import VoiceTextCore

final class HoldControlKeyService {
    private let holdThreshold: TimeInterval
    private let onHoldBegan: () -> Void
    private let onHoldEnded: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var holdTimer: Timer?
    private var isControlPressed = false
    private var didBeginHold = false

    init(holdThreshold: TimeInterval, onHoldBegan: @escaping () -> Void, onHoldEnded: @escaping () -> Void) {
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
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
        VoiceTextLogger.log("Hold Control key monitor registered")
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
        isControlPressed = false
        didBeginHold = false
    }

    private func handle(_ event: NSEvent) {
        let controlPressed = event.modifierFlags.contains(.control)
        if controlPressed && !isControlPressed {
            handleControlPressed()
        } else if !controlPressed && isControlPressed {
            handleControlReleased()
        }
    }

    private func handleControlPressed() {
        isControlPressed = true
        didBeginHold = false
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            guard let self, self.isControlPressed else { return }
            self.didBeginHold = true
            VoiceTextLogger.log("Hold Control key began")
            self.onHoldBegan()
        }
    }

    private func handleControlReleased() {
        isControlPressed = false
        holdTimer?.invalidate()
        holdTimer = nil
        guard didBeginHold else { return }
        didBeginHold = false
        VoiceTextLogger.log("Hold Control key ended")
        onHoldEnded()
    }
}
