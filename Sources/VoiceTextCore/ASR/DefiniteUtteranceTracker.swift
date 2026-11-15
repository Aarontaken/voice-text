import Foundation

/// 实时识别会持续返回累计结果，分句只有 `definite = true` 后才算定稿。
/// 这个 tracker 负责挑出「本次新定稿的分句」，避免同一句被插入多次。
public struct DefiniteUtteranceTracker {
    private var emittedKeys = Set<String>()

    public init() {}

    public mutating func takeNewDefinite(_ utterances: [DoubaoUtterance]) -> [String] {
        var texts: [String] = []

        for (index, utterance) in utterances.enumerated() where utterance.definite {
            let key = utterance.dedupKey(fallbackIndex: index)
            guard !emittedKeys.contains(key) else { continue }
            emittedKeys.insert(key)

            let text = utterance.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                texts.append(text)
            }
        }

        return texts
    }

    public mutating func reset() {
        emittedKeys.removeAll()
    }
}

private extension DoubaoUtterance {
    /// 优先用时间区间做身份；部分场景时间戳为 0 时退回数组下标。
    func dedupKey(fallbackIndex: Int) -> String {
        if startTime != 0 || endTime != 0 {
            return "\(startTime)-\(endTime)"
        }
        return "idx-\(fallbackIndex)"
    }
}
