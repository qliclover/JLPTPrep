import Foundation

/// 题型。对齐 JLPT 言語知識（文字·語彙）的真实题型，见 PRD §3。
public enum QuestionType: String, Codable, CaseIterable, Sendable {
    /// 汉字读音：给「食べる」，选「たべる」
    case kanjiReading
    /// 假名书写：给「たべる」，选「食べる」
    case kanaToKanji
    /// 词义理解：给「食べる」，选中文释义
    case wordToMeaning
    /// 中译日：给「吃」，选「食べる」
    case meaningToWord
    /// 语境选词：句子挖空，选填进去的词
    case contextFill

    public var labelZh: String {
        switch self {
        case .kanjiReading: "汉字读音"
        case .kanaToKanji: "假名书写"
        case .wordToMeaning: "词义"
        case .meaningToWord: "中译日"
        case .contextFill: "语境选词"
        }
    }

    /// 题干用日语呈现时，是否需要振假名。
    public var promptIsJapanese: Bool {
        switch self {
        case .kanjiReading, .wordToMeaning, .contextFill: true
        case .kanaToKanji, .meaningToWord: false
        }
    }
}

/// 一道生成好的选择题。
public struct QuizQuestion: Equatable, Sendable, Identifiable {
    public var id: String { "\(slug)-\(type.rawValue)" }
    /// 考的是哪个词。
    public var slug: String
    public var type: QuestionType
    /// 题干。
    public var prompt: String
    /// 题干的振假名标注（`kanjiReading` 题绝不能给，那等于把答案印在题面上）。
    public var promptFurigana: String?
    public var choices: [String]
    public var answerIndex: Int
    /// 答完之后显示的解析。
    public var explanation: String?

    public var answer: String { choices[answerIndex] }

    public init(
        slug: String,
        type: QuestionType,
        prompt: String,
        promptFurigana: String? = nil,
        choices: [String],
        answerIndex: Int,
        explanation: String? = nil
    ) {
        self.slug = slug
        self.type = type
        self.prompt = prompt
        self.promptFurigana = promptFurigana
        self.choices = choices
        self.answerIndex = answerIndex
        self.explanation = explanation
    }

    public func isCorrect(_ index: Int) -> Bool { index == answerIndex }
}

/// 出题需要的最小词条信息。刻意不依赖 SwiftData，方便单测。
public struct QuizWord: Equatable, Sendable {
    public var slug: String
    public var expression: String
    public var reading: String
    public var meaningZh: String
    public var partOfSpeech: String
    public var exampleJa: String?
    public var exampleFurigana: String?

    public init(
        slug: String,
        expression: String,
        reading: String,
        meaningZh: String,
        partOfSpeech: String,
        exampleJa: String? = nil,
        exampleFurigana: String? = nil
    ) {
        self.slug = slug
        self.expression = expression
        self.reading = reading
        self.meaningZh = meaningZh
        self.partOfSpeech = partOfSpeech
        self.exampleJa = exampleJa
        self.exampleFurigana = exampleFurigana
    }

    /// 表记里有汉字，才能出「汉字读音」和「假名书写」题。
    public var hasKanjiForm: Bool {
        expression != reading && expression.unicodeScalars.contains { scalar in
            let v = Int(scalar.value)
            return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
        }
    }
}
