import Foundation
import JLPTCore

/// 内容包的 JSON 结构。内容用文件维护、App 只负责渲染与调度，所以这一层就是全部的内容契约。
///
/// `schemaVersion` 变化 = 结构变了，导入器要么迁移要么拒绝；
/// `packID` 是包的身份，同一个 packID 的新版本会覆盖旧内容（但不动进度）。
public struct VocabPack: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var packID: String
    public var level: JLPTLevel
    public var vocab: [VocabSeed]

    public init(schemaVersion: Int = ContentPackSchema.current, packID: String, level: JLPTLevel, vocab: [VocabSeed]) {
        self.schemaVersion = schemaVersion
        self.packID = packID
        self.level = level
        self.vocab = vocab
    }
}

public struct VocabSeed: Codable, Equatable, Sendable {
    public var slug: String
    public var expression: String
    public var reading: String
    public var furigana: String?
    /// 中文释义。只有 JLPT 核心词有 —— 日中的开源词典不存在，靠手工维护。
    public var meaningZh: String
    /// 英文释义。来自社区词表，覆盖全部等级，是中文缺位时的兜底。
    public var meaningEn: String?
    public var partOfSpeech: String
    /// 缺省时用整包的 `level`。
    public var level: JLPTLevel?
    public var tags: [String]?
    public var audioFile: String?
    public var examples: [Example]?

    public init(
        slug: String,
        expression: String,
        reading: String,
        furigana: String? = nil,
        meaningZh: String,
        meaningEn: String? = nil,
        partOfSpeech: String,
        level: JLPTLevel? = nil,
        tags: [String]? = nil,
        audioFile: String? = nil,
        examples: [Example]? = nil
    ) {
        self.slug = slug
        self.expression = expression
        self.reading = reading
        self.furigana = furigana
        self.meaningZh = meaningZh
        self.meaningEn = meaningEn
        self.partOfSpeech = partOfSpeech
        self.level = level
        self.tags = tags
        self.audioFile = audioFile
        self.examples = examples
    }
}

public enum ContentPackSchema {
    /// v2 加了 `meaningEn`：全等级词表只有英文释义，中英必须分开存。
    public static let current = 2

    public static func decoder() -> JSONDecoder { JSONDecoder() }

    /// 算内容指纹用的编码器。`sortedKeys` 保证同样的内容永远得到同样的字节序列，
    /// 否则字典顺序一抖，指纹就变了，每次启动都会白白重跑一遍导入。
    public static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public enum ContentPackError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case duplicateSlugs([String])
    case emptyPack(packID: String)

    /// 不实现这个的话，界面上只会显示「ContentPackError error 1」——
    /// 对着这种信息没人能判断出问题在哪。
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let found, let supported):
            "内容包格式版本 \(found) 不受支持（当前支持 \(supported)）"
        case .duplicateSlugs(let slugs):
            "内容包里有重复的 slug：\(slugs.prefix(5).joined(separator: "、"))"
                + (slugs.count > 5 ? " 等 \(slugs.count) 个" : "")
        case .emptyPack(let packID):
            "内容包 \(packID) 里没有词条"
        }
    }
}
