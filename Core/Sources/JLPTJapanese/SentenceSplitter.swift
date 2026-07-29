import Foundation

/// 把一段日文切成句子。
///
/// 用来做「选中一句 → 翻译」。看着简单，但有几个坑：
/// - 句末标点后面常跟着收尾的引号：`「行こう。」` 整个才是一句，不能在 `。` 处切开
/// - 省略号 `……` 由两个字符组成，不能当成两个句子边界
/// - 段落可能整段没有句末标点（诗歌、标题），这时整段算一句
public enum SentenceSplitter {

    /// 句末标点。
    private static let terminators: Set<Character> = ["。", "！", "？", "!", "?", "．", "."]

    /// 跟在句末标点后面、仍属于同一句的收尾字符。
    private static let closers: Set<Character> = [
        "」", "』", "）", ")", "”", "’", "〉", "》", "】", "〕", "］", "｝",
    ]

    /// 开引号 / 开括号。
    private static let openers: Set<Character> = [
        "「", "『", "（", "(", "“", "‘", "〈", "《", "【", "〔", "［", "｛",
    ]

    /// 切出每句在原字符串里的区间。区间首尾相接，拼起来等于原文。
    ///
    /// 引号里的句号**不算句末**：`彼は「行こう。」と言った。` 是一句，不是两句。
    /// 但独立成句的引文又该断开：`「おはよう。」「こんにちは。」` 是两句。
    /// 区分办法是等到引号闭合、且后面接的是另一个引号或段尾时才断
    /// —— 后面跟着 `と言った` 这类续写就不断。
    ///
    /// 这是启发式，不是语法分析。日文没有可靠的句子边界规则，
    /// 这套规则覆盖小说里的绝大多数写法，但不保证每种排版都对。
    public static func ranges(in text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }

        var result: [Range<String.Index>] = []
        var start = text.startIndex
        var index = text.startIndex
        var depth = 0
        /// 刚闭合的引号里以句末标点收尾 —— 是否成句要看后面接什么。
        var quotedSentenceJustClosed = false

        while index < text.endIndex {
            let character = text[index]

            if openers.contains(character) {
                // 上一段引文后面又起了引号，说明它自成一句
                if quotedSentenceJustClosed {
                    result.append(start..<index)
                    start = index
                    quotedSentenceJustClosed = false
                }
                depth += 1
                index = text.index(after: index)
                continue
            }

            if closers.contains(character) {
                let previous = index > text.startIndex ? text[text.index(before: index)] : " "
                depth = max(0, depth - 1)
                index = text.index(after: index)
                if depth == 0, terminators.contains(previous) {
                    quotedSentenceJustClosed = true
                }
                continue
            }

            index = text.index(after: index)

            guard terminators.contains(character), depth == 0 else {
                // 引号闭合后接了别的内容，说明句子还在继续
                if !character.isWhitespace { quotedSentenceJustClosed = false }
                continue
            }

            // 连续的句末标点算一组（`！？` `……` 这类）
            while index < text.endIndex, terminators.contains(text[index]) {
                index = text.index(after: index)
            }
            // 把收尾引号并进来
            while index < text.endIndex, closers.contains(text[index]) {
                index = text.index(after: index)
            }

            result.append(start..<index)
            start = index
            quotedSentenceJustClosed = false
        }

        // 段尾没有句末标点的残句（标题、诗行）也是一句
        if start < text.endIndex {
            result.append(start..<text.endIndex)
        }
        return result
    }

    public static func sentences(in text: String) -> [String] {
        ranges(in: text).map { String(text[$0]) }
    }
}
