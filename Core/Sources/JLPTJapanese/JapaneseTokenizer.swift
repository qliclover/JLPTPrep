import Foundation

/// 分词结果的一段。整篇文本切出来的 token 首尾相接，拼回去必须等于原文 ——
/// 阅读器要靠这个位置信息做点词查义和高亮，丢一个字都会错位。
public struct JapaneseToken: Equatable, Sendable {
    /// 原文片段，原样保留（不做任何归一化）。
    public var surface: String
    /// 平假名读音。标点、空白、拉丁文等拿不到读音的片段为 nil。
    public var reading: String?
    /// 在原文中的 UTF-16 区间。
    public var utf16Range: Range<Int>

    public init(surface: String, reading: String?, utf16Range: Range<Int>) {
        self.surface = surface
        self.reading = reading
        self.utf16Range = utf16Range
    }

    public var isWord: Bool { reading != nil }
}

/// 日语分词。
///
/// 用系统的 `CFStringTokenizer` 而不是 MeCab：零依赖、离线、不用打包几十 MB 词典。
/// 代价是分词粒度和读音准确度不如 MeCab + IPAdic，尤其在人名地名和生僻复合词上。
/// 到底差多少不能靠猜 —— `FuriganaAccuracyTests` 拿手工标注的例句量了实际数字。
public struct JapaneseTokenizer: Sendable {
    public init() {}

    public func tokenize(_ text: String) -> [JapaneseToken] {
        guard !text.isEmpty else { return [] }

        let cfText = text as CFString
        let length = CFStringGetLength(cfText)
        let locale = Locale(identifier: "ja_JP") as CFLocale
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            cfText,
            CFRangeMake(0, length),
            kCFStringTokenizerUnitWordBoundary,
            locale
        ) else {
            return [gapToken(in: text, from: 0, to: length)].compactMap { $0 }
        }

        var tokens: [JapaneseToken] = []
        var cursor = 0

        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let start = range.location
            let end = range.location + range.length
            guard start >= cursor else { continue }

            // 分词器会跳过标点和空白，这些空隙要补回来，否则拼不回原文。
            if start > cursor, let gap = gapToken(in: text, from: cursor, to: start) {
                tokens.append(gap)
            }

            if let surface = substring(text, from: start, to: end) {
                let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                    tokenizer,
                    kCFStringTokenizerAttributeLatinTranscription
                ) as? String
                tokens.append(JapaneseToken(
                    surface: surface,
                    reading: latin.flatMap(Kana.hiragana(fromLatin:)).flatMap(validReading),
                    utf16Range: start..<end
                ))
            }
            cursor = end
        }

        if cursor < length, let tail = gapToken(in: text, from: cursor, to: length) {
            tokens.append(tail)
        }
        return tokens
    }

    /// 剔除假读音。
    ///
    /// 分词器对标点也会给出「转写」：`。` 的罗马字是 `.`，再过一道
    /// Latin→Hiragana 会变成半角的 `｡`，看着像有读音其实是垃圾。
    /// 判据是至少含一个平假名 —— 标点、数字、拉丁串都过不了这一关。
    private func validReading(_ reading: String) -> String? {
        reading.unicodeScalars.contains(where: Kana.isHiragana) ? reading : nil
    }

    private func gapToken(in text: String, from start: Int, to end: Int) -> JapaneseToken? {
        guard let surface = substring(text, from: start, to: end) else { return nil }
        return JapaneseToken(surface: surface, reading: nil, utf16Range: start..<end)
    }

    private func substring(_ text: String, from start: Int, to end: Int) -> String? {
        guard start < end,
              let lower = String.Index(String.Index(utf16Offset: start, in: text), within: text),
              let upper = String.Index(String.Index(utf16Offset: end, in: text), within: text),
              lower < upper
        else { return nil }
        return String(text[lower..<upper])
    }
}
