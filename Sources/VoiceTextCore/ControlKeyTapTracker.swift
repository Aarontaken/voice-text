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
