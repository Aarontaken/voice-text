import AVFoundation
import Foundation
import QuartzCore

public final class AudioCaptureService {
    /// 引擎刚启动的一段时间内，`AVAudioEngineConfigurationChange` 常被误触发，勿当作真实路由切换。
    private static let configurationWarmupSeconds: CFTimeInterval = 0.45
    /// 仅当采音已进入稳定中段（足够多的 tap 回调 + 足够的经过时间），才认为这是「录音进行中」的设备变更；
    /// 否则忽略（否则会与启动噪声、蓝牙/HFP 偶发通报、Main 队列延迟等互相误伤）。
    private static let configurationReactionMinCapturedBuffers = 45
    private static let configurationReactionMinElapsedSeconds: CFTimeInterval = 1.2

    public enum CaptureError: Error {
        case microphonePermissionDenied
        case invalidInputFormat
        case conversionFailed
        /// 默认输入设备在录音过程中发生变化（常见于连接/断开蓝牙耳机或切换系统音效输出）。
        case hardwareRouteChanged
    }

    /// 每次会话使用新的引擎实例，避免蓝牙等路由切换后复用陈旧图导致断言或崩溃。
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private let encoder = AACEncoder()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )
    private var converter: AVAudioConverter?
    private let processingQueue = DispatchQueue(label: "AudioCaptureService.processingQueue")
    private var isRunning = false
    private var capturedBufferCount = 0
    private var encodedPacketCount = 0
    private var packetHandler: ((Data) -> Void)?
    private var errorHandler: ((Error) -> Void)?
    /// 当前这次 `engine.start()` 成功的单调时钟原点；未完成启动则为 nil。
    private var recordingSessionStartMediaTime: CFTimeInterval?

    public init() {}

    deinit {
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func requestPermission(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    public func start(
        onPacket: @escaping (Data) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) != .denied else {
            throw CaptureError.microphonePermissionDenied
        }
        guard let targetFormat else {
            throw CaptureError.invalidInputFormat
        }

        packetHandler = onPacket
        errorHandler = onError
        capturedBufferCount = 0
        encodedPacketCount = 0
        recordingSessionStartMediaTime = nil

        let engine = AVAudioEngine()
        self.engine = engine

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                guard let sessionStart = self.recordingSessionStartMediaTime else { return }

                let elapsed = CACurrentMediaTime() - sessionStart
                guard elapsed >= Self.configurationWarmupSeconds else {
                    VoiceTextLogger.log(
                        "AVAudioEngine configurationChange ignored (\(Int(elapsed * 1000))ms < \(Int(Self.configurationWarmupSeconds * 1000))ms warmup)"
                    )
                    return
                }
                guard self.capturedBufferCount >= Self.configurationReactionMinCapturedBuffers else {
                    VoiceTextLogger.log(
                        "AVAudioEngine configurationChange ignored (buffers=\(self.capturedBufferCount)/\(Self.configurationReactionMinCapturedBuffers))"
                    )
                    return
                }
                guard elapsed >= Self.configurationReactionMinElapsedSeconds else {
                    VoiceTextLogger.log(
                        "AVAudioEngine configurationChange ignored (elapsed=\(Int(elapsed * 1000))ms < \(Int(Self.configurationReactionMinElapsedSeconds * 1000))ms with buffers)"
                    )
                    return
                }

                VoiceTextLogger.log(
                    "Audio engine configuration changed after stable capture \(Int(elapsed * 1000))ms buffers=\(self.capturedBufferCount); stopping capture"
                )
                let report = self.errorHandler
                self.stop()
                report?(CaptureError.hardwareRouteChanged)
            }
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            tearDownIncompleteStart()
            throw CaptureError.conversionFailed
        }
        self.converter = converter

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let copiedBuffer = buffer.deepCopy() else { return }
            self.capturedBufferCount += 1
            if self.capturedBufferCount == 1 || self.capturedBufferCount % 50 == 0 {
                VoiceTextLogger.log("Audio captured buffers=\(self.capturedBufferCount) frames=\(buffer.frameLength)")
            }
            self.processingQueue.async { [weak self] in
                self?.handle(copiedBuffer, targetFormat: targetFormat)
            }
        }

        do {
            try engine.start()
        } catch {
            tearDownIncompleteStart()
            throw error
        }
        recordingSessionStartMediaTime = CACurrentMediaTime()
        isRunning = true
    }

    /// 在 `start()` 成功启动引擎之前失败时释放图与监听，避免 `isRunning` 被误置为 true。
    private func tearDownIncompleteStart() {
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
        }
        converter = nil
        recordingSessionStartMediaTime = nil
    }

    public func stop() {
        guard isRunning else {
            return
        }
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }

        guard let engine else {
            isRunning = false
            recordingSessionStartMediaTime = nil
            converter = nil
            packetHandler = nil
            errorHandler = nil
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        isRunning = false
        recordingSessionStartMediaTime = nil
        processingQueue.async { [encoder] in
            encoder.reset()
        }
        converter = nil
        packetHandler = nil
        errorHandler = nil
    }

    private func handle(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard isRunning, let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            errorHandler?(CaptureError.conversionFailed)
            return
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error || conversionError != nil {
            errorHandler?(conversionError ?? CaptureError.conversionFailed)
            return
        }

        do {
            let packets = try encoder.encodePackets(convertedBuffer)
            for packet in packets {
                encodedPacketCount += 1
                if encodedPacketCount == 1 || encodedPacketCount % 20 == 0 {
                    VoiceTextLogger.log("Audio encoded packets=\(encodedPacketCount) bytes=\(packet.count)")
                }
                if encodedPacketCount == 1 {
                    VoiceTextLogger.log("Audio first packet hex=\(packet.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))")
                }
                packetHandler?(packet)
            }
        } catch AACEncoder.EncoderError.emptyOutput {
            return
        } catch {
            errorHandler?(error)
        }
    }
}

private extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        copy.frameLength = frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<sourceBuffers.count {
            guard let source = sourceBuffers[index].mData,
                  let destination = destinationBuffers[index].mData else {
                continue
            }
            memcpy(destination, source, Int(sourceBuffers[index].mDataByteSize))
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }

        return copy
    }
}

extension AudioCaptureService.CaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "未授予麦克风权限。"
        case .invalidInputFormat:
            return "无法建立音频采集格式。"
        case .conversionFailed:
            return "音频重采样失败。"
        case .hardwareRouteChanged:
            return "音频输入设备已切换（常见于连接或断开蓝牙耳机），请重新开始录音。"
        }
    }
}
