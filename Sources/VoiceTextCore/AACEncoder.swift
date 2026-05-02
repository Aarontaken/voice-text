import AVFoundation
import Foundation

public final class AACEncoder {
    public enum EncoderError: Error {
        case missingInputFormat
        case missingOutputFormat
        case conversionFailed
        case emptyOutput
    }

    private let sampleRate: Double
    private let channelCount: AVAudioChannelCount
    private let bitRate: Int
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?

    public init(sampleRate: Double = 16_000, channelCount: AVAudioChannelCount = 1, bitRate: Int = 32_000) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitRate = bitRate
    }

    public func encode(_ pcmBuffer: AVAudioPCMBuffer) throws -> Data {
        try encodePackets(pcmBuffer).reduce(Data(), +)
    }

    public func encodePackets(_ pcmBuffer: AVAudioPCMBuffer) throws -> [Data] {
        if converter == nil {
            try prepareConverter(inputFormat: pcmBuffer.format)
        }

        guard let converter, let outputFormat else {
            throw EncoderError.missingOutputFormat
        }

        var didProvideInput = false
        var packets: [Data] = []

        while true {
            let compressedBuffer = AVAudioCompressedBuffer(
                format: outputFormat,
                packetCapacity: 8,
                maximumPacketSize: converter.maximumOutputPacketSize
            )

            var conversionError: NSError?
            let status = converter.convert(to: compressedBuffer, error: &conversionError) { _, outStatus in
                if didProvideInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                didProvideInput = true
                outStatus.pointee = .haveData
                return pcmBuffer
            }

            if status == .error || conversionError != nil {
                throw conversionError ?? EncoderError.conversionFailed
            }

            if compressedBuffer.byteLength > 0 {
                packets.append(contentsOf: makeADTSPackets(from: compressedBuffer))
            }

            if status != .haveData {
                break
            }
        }

        guard !packets.isEmpty else {
            throw EncoderError.emptyOutput
        }

        return packets
    }

    public func reset() {
        converter?.reset()
    }

    private func prepareConverter(inputFormat: AVAudioFormat) throws {
        self.inputFormat = inputFormat
        guard let outputFormat = AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]) else {
            throw EncoderError.missingOutputFormat
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw EncoderError.conversionFailed
        }
        self.outputFormat = outputFormat
        self.converter = converter
    }

    private func makeADTSPackets(from compressedBuffer: AVAudioCompressedBuffer) -> [Data] {
        let packetCount = Int(compressedBuffer.packetCount)
        guard packetCount > 1, let descriptions = compressedBuffer.packetDescriptions else {
            let payload = Data(bytes: compressedBuffer.data, count: Int(compressedBuffer.byteLength))
            return [makeADTSPacket(payload: payload)]
        }

        return (0..<packetCount).compactMap { index in
            let description = descriptions[index]
            guard description.mDataByteSize > 0 else { return nil }
            let start = Int(description.mStartOffset)
            let size = Int(description.mDataByteSize)
            let payload = Data(bytes: compressedBuffer.data.advanced(by: start), count: size)
            return makeADTSPacket(payload: payload)
        }
    }

    private func makeADTSPacket(payload: Data) -> Data {
        let header = (try? ADTSHeader.makeValidatedHeader(
            payloadLength: payload.count,
            sampleRate: Int(sampleRate),
            channelCount: Int(channelCount)
        )) ?? Data()
        return header + payload
    }
}
