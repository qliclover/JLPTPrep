import Foundation
import JLPTCore

/// 出选择题。
///
/// 全部逻辑是纯函数 + 可注入的随机源，所以能对「干扰项质量」这种模糊的东西写断言。
public enum QuizGenerator {

    public static let choiceCount = 4

    /// 给一个词出一道题。造不出合格的题（比如干扰项不够）就返回 nil ——
    /// 宁可不出，也不能出一道三个选项明显不可能的送分题。
    public static func question<G: RandomNumberGenerator>(
        for word: QuizWord,
        type: QuestionType,
        pool: [QuizWord],
        using generator: inout G
    ) -> QuizQuestion? {
        switch type {
        case .kanjiReading: kanjiReading(word, pool: pool, using: &generator)
        case .kanaToKanji: kanaToKanji(word, pool: pool, using: &generator)
        case .wordToMeaning: wordToMeaning(word, pool: pool, using: &generator)
        case .meaningToWord: meaningToWord(word, pool: pool, using: &generator)
        case .contextFill: contextFill(word, pool: pool, using: &generator)
        }
    }

    /// 这个词能出哪些题型。
    public static func availableTypes(for word: QuizWord, pool: [QuizWord]) -> [QuestionType] {
        var types: [QuestionType] = []
        if word.hasKanjiForm {
            types.append(.kanjiReading)
            types.append(.kanaToKanji)
        }
        if !word.meaningZh.isEmpty {
            types.append(.wordToMeaning)
            types.append(.meaningToWord)
        }
        if let example = word.exampleJa, inflectedForm(of: word.expression, in: example) != nil {
            types.append(.contextFill)
        }
        return types.filter { type in
            // 同词性的备选够不够凑出干扰项
            switch type {
            case .kanjiReading: true   // 干扰项是造出来的，不依赖词库
            case .kanaToKanji, .wordToMeaning, .meaningToWord, .contextFill:
                samePartOfSpeech(as: word, in: pool).count >= choiceCount - 1
            }
        }
    }

    // MARK: - 汉字读音

    /// 干扰项靠音韵扰动生成，不从词库里找 —— 这样任何词都能出题，
    /// 而且干扰项和正确答案只差一个音，正是真题的做法。
    private static func kanjiReading<G: RandomNumberGenerator>(
        _ word: QuizWord,
        pool: [QuizWord],
        using generator: inout G
    ) -> QuizQuestion? {
        guard word.hasKanjiForm else { return nil }

        var wrong = KanaPerturbation.distractors(
            for: word.reading,
            count: choiceCount - 1,
            avoiding: [word.reading]
        )
        // 扰动造不够时（极短的词），拿同词性词的读音补齐
        if wrong.count < choiceCount - 1 {
            let fallback = samePartOfSpeech(as: word, in: pool)
                .map(\.reading)
                .filter { $0 != word.reading && !wrong.contains($0) }
            wrong += fallback.prefix(choiceCount - 1 - wrong.count)
        }
        guard wrong.count == choiceCount - 1 else { return nil }

        return assemble(
            slug: word.slug,
            type: .kanjiReading,
            prompt: word.expression,
            // 这里绝不能带振假名 —— 那等于把答案印在题面上
            promptFurigana: nil,
            correct: word.reading,
            wrong: wrong,
            explanation: "\(word.expression)（\(word.reading)）\(word.meaningZh)",
            using: &generator
        )
    }

    // MARK: - 假名书写

    private static func kanaToKanji<G: RandomNumberGenerator>(
        _ word: QuizWord,
        pool: [QuizWord],
        using generator: inout G
    ) -> QuizQuestion? {
        guard word.hasKanjiForm else { return nil }

        // 好的干扰项是「长得像的表记」：优先取字数相同、且共用汉字的词
        let others = pool.filter { $0.slug != word.slug && $0.hasKanjiForm }
        let ranked = others.sorted { lhs, rhs in
            score(lhs.expression, against: word.expression) > score(rhs.expression, against: word.expression)
        }
        let wrong = Array(ranked.prefix(choiceCount - 1).map(\.expression))
        guard wrong.count == choiceCount - 1 else { return nil }

        return assemble(
            slug: word.slug,
            type: .kanaToKanji,
            prompt: word.reading,
            promptFurigana: nil,
            correct: word.expression,
            wrong: wrong,
            explanation: "\(word.expression)（\(word.reading)）\(word.meaningZh)",
            using: &generator
        )
    }

    /// 两个表记有多「像」：共用汉字多、字数接近就算像。
    private static func score(_ candidate: String, against target: String) -> Int {
        let shared = Set(candidate).intersection(Set(target)).count
        let lengthPenalty = abs(candidate.count - target.count)
        return shared * 3 - lengthPenalty
    }

    // MARK: - 词义

    private static func wordToMeaning<G: RandomNumberGenerator>(
        _ word: QuizWord,
        pool: [QuizWord],
        using generator: inout G
    ) -> QuizQuestion? {
        let wrong = pick(choiceCount - 1, from: samePartOfSpeech(as: word, in: pool).map(\.meaningZh),
                         excluding: [word.meaningZh], using: &generator)
        guard wrong.count == choiceCount - 1 else { return nil }

        return assemble(
            slug: word.slug,
            type: .wordToMeaning,
            prompt: word.expression,
            promptFurigana: nil,
            correct: word.meaningZh,
            wrong: wrong,
            explanation: "\(word.expression)（\(word.reading)）",
            using: &generator
        )
    }

    private static func meaningToWord<G: RandomNumberGenerator>(
        _ word: QuizWord,
        pool: [QuizWord],
        using generator: inout G
    ) -> QuizQuestion? {
        let wrong = pick(choiceCount - 1, from: samePartOfSpeech(as: word, in: pool).map(\.expression),
                         excluding: [word.expression], using: &generator)
        guard wrong.count == choiceCount - 1 else { return nil }

        return assemble(
            slug: word.slug,
            type: .meaningToWord,
            prompt: word.meaningZh,
            promptFurigana: nil,
            correct: word.expression,
            wrong: wrong,
            explanation: "\(word.expression)（\(word.reading)）\(word.meaningZh)",
            using: &generator
        )
    }

    // MARK: - 语境选词

    private static func contextFill<G: RandomNumberGenerator>(
        _ word: QuizWord,
        pool: [QuizWord],
        using generator: inout G
    ) -> QuizQuestion? {
        guard let example = word.exampleJa,
              let surface = inflectedForm(of: word.expression, in: example)
        else { return nil }

        let wrong = pick(choiceCount - 1, from: samePartOfSpeech(as: word, in: pool).map(\.expression),
                         excluding: [word.expression], using: &generator)
        guard wrong.count == choiceCount - 1 else { return nil }

        let blanked = example.replacingOccurrences(of: surface, with: "（　　）")
        return assemble(
            slug: word.slug,
            type: .contextFill,
            prompt: blanked,
            promptFurigana: word.exampleFurigana.map {
                // 挖空的部分连带它的振假名一起去掉，否则答案还是露在题面上
                blankOut(surface, in: $0)
            },
            correct: word.expression,
            wrong: wrong,
            explanation: example,
            using: &generator
        )
    }

    /// 在句子里找出这个词实际出现的形态。
    ///
    /// 例句里的动词几乎都是活用形（`食べる` 写成 `食べます`），直接找原形是找不到的。
    /// 所以按分词切开，逐段还原回原形来比对 —— 复用已有的活用引擎。
    /// 一个活用形可能跨多个 token（`食べ` + `ます`），所以要试连续几段的组合。
    static func inflectedForm(
        of expression: String,
        in sentence: String,
        tokenizer: JapaneseTokenizer = JapaneseTokenizer()
    ) -> String? {
        // 原形本来就字面出现（名词、形容词常见）就直接用
        if sentence.contains(expression) { return expression }

        let tokens = tokenizer.tokenize(sentence)
        let maxSpan = 3

        for start in tokens.indices {
            var surface = ""
            for length in 1...maxSpan {
                guard start + length <= tokens.count else { break }
                surface += tokens[start + length - 1].surface
                guard surface.count >= 2 else { continue }
                if Deinflector.deinflect(surface, isDictionaryWord: { $0 == expression })
                    .contains(where: { $0.dictionaryForm == expression })
                {
                    return surface
                }
            }
        }
        return nil
    }

    /// 在振假名标注里把某个词整体换成空格。
    ///
    /// 先在纯文本上定位字符区间，再按区间重建 —— 不能只在段落边界上匹配，
    /// 因为要挖的活用形常常结束在某个段落中间（`{食|た}` + `べます。` 里的 `べます`）。
    /// 注音段落只要与区间有交集就整段丢掉：注音是不可分割的，切一半会渲染出乱七八糟的东西。
    static func blankOut(_ expression: String, in annotated: String) -> String {
        let segments = FuriganaParser.parse(annotated)
        let plain = segments.map(\.base).joined()
        guard let found = plain.range(of: expression) else { return annotated }

        let lower = plain.distance(from: plain.startIndex, to: found.lowerBound)
        let upper = plain.distance(from: plain.startIndex, to: found.upperBound)

        var result = ""
        var inserted = false
        var cursor = 0

        for segment in segments {
            let length = segment.base.count
            let start = cursor
            let end = cursor + length
            cursor = end

            // 完全在挖空区间之外
            if end <= lower || start >= upper {
                result += render(segment)
                continue
            }
            if !inserted {
                result += "（　　）"
                inserted = true
            }
            // 有交集：普通文字保留区间外的部分，注音段整段丢弃
            if case .plain(let text) = segment {
                let characters = Array(text)
                let head = String(characters[0..<max(0, min(length, lower - start))])
                let tail = String(characters[min(length, max(0, upper - start))...])
                result = String(result.dropLast("（　　）".count)) + head + "（　　）" + tail
            }
        }
        return result
    }

    private static func render(_ segment: FuriganaSegment) -> String {
        switch segment {
        case .plain(let text): text
        case .ruby(let base, let reading): "{\(base)|\(reading)}"
        }
    }

    // MARK: - 组装

    private static func assemble<G: RandomNumberGenerator>(
        slug: String,
        type: QuestionType,
        prompt: String,
        promptFurigana: String?,
        correct: String,
        wrong: [String],
        explanation: String?,
        using generator: inout G
    ) -> QuizQuestion? {
        // 选项里出现重复就等于送分（两个一样的选项必然都不是答案，或者都对）
        var seen = Set([correct])
        let unique = wrong.filter { seen.insert($0).inserted }
        guard unique.count == choiceCount - 1 else { return nil }

        var choices = unique + [correct]
        choices.shuffle(using: &generator)
        guard let answerIndex = choices.firstIndex(of: correct) else { return nil }

        return QuizQuestion(
            slug: slug,
            type: type,
            prompt: prompt,
            promptFurigana: promptFurigana,
            choices: choices,
            answerIndex: answerIndex,
            explanation: explanation
        )
    }

    private static func samePartOfSpeech(as word: QuizWord, in pool: [QuizWord]) -> [QuizWord] {
        let same = pool.filter { $0.slug != word.slug && $0.partOfSpeech == word.partOfSpeech }
        // 同词性的不够就放宽，总比出不了题强
        return same.count >= choiceCount - 1 ? same : pool.filter { $0.slug != word.slug }
    }

    private static func pick<G: RandomNumberGenerator>(
        _ count: Int,
        from candidates: [String],
        excluding: Set<String>,
        using generator: inout G
    ) -> [String] {
        var seen = excluding
        var pool = candidates.filter { seen.insert($0).inserted }
        pool.shuffle(using: &generator)
        return Array(pool.prefix(count))
    }
}
