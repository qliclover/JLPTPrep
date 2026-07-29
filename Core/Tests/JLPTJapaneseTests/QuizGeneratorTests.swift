import XCTest
@testable import JLPTJapanese
import JLPTCore

/// 固定种子的随机源，让「随机打乱选项」也能写确定性断言。
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64 = 0x1234_5678) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

final class KanaPerturbationTests: XCTestCase {

    func testVoicingDistractors() {
        let candidates = KanaPerturbation.candidates(for: "がっこう", kind: .voicing)
        XCTAssertTrue(candidates.contains("かっこう"), "が → か 是最典型的干扰项")
    }

    func testGeminationDistractors() {
        // 促音有无是 N5 的常考点
        XCTAssertTrue(KanaPerturbation.candidates(for: "がっこう", kind: .gemination).contains("がこう"))
        XCTAssertTrue(KanaPerturbation.candidates(for: "がこう", kind: .gemination).contains("がっこう"))
    }

    func testLongVowelDistractors() {
        XCTAssertTrue(KanaPerturbation.candidates(for: "がっこう", kind: .longVowel).contains("がっこ"))
        XCTAssertTrue(KanaPerturbation.candidates(for: "せんせい", kind: .longVowel).contains("せんせ"))
    }

    func testVowelShiftStaysInTheSameConsonantRow() {
        let candidates = KanaPerturbation.candidates(for: "たべる", kind: .vowelShift)
        XCTAssertTrue(candidates.contains("たべら"), "る → ら，同辅音不同元音")
        XCTAssertFalse(candidates.contains("たべく"), "不该跨行")
    }

    // MARK: - 干扰项的硬性要求

    func testDistractorsAreNeverEqualToTheAnswer() {
        for reading in ["たべる", "がっこう", "せんせい", "みず", "ちょっと", "あ"] {
            let distractors = KanaPerturbation.distractors(for: reading, count: 3)
            XCTAssertFalse(distractors.contains(reading), "「\(reading)」的干扰项里混进了正确答案")
            XCTAssertEqual(Set(distractors).count, distractors.count, "干扰项之间不能重复")
        }
    }

    func testAvoidedReadingsAreExcluded() {
        let distractors = KanaPerturbation.distractors(
            for: "がっこう", count: 3, avoiding: ["かっこう", "がこう"]
        )
        XCTAssertFalse(distractors.contains("かっこう"))
        XCTAssertFalse(distractors.contains("がこう"))
        XCTAssertEqual(distractors.count, 3, "排除了两个还要能凑够三个")
    }

    func testCommonWordsCanAlwaysProduceThreeDistractors() {
        let readings = [
            "たべる", "のむ", "みる", "きく", "いく", "くる", "かえる", "はなす", "よむ", "かく",
            "がっこう", "せんせい", "がくせい", "ともだち", "かぞく", "なまえ", "じかん", "でんしゃ",
            "おおきい", "ちいさい", "あたらしい", "たかい", "やすい", "げんき", "しずか", "べんり",
        ]
        for reading in readings {
            let distractors = KanaPerturbation.distractors(for: reading, count: 3)
            XCTAssertEqual(distractors.count, 3, "「\(reading)」造不出三个干扰项")
        }
    }

    func testSingleCharacterReadingStillWorks() {
        // 极短的词可造的扰动少，但不该崩
        XCTAssertNoThrow(KanaPerturbation.distractors(for: "き", count: 3))
    }

    func testEmptyInput() {
        XCTAssertTrue(KanaPerturbation.distractors(for: "", count: 3).isEmpty)
        XCTAssertTrue(KanaPerturbation.distractors(for: "たべる", count: 0).isEmpty)
    }
}

final class QuizGeneratorTests: XCTestCase {

    private let pool: [QuizWord] = [
        QuizWord(slug: "taberu", expression: "食べる", reading: "たべる", meaningZh: "吃",
                 partOfSpeech: "动词·二类", exampleJa: "朝ご飯にパンを食べます。",
                 exampleFurigana: "{朝|あさ}ご{飯|はん}にパンを{食|た}べます。"),
        QuizWord(slug: "nomu", expression: "飲む", reading: "のむ", meaningZh: "喝", partOfSpeech: "动词·一类"),
        QuizWord(slug: "miru", expression: "見る", reading: "みる", meaningZh: "看", partOfSpeech: "动词·二类"),
        QuizWord(slug: "kiku", expression: "聞く", reading: "きく", meaningZh: "听", partOfSpeech: "动词·一类"),
        QuizWord(slug: "iku", expression: "行く", reading: "いく", meaningZh: "去", partOfSpeech: "动词·一类"),
        QuizWord(slug: "kaku", expression: "書く", reading: "かく", meaningZh: "写", partOfSpeech: "动词·一类"),
        QuizWord(slug: "gakkou", expression: "学校", reading: "がっこう", meaningZh: "学校", partOfSpeech: "名词"),
        QuizWord(slug: "sensei", expression: "先生", reading: "せんせい", meaningZh: "老师", partOfSpeech: "名词"),
        QuizWord(slug: "gakusei", expression: "学生", reading: "がくせい", meaningZh: "学生", partOfSpeech: "名词"),
        QuizWord(slug: "kaisha", expression: "会社", reading: "かいしゃ", meaningZh: "公司", partOfSpeech: "名词"),
        QuizWord(slug: "chotto", expression: "ちょっと", reading: "ちょっと", meaningZh: "稍微", partOfSpeech: "副词"),
    ]

    private func word(_ slug: String) -> QuizWord {
        pool.first { $0.slug == slug }!
    }

    private func make(_ slug: String, _ type: QuestionType, seed: UInt64 = 42) -> QuizQuestion? {
        var rng = SeededRNG(seed: seed)
        return QuizGenerator.question(for: word(slug), type: type, pool: pool, using: &rng)
    }

    // MARK: - 每种题型都成立

    func testKanjiReadingQuestion() throws {
        let question = try XCTUnwrap(make("gakkou", .kanjiReading))
        XCTAssertEqual(question.prompt, "学校")
        XCTAssertEqual(question.answer, "がっこう")
        XCTAssertEqual(question.choices.count, 4)
        XCTAssertNil(question.promptFurigana, "汉字读音题绝不能给振假名，那等于印上答案")
    }

    func testKanaToKanjiQuestion() throws {
        let question = try XCTUnwrap(make("gakkou", .kanaToKanji))
        XCTAssertEqual(question.prompt, "がっこう")
        XCTAssertEqual(question.answer, "学校")
        XCTAssertTrue(question.choices.allSatisfy { $0 != "がっこう" }, "选项该是表记不是读音")
    }

    func testMeaningQuestions() throws {
        let toMeaning = try XCTUnwrap(make("taberu", .wordToMeaning))
        XCTAssertEqual(toMeaning.prompt, "食べる")
        XCTAssertEqual(toMeaning.answer, "吃")

        let toWord = try XCTUnwrap(make("taberu", .meaningToWord))
        XCTAssertEqual(toWord.prompt, "吃")
        XCTAssertEqual(toWord.answer, "食べる")
    }

    func testContextFillBlanksOutTheWord() throws {
        let question = try XCTUnwrap(make("taberu", .contextFill))
        // 例句里是活用形「食べます」，整段挖掉，而不是只挖原形
        XCTAssertEqual(question.prompt, "朝ご飯にパンを（　　）。")
        XCTAssertEqual(question.answer, "食べる")
        XCTAssertFalse(question.prompt.contains("食べる"), "答案不能留在题干里")
    }

    /// 挖空时必须连它的振假名一起挖掉，否则注音会把答案暴露出来。
    func testContextFillRemovesFuriganaOfTheAnswer() throws {
        let question = try XCTUnwrap(make("taberu", .contextFill))
        let furigana = try XCTUnwrap(question.promptFurigana)
        XCTAssertFalse(furigana.contains("{食|た}"), "答案的振假名还留在题面上")
        XCTAssertTrue(furigana.contains("（　　）"))
        XCTAssertTrue(furigana.contains("{朝|あさ}"), "其他词的振假名要保留")
    }

    // MARK: - 所有题型共有的硬性要求

    func testEveryQuestionIsWellFormed() {
        var rng = SeededRNG()
        for word in pool {
            for type in QuizGenerator.availableTypes(for: word, pool: pool) {
                guard let question = QuizGenerator.question(for: word, type: type, pool: pool, using: &rng) else {
                    XCTFail("「\(word.expression)」的 \(type.labelZh) 题没造出来")
                    continue
                }
                XCTAssertEqual(question.choices.count, 4, "\(word.expression)/\(type.labelZh)")
                XCTAssertEqual(Set(question.choices).count, 4, "\(word.expression)/\(type.labelZh) 选项重复了")
                XCTAssertTrue(question.choices.indices.contains(question.answerIndex))
                XCTAssertFalse(question.prompt.isEmpty)
                XCTAssertFalse(question.answer.isEmpty)
            }
        }
    }

    func testAnswerPositionIsNotAlwaysTheSame() {
        // 答案总在同一个位置，学习者会靠位置蒙
        var positions = Set<Int>()
        for seed in UInt64(1)...30 {
            if let question = make("gakkou", .kanjiReading, seed: seed) {
                positions.insert(question.answerIndex)
            }
        }
        XCTAssertGreaterThan(positions.count, 2, "答案位置分布太集中")
    }

    func testGenerationIsDeterministicForTheSameSeed() {
        XCTAssertEqual(make("gakkou", .kanjiReading, seed: 7), make("gakkou", .kanjiReading, seed: 7))
    }

    // MARK: - 造不出好题就不造

    func testKanaOnlyWordCannotProduceKanjiQuestions() {
        let types = QuizGenerator.availableTypes(for: word("chotto"), pool: pool)
        XCTAssertFalse(types.contains(.kanjiReading), "「ちょっと」没有汉字表记，出不了读音题")
        XCTAssertFalse(types.contains(.kanaToKanji))
        XCTAssertTrue(types.contains(.wordToMeaning), "但词义题照样能出")
    }

    func testTinyPoolCannotProduceMeaningQuestions() {
        let tiny = [pool[0], pool[1]]
        var rng = SeededRNG()
        // 只有两个词，凑不出三个干扰项，宁可不出题
        XCTAssertNil(QuizGenerator.question(for: tiny[0], type: .wordToMeaning, pool: tiny, using: &rng))
    }

    func testWordWithoutExampleCannotProduceContextFill() {
        XCTAssertFalse(QuizGenerator.availableTypes(for: word("nomu"), pool: pool).contains(.contextFill))
    }
}
