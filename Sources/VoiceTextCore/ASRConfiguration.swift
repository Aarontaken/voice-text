import Foundation

/// 豆包语音识别配置。替代原来的小猿账号/环境/cookie 体系。
public struct ASRConfiguration: Codable, Equatable, Sendable {
    /// `X-Api-Resource-Id` 对应的模型版本。
    public enum Resource: String, Codable, CaseIterable, Sendable {
        case seedASRDuration = "volc.seedasr.sauc.duration"
        case seedASRConcurrent = "volc.seedasr.sauc.concurrent"
        case bigASRDuration = "volc.bigasr.sauc.duration"
        case bigASRConcurrent = "volc.bigasr.sauc.concurrent"

        public var displayName: String {
            switch self {
            case .seedASRDuration:
                return "2.0 小时版（推荐）"
            case .seedASRConcurrent:
                return "2.0 并发版"
            case .bigASRDuration:
                return "1.0 小时版"
            case .bigASRConcurrent:
                return "1.0 并发版"
            }
        }
    }

    /// 识别模式：一句话识别在松手后返回整句；实时识别边说边出字并按分句插入。
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case oneShot
        case realtime

        public var displayName: String {
            switch self {
            case .oneShot:
                return "一句话识别（松手出字，更准确）"
            case .realtime:
                return "实时识别（边说边出字）"
            }
        }
    }

    /// 新版控制台 API Key；留空则无法开始识别。
    public var apiKey: String
    public var mode: Mode
    public var resource: Resource
    /// 识别语种，空字符串表示自动（中英混合）。
    public var language: String
    /// 数字/日期/金额规范化。
    public var enableITN: Bool
    /// 自动添加标点。
    public var enablePunc: Bool
    /// 语义顺滑（删除语气词、重复词）。
    public var enableDDC: Bool
    /// 是否返回分句信息（当前 UI 未使用，保留给排查问题）。
    public var showUtterances: Bool
    /// VAD 静音判停阈值，单位毫秒。
    public var endWindowSize: Int
    /// 音频起始阶段强制按有声处理，单位毫秒。
    public var forceToSpeechTime: Int

    private enum CodingKeys: String, CodingKey {
        case apiKey
        case mode
        case resource
        case language
        case enableITN
        case enablePunc
        case enableDDC
        case showUtterances
        case endWindowSize
        case forceToSpeechTime
    }

    public init(
        apiKey: String = "",
        mode: Mode = .oneShot,
        resource: Resource = .seedASRDuration,
        language: String = "",
        enableITN: Bool = true,
        enablePunc: Bool = true,
        enableDDC: Bool = false,
        showUtterances: Bool = false,
        endWindowSize: Int = 800,
        forceToSpeechTime: Int = 1_000
    ) {
        self.apiKey = apiKey
        self.mode = mode
        self.resource = resource
        self.language = language
        self.enableITN = enableITN
        self.enablePunc = enablePunc
        self.enableDDC = enableDDC
        self.showUtterances = showUtterances
        self.endWindowSize = endWindowSize
        self.forceToSpeechTime = forceToSpeechTime
    }

    /// 所有字段都容忍缺失，旧版 settings.json 可以直接解码成默认值，不需要单独迁移脚本。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .oneShot
        resource = try container.decodeIfPresent(Resource.self, forKey: .resource) ?? .seedASRDuration
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        enableITN = try container.decodeIfPresent(Bool.self, forKey: .enableITN) ?? true
        enablePunc = try container.decodeIfPresent(Bool.self, forKey: .enablePunc) ?? true
        enableDDC = try container.decodeIfPresent(Bool.self, forKey: .enableDDC) ?? false
        showUtterances = try container.decodeIfPresent(Bool.self, forKey: .showUtterances) ?? false
        endWindowSize = try container.decodeIfPresent(Int.self, forKey: .endWindowSize) ?? 800
        forceToSpeechTime = try container.decodeIfPresent(Int.self, forKey: .forceToSpeechTime) ?? 1_000
    }

    public static func defaultConfiguration() -> ASRConfiguration {
        ASRConfiguration()
    }

    public var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 设置界面里的语种选项。
    public static let languageOptions: [(value: String, title: String)] = [
        ("", "自动（中英混合）"),
        ("zh-CN", "中文普通话"),
        ("en-US", "English")
    ]
}
