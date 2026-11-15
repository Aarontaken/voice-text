import AppKit
import VoiceTextCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let textInserter = TextInsertionService()
    private var statusController: StatusBarController?
    private var recordingController: RecordingController?
    private var holdOptionKeyService: HoldOptionKeyService?
    private var settingsWindowController: SettingsWindowController?
    private var previewWindowController: RecognitionPreviewWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        VoiceTextLogger.log(
            "App launch bundle=\(Bundle.main.bundlePath) accessibilityTrusted=\(textInserter.ensureAccessibilityPermission(prompt: false))"
        )
        let configuration = loadConfiguration()
        let controller = RecordingController(
            configuration: configuration,
            textInserter: textInserter
        )
        let statusController = StatusBarController()
        let previewWindowController = RecognitionPreviewWindowController()

        controller.onStateChange = { [weak self, weak statusController] state in
            DispatchQueue.main.async {
                statusController?.update(state: state)
                switch state {
                case .idle, .error:
                    self?.holdOptionKeyService?.resetTriggerState()
                case .connecting, .recording, .finalizing:
                    break
                }
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
        statusController.updateHotkeyDescription(Self.hotkeyDescription)

        let holdOptionKeyService = HoldOptionKeyService(
            holdThreshold: 0.25,
            onHoldBegan: { [weak controller] in
                controller?.start()
            },
            onHoldEnded: { [weak controller] in
                controller?.stop()
            },
            onDoubleTap: { [weak controller] in
                controller?.toggle()
            }
        )
        holdOptionKeyService.register()

        self.recordingController = controller
        self.statusController = statusController
        self.holdOptionKeyService = holdOptionKeyService
        self.previewWindowController = previewWindowController

        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openSettings()
            }
        }
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
            self?.statusController?.updateHotkeyDescription(Self.hotkeyDescription)
        }
        settingsWindowController = controller
        controller.window?.center()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static let hotkeyDescription = "按住 Option (⌥) 说话，松开结束；双击 Control 开始/停止"
}
