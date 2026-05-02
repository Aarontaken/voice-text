import AVFoundation
import Foundation

public final class AudioCaptureService {
    public enum CaptureError: Error {
        case microphonePermissionDenied
        case invalidInputFormat
        case conversionFailed
    }

    private let engine = AVAudioEngine()
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

    public init() {}

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
        isRunning = true
        capturedBufferCount = 0
        encodedPacketCount = 0

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
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

        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
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
