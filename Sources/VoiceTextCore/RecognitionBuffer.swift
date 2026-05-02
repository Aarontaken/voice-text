import Foundation

public struct RecognitionBuffer {
    private var lastRecognizedText = ""

    public init() {}

    public mutating func consume(_ result: RecognitionResult) -> String {
        let nextText = result.text
        let delta = deltaText(from: lastRecognizedText, to: nextText)

        if result.isFinal {
            lastRecognizedText = ""
        } else {
            lastRecognizedText = nextText
        }
        return delta
    }

    public mutating func reset() {
        lastRecognizedText = ""
    }

    private func deltaText(from previousText: String, to nextText: String) -> String {
        guard !nextText.isEmpty else { return "" }
        guard !previousText.isEmpty else { return nextText }
        guard nextText != previousText else { return "" }

        if nextText.hasPrefix(previousText) {
            return String(nextText.dropFirst(previousText.count))
        }

        if previousText.hasPrefix(nextText) {
            return ""
        }

        let commonPrefixCount = previousText.commonPrefix(with: nextText).count
        if commonPrefixCount > 0, nextText.count >= previousText.count {
            return String(nextText.dropFirst(commonPrefixCount))
        }

        return nextText
    }
}
