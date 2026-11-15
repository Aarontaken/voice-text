import Foundation

/// 一次语音识别会话对外暴露的事件。
public enum ASREvent: Equatable, Sendable {
    /// 服务端已确认初始化请求，可以开始送音频。
    case ready
    /// 中间结果（豆包一句话识别可能只在结尾返回，因此该事件不是必然出现）。
    case preview(String)
    /// 实时模式下已经定稿的一个分句（`definite = true`），可以立即插入。
    case segmentFinal(String)
    /// 拿到最终结果，`text` 为整句文本。
    case completed(text: String, logId: String?)
    case failed(ASRServiceError)
}

public struct ASRServiceError: Error, Equatable, Sendable, LocalizedError {
    public let code: Int?
    public let message: String

    public init(message: String, code: Int? = nil) {
        self.message = message
        self.code = code
    }

    public var errorDescription: String? {
        message
    }
}

/// ASR 供应商边界。`RecordingController` 只依赖这个协议，换供应商不影响会话编排。
public protocol ASRSession: AnyObject {
    var onEvent: ((ASREvent) -> Void)? { get set }

    /// 建立连接并发送初始化请求。
    func start() throws
    /// 追加 16kHz / 16bit / 单声道 PCM 数据。
    func append(_ pcm: Data)
    /// 结束送音频，并等待服务端返回最终结果。
    func finish()
    /// 直接取消，不伪装成正常完成。
    func cancel()
}
