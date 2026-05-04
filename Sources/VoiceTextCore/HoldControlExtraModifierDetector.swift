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
