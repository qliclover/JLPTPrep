import Foundation
import JLPTCore

/// 阅读器里的一个可点击单位。
///
/// 它同时承载两套切分：**显示**按振假名段落（`{漢字|かんじ}`），**交互**按分词。
/// 两者未必对齐 —— 青空文庫把「大人《おとな》」标成一个注音单元，
/// 分词器却可能切成「大」「人」。所以合并规则是：**注音单元不可拆**，
/// 词边界只在注音单元的边界上生效。宁可点击范围粗一点，也不能让注音断成两半。
public struct ReaderWord: Equatable, Sendable, Identifiable {
    public var id: Int
    /// 显示用的振假名片段。
    public var segments: [FuriganaSegment]
    /// 原文（去掉注音标记）。
    public var surface: String
    /// 假名读音。全是标点或拉丁字符时为 nil。
    public var reading: String?
    /// 所属句子的下标（段落内）。选中整句高亮时按它归组。
    public var sentenceIndex: Int

    /// 值得点开看的词。标点、空白、纯数字不算。
    public var isLookupable: Bool {
        surface.unicodeScalars.contains { Kana.isKanji($0) || Kana.isKana($0) }
    }

    public init(
        id: Int,
        segments: [FuriganaSegment],
        surface: String,
        reading: String?,
        sentenceIndex: Int = 0
    ) {
        self.id = id
        self.segments = segments
        self.surface = surface
        self.reading = reading
        self.sentenceIndex = sentenceIndex
    }
}

public enum ReaderText {

    /// 把一段带注音标记的文本切成可点击的词。
    ///
    /// - Parameter annotated: `{漢字|かんじ}` 格式的文本。没有注音标记的纯文本也接受。
    public static func words(
        annotated: String,
        tokenizer: JapaneseTokenizer = JapaneseTokenizer()
    ) -> [ReaderWord] {
        let segments = FuriganaParser.parse(annotated)
        guard !segments.isEmpty else { return [] }

        // 分词跑在去掉注音之后的纯文本上 —— 注音标记会把分词器搞乱。
        let plain = segments.map(\.base).joined()
        let tokens = tokenizer.tokenize(plain)

        // 词边界（以字符为单位的起始偏移）
        var boundaries = Set<Int>()
        var offset = 0
        for token in tokens {
            boundaries.insert(offset)
            offset += token.surface.count
        }

        // 句末位置（字符偏移）。词落在哪两个边界之间就属于哪一句。
        let sentenceEnds = SentenceSplitter.ranges(in: plain).map {
            plain.distance(from: plain.startIndex, to: $0.upperBound)
        }
        func sentence(at offset: Int) -> Int {
            for (index, end) in sentenceEnds.enumerated() where offset < end { return index }
            return max(0, sentenceEnds.count - 1)
        }

        var words: [ReaderWord] = []
        var current: [FuriganaSegment] = []
        var cursor = 0

        var currentStart = 0

        func flush() {
            guard !current.isEmpty else { return }
            let surface = current.map(\.base).joined()
            let reading = current.map(\.reading).joined()
            words.append(ReaderWord(
                id: words.count,
                segments: current,
                surface: surface,
                reading: reading.isEmpty || reading == surface && !Kana.containsKanji(surface) ? nil : reading,
                sentenceIndex: sentence(at: currentStart)
            ))
            current = []
        }

        for segment in segments {
            switch segment {
            case .ruby:
                // 注音单元是原子的：词边界落在它内部也不拆。
                if boundaries.contains(cursor) { flush() }
                if current.isEmpty { currentStart = cursor }
                current.append(segment)
                cursor += segment.base.count

            case .plain(let text):
                // 普通文本要逐字看，词边界可能落在段落内部 ——
                // 完全没有注音标记时整段就是一个 plain，不切的话整段会变成一个词。
                var buffer = ""
                for character in text {
                    if boundaries.contains(cursor) {
                        if !buffer.isEmpty {
                            current.append(.plain(buffer))
                            buffer = ""
                        }
                        flush()
                    }
                    if current.isEmpty && buffer.isEmpty { currentStart = cursor }
                    buffer.append(character)
                    cursor += 1
                }
                if !buffer.isEmpty { current.append(.plain(buffer)) }
            }
        }
        flush()

        return words
    }
}
