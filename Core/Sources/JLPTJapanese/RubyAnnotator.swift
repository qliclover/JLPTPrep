import Foundation
import JLPTCore

/// 把分词结果转成 `{漢字|かんじ}` 标注，直接喂给现有的 `RubyText` 渲染。
///
/// 难点全在**送假名对齐**：`食べる` 的读音是「たべる」，但注音只能给汉字部分，
/// 必须标成 `{食|た}べる`。整词标成 `{食べる|たべる}` 会让「べる」的注音浮在假名上面，
/// 既丑又会让人误以为「べ」也是汉字的一部分。
public enum RubyAnnotator {
    /// 整段文本加注音。
    ///
    /// - Parameter overrides: 读音覆盖表，优先于分词器的判断。它还会把被拆散的
    ///   复合词合并回去（土曜 + 日 → 土曜日），所以必须在这一层处理，
    ///   不能只在单个 token 上做替换。
    public static func annotate(
        _ text: String,
        using tokenizer: JapaneseTokenizer = JapaneseTokenizer(),
        overrides: ReadingOverrides = .common
    ) -> String {
        let tokens = tokenizer.tokenize(text)
        var result = ""
        var index = 0

        while index < tokens.count {
            if let match = overrides.longestMatch(in: tokens, at: index) {
                let surface = tokens[index..<(index + match.length)].map(\.surface).joined()
                result += annotate(token: JapaneseToken(
                    surface: surface,
                    reading: match.reading,
                    utf16Range: tokens[index].utf16Range.lowerBound..<tokens[index + match.length - 1].utf16Range.upperBound
                ))
                index += match.length
            } else {
                result += annotate(token: tokens[index])
                index += 1
            }
        }
        return result
    }

    public static func annotate(token: JapaneseToken) -> String {
        guard let reading = token.reading, Kana.containsKanji(token.surface) else {
            return token.surface
        }
        // 对不齐就整词标注 —— 注音位置不完美，但读音信息不丢，
        // 总好过直接放弃或者胡乱切分。
        return align(surface: token.surface, reading: reading)
            ?? "{\(token.surface)|\(Kana.toHiragana(reading))}"
    }

    /// 按汉字段 / 假名段交替切分，用假名段在读音里定位，反推每段汉字的读音。
    ///
    /// 返回 nil 表示对不齐（读音和字面根本不匹配，多半是分词器读错了）。
    static func align(surface: String, reading: String) -> String? {
        let runs = runs(of: surface)
        guard runs.contains(where: \.isKanji) else { return surface }

        var result = ""
        var rest = Substring(Kana.toHiragana(reading))
        var index = 0

        while index < runs.count {
            let run = runs[index]

            if !run.isKanji {
                // 假名段必须原样出现在读音开头，否则说明读音是错的。
                let normalized = Kana.toHiragana(run.text)
                guard rest.hasPrefix(normalized) else { return nil }
                rest = rest.dropFirst(normalized.count)
                result += run.text
                index += 1
                continue
            }

            if index + 1 < runs.count {
                // 用下一个假名段当锚点：它在读音里第一次出现的位置之前，就是这段汉字的读音。
                // 从偏移 1 开始找，因为汉字至少要念一个音。
                let anchor = Kana.toHiragana(runs[index + 1].text)
                guard let found = firstRange(of: anchor, in: rest, skippingFirst: 1) else { return nil }
                let kanjiReading = rest[rest.startIndex..<found.lowerBound]
                result += "{\(run.text)|\(kanjiReading)}"
                rest = rest[found.lowerBound...]
            } else {
                // 末尾的汉字段吃掉剩下全部读音。
                guard !rest.isEmpty else { return nil }
                result += "{\(run.text)|\(rest)}"
                rest = rest[rest.endIndex...]
            }
            index += 1
        }

        // 读音必须正好用完；有剩说明对齐是错的。
        guard rest.isEmpty else { return nil }
        return result
    }

    // MARK: - 切分

    struct Run: Equatable {
        var text: String
        var isKanji: Bool
    }

    static func runs(of surface: String) -> [Run] {
        var runs: [Run] = []
        for character in surface {
            let isKanji = character.unicodeScalars.contains(where: Kana.isKanji)
            if var last = runs.last, last.isKanji == isKanji {
                last.text.append(character)
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(text: String(character), isKanji: isKanji))
            }
        }
        return runs
    }

    private static func firstRange(
        of needle: String,
        in haystack: Substring,
        skippingFirst offset: Int
    ) -> Range<Substring.Index>? {
        guard !needle.isEmpty, haystack.count > offset else { return nil }
        let start = haystack.index(haystack.startIndex, offsetBy: offset)
        return haystack.range(of: needle, range: start..<haystack.endIndex)
    }
}
