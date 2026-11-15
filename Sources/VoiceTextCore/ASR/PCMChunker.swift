import Foundation

/// 把采集到的 PCM 切成固定大小的包，并**保留最后一个包**。
///
/// 豆包要求最后一包音频带负数序号和 last 标志；实时录音时我们事先不知道哪一包是
/// 最后一包，所以必须压住一包不发，等 `finish()` 时再把它作为末包发出去。
public struct PCMChunker {
    public let chunkSize: Int
    private var buffer = Data()

    public init(chunkSize: Int = 6400) {
        precondition(chunkSize > 0, "chunkSize must be positive")
        self.chunkSize = chunkSize
    }

    public var pendingByteCount: Int {
        buffer.count
    }

    /// 追加 PCM，返回可以立即发送的完整包（至少压住一包在缓冲里）。
    public mutating func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)

        var chunks: [Data] = []
        while buffer.count >= chunkSize * 2 {
            chunks.append(Data(buffer.prefix(chunkSize)))
            buffer.removeFirst(chunkSize)
        }
        return chunks
    }

    /// 取出剩余数据。返回值中最后一个是末包，调用方需带 last 标志发送。
    ///
    /// 尾部不足一个整包时直接并进末包，避免发出只有几个字节的最后一帧
    /// （PCM16 还要求每个音频块的字节数为偶数）。
    public mutating func finish() -> [Data] {
        guard !buffer.isEmpty else { return [] }

        var chunks: [Data] = []
        while buffer.count > chunkSize * 3 / 2 {
            chunks.append(Data(buffer.prefix(chunkSize)))
            buffer.removeFirst(chunkSize)
        }
        chunks.append(buffer)
        buffer.removeAll(keepingCapacity: false)
        return chunks
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}
