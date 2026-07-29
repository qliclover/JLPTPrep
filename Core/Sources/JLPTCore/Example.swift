import Foundation

/// 例句。单词和语法点共用。
///
/// `furigana` 用 `{漢字|かんじ}` 标注，例如 `{毎朝|まいあさ}パンを{食|た}べます。`
/// 刻意没用 Anki 的 `漢字[かんじ]` 格式 —— 那套要靠空格划分词边界，
/// 「お茶[ちゃ]」和「お 茶[ちゃ]」含义不同，很容易标错且肉眼看不出来。
/// 花括号是自闭合的，无歧义。
public struct Example: Codable, Equatable, Hashable, Sendable {
    public var ja: String
    public var furigana: String?
    public var zh: String
    public var audioFile: String?

    public init(ja: String, furigana: String? = nil, zh: String, audioFile: String? = nil) {
        self.ja = ja
        self.furigana = furigana
        self.zh = zh
        self.audioFile = audioFile
    }
}
