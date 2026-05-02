import Foundation

public enum ADTSHeader {
    public enum HeaderError: Error, Equatable {
        case unsupportedSampleRate(Int)
        case unsupportedChannelCount(Int)
    }

    private static let frequencyIndexes: [Int: UInt8] = [
        96_000: 0,
        88_200: 1,
        64_000: 2,
        48_000: 3,
        44_100: 4,
        32_000: 5,
        24_000: 6,
        22_050: 7,
        16_000: 8,
        12_000: 9,
        11_025: 10,
        8_000: 11,
        7_350: 12
    ]

    public static func makeHeader(payloadLength: Int, sampleRate: Int, channelCount: Int) -> Data {
        let frequencyIndex = frequencyIndexes[sampleRate] ?? 8
        return makeHeader(payloadLength: payloadLength, frequencyIndex: frequencyIndex, channelCount: UInt8(channelCount))
    }

    public static func makeValidatedHeader(payloadLength: Int, sampleRate: Int, channelCount: Int) throws -> Data {
        guard let frequencyIndex = frequencyIndexes[sampleRate] else {
            throw HeaderError.unsupportedSampleRate(sampleRate)
        }
        guard (1...7).contains(channelCount) else {
            throw HeaderError.unsupportedChannelCount(channelCount)
        }
        return makeHeader(payloadLength: payloadLength, frequencyIndex: frequencyIndex, channelCount: UInt8(channelCount))
    }

    private static func makeHeader(payloadLength: Int, frequencyIndex: UInt8, channelCount: UInt8) -> Data {
        let packetLength = payloadLength + 7
        let profile: UInt8 = 2
        var header = Data(count: 7)

        header[0] = 0xFF
        header[1] = 0xF1
        header[2] = ((profile - 1) << 6) + (frequencyIndex << 2) + (channelCount >> 2)
        header[3] = ((channelCount & 3) << 6) + UInt8((packetLength >> 11) & 0x03)
        header[4] = UInt8((packetLength >> 3) & 0xFF)
        header[5] = UInt8((packetLength & 0x07) << 5) + 0x1F
        header[6] = 0xFC

        return header
    }
}
