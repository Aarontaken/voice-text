import AppKit
import ApplicationServices
import Foundation

public final class TextInsertionService {
    public enum InsertionError: Error {
        case accessibilityPermissionMissing
        case noFocusedElement
        case pasteboardWriteFailed
    }

    public init() {}

    public func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func insert(_ text: String) throws {
        guard !text.isEmpty else { return }

        let isTrusted = ensureAccessibilityPermission(prompt: false)
        VoiceTextLogger.log("Text insertion accessibilityTrusted=\(isTrusted)")
        if isTrusted, (try? insertWithAccessibility(text)) == true {
            VoiceTextLogger.log("Text inserted with accessibility count=\(text.count)")
            return
        }

        VoiceTextLogger.log("Text insertion falling back to paste count=\(text.count)")
        try paste(text)
    }

    private func insertWithAccessibility(_ text: String) throws -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard result == .success, let focusedValue else {
            VoiceTextLogger.log("Text AX focused element failed result=\(result.rawValue)")
            throw InsertionError.noFocusedElement
        }

        let focusedElement = focusedValue as! AXUIElement
        let selectedTextResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        VoiceTextLogger.log("Text AX selectedText result=\(selectedTextResult.rawValue)")
        if selectedTextResult == .success {
            return true
        }

        var valueRef: CFTypeRef?
        let copyValueResult = AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &valueRef)
        guard copyValueResult == .success,
              let currentValue = valueRef as? String else {
            VoiceTextLogger.log("Text AX value copy failed result=\(copyValueResult.rawValue)")
            return false
        }

        let newValue = currentValue + text
        let setValueResult = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, newValue as CFTypeRef)
        VoiceTextLogger.log("Text AX value set result=\(setValueResult.rawValue)")
        return setValueResult == .success
    }

    private func paste(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw InsertionError.pasteboardWriteFailed
        }

        sendCommandV()
        VoiceTextLogger.log("Text pasted count=\(text.count)")
    }

    private func sendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        usleep(50_000)
        keyUp?.post(tap: .cghidEventTap)
    }
}
