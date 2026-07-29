import Foundation
import SwiftData
import JLPTCore

/// 单词。**只存内容，不存进度** —— 进度在 `ReviewItemEntity` 里。
///
/// 这个切分是内容包能反复更新的前提：修了一个错别字重新导入，
/// 只会改这张表，用户背了三个月的 SRS 状态一根汗毛都不会动。
@Model
public final class VocabEntity {
    /// 内容包里的稳定 ID，跨版本不变。所有 upsert 都认它。
    @Attribute(.unique) public var slug: String
    /// 表记，如「食べる」。
    public var expression: String
    /// 假名读音，如「たべる」。
    public var reading: String
    /// `{漢字|かんじ}` 格式的振假名标注。
    public var furigana: String?
    /// 中文释义。只有 JLPT 核心词有。
    public var meaningZh: String
    /// 英文释义（JMdict / 社区词表）。中文缺位时显示它。
    public var meaningEn: String?
    public var partOfSpeech: String
    public var levelRaw: String
    public var audioFile: String?
    public var tags: [String]
    public var examples: [Example]
    /// 来源内容包，用于「这个包里消失的词该退役」的判断。
    public var packID: String
    /// 新版内容包里不再出现的词。不物理删除，否则会连带删掉用户的复习历史。
    public var isRetired: Bool

    public var level: JLPTLevel {
        get { JLPTLevel(rawValue: levelRaw) ?? .n5 }
        set { levelRaw = newValue.rawValue }
    }

    /// 显示用释义：有中文用中文，没有退到英文。
    public var displayMeaning: String {
        meaningZh.isEmpty ? (meaningEn ?? "") : meaningZh
    }

    public init(
        slug: String,
        expression: String,
        reading: String,
        furigana: String? = nil,
        meaningZh: String,
        meaningEn: String? = nil,
        partOfSpeech: String,
        level: JLPTLevel,
        audioFile: String? = nil,
        tags: [String] = [],
        examples: [Example] = [],
        packID: String,
        isRetired: Bool = false
    ) {
        self.slug = slug
        self.expression = expression
        self.reading = reading
        self.furigana = furigana
        self.meaningZh = meaningZh
        self.meaningEn = meaningEn
        self.partOfSpeech = partOfSpeech
        self.levelRaw = level.rawValue
        self.audioFile = audioFile
        self.tags = tags
        self.examples = examples
        self.packID = packID
        self.isRetired = isRetired
    }
}

/// 语法点。结构和 `VocabEntity` 对称，同样只存内容。
@Model
public final class GrammarEntity {
    @Attribute(.unique) public var slug: String
    /// 句型，如「〜てもいいです」。
    public var pattern: String
    /// 接续规则说明。
    public var connectionRule: String
    public var meaningZh: String
    /// 常见误用 / 对比说明。
    public var noteZh: String?
    public var levelRaw: String
    public var tags: [String]
    public var examples: [Example]
    /// 易混句型的 slug，做「〜ている vs 〜てある」这种对比跳转。
    public var contrastSlugs: [String]
    public var packID: String
    public var isRetired: Bool

    public var level: JLPTLevel {
        get { JLPTLevel(rawValue: levelRaw) ?? .n5 }
        set { levelRaw = newValue.rawValue }
    }

    public init(
        slug: String,
        pattern: String,
        connectionRule: String,
        meaningZh: String,
        noteZh: String? = nil,
        level: JLPTLevel,
        tags: [String] = [],
        examples: [Example] = [],
        contrastSlugs: [String] = [],
        packID: String,
        isRetired: Bool = false
    ) {
        self.slug = slug
        self.pattern = pattern
        self.connectionRule = connectionRule
        self.meaningZh = meaningZh
        self.noteZh = noteZh
        self.levelRaw = level.rawValue
        self.tags = tags
        self.examples = examples
        self.contrastSlugs = contrastSlugs
        self.packID = packID
        self.isRetired = isRetired
    }
}
