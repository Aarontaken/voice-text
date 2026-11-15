import Compression
import Foundation

/// gzip（RFC 1952）编解码。
///
/// 豆包 v3 协议要求 payload 带 `CompressionType.GZIP` 标志。Apple 的 `Compression`
/// 框架只有 raw DEFLATE（`COMPRESSION_ZLIB`），没有 gzip 容器，因此这里手工拼
/// 10 字节头 + raw DEFLATE + 8 字节尾（CRC32 / ISIZE）。
public enum Gzip {
    public enum GzipError: Error, Equatable {
        case invalidHeader
        case truncated
        case compressionFailed
    }

    private static let headerBytes: [UInt8] = [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03]
    private static let maxBufferSize = 64 * 1024 * 1024

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    public static func compress(_ data: Data) throws -> Data {
        var output = Data(headerBytes)
        if data.isEmpty {
            output.append(contentsOf: [0x03, 0x00])
        } else {
            output.append(try rawDeflate(data))
        }

        var crc = crc32(data).littleEndian
        var isize = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &crc) { output.append(contentsOf: $0) }
        withUnsafeBytes(of: &isize) { output.append(contentsOf: $0) }
        return output
    }

    public static func decompress(_ data: Data) throws -> Data {
        guard data.count >= 18 else { throw GzipError.truncated }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 0x08 else {
            throw GzipError.invalidHeader
        }

        let flags = bytes[3]
        var offset = 10

        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { throw GzipError.truncated }
            let extraLength = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + extraLength
        }
        if flags & 0x08 != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 {
            offset += 2
        }

        guard offset <= bytes.count - 8 else { throw GzipError.truncated }

        let isize = UInt32(bytes[bytes.count - 4])
            | (UInt32(bytes[bytes.count - 3]) << 8)
            | (UInt32(bytes[bytes.count - 2]) << 16)
            | (UInt32(bytes[bytes.count - 1]) << 24)
        if isize == 0 {
            return Data()
        }

        let body = Data(bytes[offset..<(bytes.count - 8)])
        return try rawInflate(body, sizeHint: Int(isize))
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func rawDeflate(_ data: Data) throws -> Data {
        var capacity = max(256, data.count + data.count / 4 + 64)
        while capacity <= maxBufferSize {
            var output = [UInt8](repeating: 0, count: capacity)
            let written = output.withUnsafeMutableBufferPointer { buffer -> Int in
                data.withUnsafeBytes { raw -> Int in
                    guard let input = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_encode_buffer(
                        buffer.baseAddress!,
                        capacity,
                        input,
                        data.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if written > 0 {
                return Data(output[0..<written])
            }
            capacity *= 4
        }
        throw GzipError.compressionFailed
    }

    private static func rawInflate(_ data: Data, sizeHint: Int) throws -> Data {
        var capacity = max(1024, sizeHint + 64)
        while capacity <= maxBufferSize {
            var output = [UInt8](repeating: 0, count: capacity)
            let written = output.withUnsafeMutableBufferPointer { buffer -> Int in
                data.withUnsafeBytes { raw -> Int in
                    guard let input = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(
                        buffer.baseAddress!,
                        capacity,
                        input,
                        data.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if written > 0 {
                return Data(output[0..<written])
            }
            capacity *= 4
        }
        throw GzipError.compressionFailed
    }
}
