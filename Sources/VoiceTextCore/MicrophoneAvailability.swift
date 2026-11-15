import CoreAudio
import Foundation
import IOKit

/// 判断当前是否处于「必然录不到声音」的状态。
///
/// Apple 芯片与 T2 机型的 Mac 笔记本在合盖（clamshell）时会**在硬件层断开内建麦克风**
/// （Apple 平台安全指南：Hardware microphone disconnect），root、内核扩展、关闭 SIP 都无法绕过。
/// 麻烦之处在于 CoreAudio 仍照常把它报成默认输入设备：采集链路不报错、只是回调静音，
/// 应用侧看起来就是「录到了，但什么都识别不出来」。
///
/// 这里只做判定和提示，不改系统默认输入设备。
public enum MicrophoneAvailability {
    public enum Issue: Equatable {
        /// 合盖 + 默认输入仍是内建麦克风：此刻只能录到静音。
        case lidClosedWithBuiltInMicrophone

        /// 对话框标题。
        public var title: String {
            switch self {
            case .lidClosedWithBuiltInMicrophone:
                return "合盖时录不到声音"
            }
        }

        /// 原因说明与可操作建议。保持一句话，别让提示本身变成阅读负担。
        public var detail: String {
            switch self {
            case .lidClosedWithBuiltInMicrophone:
                return "合盖时系统会断开内置麦克风，接外置麦克风或打开机盖再试。"
            }
        }

        /// 状态栏菜单里显示的一行短提示。
        public var statusText: String {
            switch self {
            case .lidClosedWithBuiltInMicrophone:
                return "合盖时内建麦克风被系统断开"
            }
        }
    }

    /// 纯判定，便于单测：调用方给出「是否合盖」「默认输入是否内建」。
    public static func issue(lidClosed: Bool, defaultInputIsBuiltIn: Bool) -> Issue? {
        guard lidClosed, defaultInputIsBuiltIn else { return nil }
        return .lidClosedWithBuiltInMicrophone
    }

    /// 探测本机当前状态。
    public static func currentIssue() -> Issue? {
        let lidClosed = isLidClosed()
        let builtIn = isDefaultInputBuiltIn()
        VoiceTextLogger.log("Microphone preflight lidClosed=\(lidClosed) defaultInputIsBuiltIn=\(builtIn)")
        return issue(lidClosed: lidClosed, defaultInputIsBuiltIn: builtIn)
    }

    /// 机盖是否合上：读取 `IOPMrootDomain` 的 `AppleClamshellState`。
    public static func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return false
        }
        return (value as? Bool) ?? false
    }

    /// 默认输入设备是不是内建麦克风。没有输入设备时按内建麦处理：合盖场景下同样录不到声音。
    public static func isDefaultInputBuiltIn() -> Bool {
        guard let device = defaultInputDevice() else { return true }
        return transportType(of: device) == kAudioDeviceTransportTypeBuiltIn
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }
}
