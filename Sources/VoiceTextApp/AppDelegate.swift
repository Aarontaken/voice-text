import AppKit
import VoiceTextCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let textInserter = TextInsertionService()
    private var statusController: StatusBarController?
    private var recordingController: RecordingController?
    private var holdControlKeyService: HoldControlKeyService?
    private var settingsWindowController: SettingsWindowController?
    private var previewWindowController: RecognitionPreviewWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = loadConfiguration()
        let controller = RecordingController(
            configuration: configuration,
            textInserter: textInserter,
            settingsStore: settingsStore
        )
        let statusController = StatusBarController()
        let previewWindowController = RecognitionPreviewWindowController()

        controller.onStateChange = { [weak statusController] state in
            DispatchQueue.main.async {
                statusController?.update(state: state)
            }
        }
        controller.onPreviewChange = { [weak previewWindowController] state in
            DispatchQueue.main.async {
                switch state {
                case .hidden:
                    previewWindowController?.hide()
                case .preparing:
                    previewWindowController?.showPreparing()
                case .listening:
                    previewWindowController?.showListening()
                case .waiting:
                    previewWindowController?.showWaiting()
                case let .preview(text):
                    previewWindowController?.showPreview(text: text)
                }
            }
        }

        statusController.onToggle = { [weak controller] in
            controller?.toggle()
        }
        statusController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        statusController.onRequestAccessibility = { [weak self] in
            _ = self?.textInserter.ensureAccessibilityPermission(prompt: true)
        }
        statusController.accessibilityStatusProvider = { [weak self] in
            self?.textInserter.ensureAccessibilityPermission(prompt: false) ?? false
        }
        statusController.updateAccessibilityStatus()
        statusController.updateHotkeyDescription(Self.hotkeyDescription(for: configuration))

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

        self.recordingController = controller
        self.statusController = statusController
        self.holdControlKeyService = holdControlKeyService
        self.previewWindowController = previewWindowController
    }

    private func loadConfiguration() -> ASRConfiguration {
        do {
            return try settingsStore.load()
        } catch {
            return ASRConfiguration.defaultConfiguration()
        }
    }

    private func openSettings() {
        let controller = SettingsWindowController(settingsStore: settingsStore) { [weak self] configuration in
            self?.recordingController?.update(configuration: configuration)
            self?.statusController?.updateHotkeyDescription(Self.hotkeyDescription(for: configuration))
        }
        settingsWindowController = controller
        controller.window?.center()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func hotkeyDescription(for configuration: ASRConfiguration) -> String {
        "按住 Control 说话，松开结束"
    }
}
