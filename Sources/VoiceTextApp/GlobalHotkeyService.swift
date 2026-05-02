import Carbon
import Foundation
import VoiceTextCore

final class GlobalHotkeyService {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false

    private var hotkeyRef: EventHotKeyRef?
    private var keyCode: UInt32
    private var modifiers: UInt32
    private let id: UInt32
    private let handler: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
        self.id = Self.nextID
        Self.nextID += 1
        Self.handlers[id] = handler
    }

    deinit {
        unregister()
        Self.handlers.removeValue(forKey: id)
    }

    func register() {
        unregister()
        Self.installEventHandlerIfNeeded()

        let hotkeyID = EventHotKeyID(signature: OSType("VTXT".fourCharCode), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        VoiceTextLogger.log("Hotkey register keyCode=\(keyCode) modifiers=\(modifiers) status=\(status)")
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        register()
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                VoiceTextLogger.log("Hotkey triggered id=\(hotkeyID.id)")
                GlobalHotkeyService.handlers[hotkeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        eventHandlerInstalled = true
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for scalar in unicodeScalars {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }
}
