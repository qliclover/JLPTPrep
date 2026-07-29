import XCTest
@testable import JLPTJapanese
import JLPTCore

final class ReaderTextTests: XCTestCase {

    private func words(_ annotated: String) -> [ReaderWord] {
        ReaderText.words(annotated: annotated)
    }

    // MARK: - 最重要的不变量：拼回去必须等于原文

    func testWordsReassembleIntoTheOriginalText() {
        let cases = [
            "{毎朝|まいあさ}コーヒーを{飲|の}みます。",
            "ちょっと{待|ま}ってください。",
            "普通の日本語です。",
            "ABC と 123 が混ざった文。",
            "",
        ]
        for annotated in cases {
            let plain = FuriganaParser.plainText(annotated)
            XCTAssertEqual(
                words(annotated).map(\.surface).joined(),
                plain,
                "「\(annotated)」切词后拼不回原文 —— 点击位置会全部错位"
            )
        }
    }

    func testAnnotationsSurviveWordSplitting() {
        let result = words("{毎朝|まいあさ}コーヒーを{飲|の}みます。")
        let rebuilt = result.flatMap(\.segments).map { segment -> String in
            switch segment {
            case .plain(let text): text
            case .ruby(let base, let reading): "{\(base)|\(reading)}"
            }
        }.joined()
        XCTAssertEqual(rebuilt, "{毎朝|まいあさ}コーヒーを{飲|の}みます。")
    }

    // MARK: - 注音单元不可拆

    /// 分词器会把「大人」切成「大」「人」，但注音是标在整个「大人」上的。
    /// 拆开会让振假名断成两半，必须保住。
    func testRubyUnitIsNeverSplitAcrossWords() {
        for word in words("{大人|おとな}になりました。") {
            for segment in word.segments {
                if case .ruby(let base, _) = segment {
                    XCTAssertTrue(
                        word.surface.contains(base),
                        "注音单元「\(base)」被拆到了不同的词里"
                    )
                }
            }
        }
        let combined = words("{大人|おとな}になりました。")
        XCTAssertTrue(
            combined.contains { $0.surface.contains("大人") },
            "「大人」应该整体留在一个词里"
        )
    }

    // MARK: - 可点击判定

    func testPunctuationIsNotLookupable() {
        let result = words("はい。ええ、そう！")
        let punctuation = result.filter { !$0.isLookupable }
        XCTAssertFalse(punctuation.isEmpty, "标点该被判为不可点")
        for word in punctuation {
            XCTAssertFalse(Kana.containsKanji(word.surface))
        }
    }

    func testJapaneseWordsAreLookupable() {
        let result = words("{学校|がっこう}へ{行|い}きます。")
        let lookupable = result.filter(\.isLookupable)
        XCTAssertTrue(lookupable.contains { $0.surface.contains("学校") })
        XCTAssertTrue(lookupable.contains { $0.surface.contains("行") })
    }

    func testLatinAndDigitsAreNotLookupable() {
        for word in words("ABC 123") {
            XCTAssertFalse(word.isLookupable, "「\(word.surface)」不该可点")
        }
    }

    // MARK: - 读音

    func testReadingIsAssembledFromAnnotations() {
        let result = words("{学校|がっこう}")
        XCTAssertEqual(result.first?.reading, "がっこう")
    }

    func testKanaOnlyWordHasNoSeparateReading() {
        let result = words("ちょっと")
        XCTAssertNil(result.first?.reading, "全是假名时读音和字面一样，不用重复显示")
    }

    // MARK: - 边界

    func testEmptyInput() {
        XCTAssertTrue(words("").isEmpty)
    }

    func testIDsAreUniqueAndOrdered() {
        let result = words("{毎朝|まいあさ}コーヒーを{飲|の}みます。")
        XCTAssertEqual(result.map(\.id), Array(0..<result.count))
    }

    func testUnannotatedTextStillSplitsIntoWords() {
        let result = words("学校へ行きます。")
        XCTAssertGreaterThan(result.count, 1, "没有注音标记也该按分词切开")
        XCTAssertEqual(result.map(\.surface).joined(), "学校へ行きます。")
    }
}

final class SentenceSplitterTests: XCTestCase {

    func testPlainSentences() {
        XCTAssertEqual(
            SentenceSplitter.sentences(in: "今日はいい天気です。明日も晴れます。"),
            ["今日はいい天気です。", "明日も晴れます。"]
        )
    }

    /// `「行こう。」` 整个才是一句 —— 不能在 `。` 处切开把收尾引号甩到下一句。
    func testClosingQuoteStaysWithItsSentence() {
        XCTAssertEqual(
            SentenceSplitter.sentences(in: "彼は「行こう。」と言った。"),
            ["彼は「行こう。」と言った。"]
        )
        XCTAssertEqual(
            SentenceSplitter.sentences(in: "「おはよう。」「こんにちは。」"),
            ["「おはよう。」", "「こんにちは。」"]
        )
    }

    func testConsecutiveTerminatorsAreOneBoundary() {
        XCTAssertEqual(SentenceSplitter.sentences(in: "本当に！？そうか。"), ["本当に！？", "そうか。"])
    }

    /// 标题、诗行这类没有句末标点的整段算一句。
    func testParagraphWithoutTerminatorIsOneSentence() {
        XCTAssertEqual(SentenceSplitter.sentences(in: "蜘蛛の糸"), ["蜘蛛の糸"])
    }

    func testTrailingFragmentIsKept() {
        XCTAssertEqual(
            SentenceSplitter.sentences(in: "一文目です。途中で終わ"),
            ["一文目です。", "途中で終わ"]
        )
    }

    func testSentencesReassembleIntoTheOriginal() {
        for text in [
            "ある日の事でございます。御釈迦様は極楽の蓮池のふちを、独りでぶらぶら御歩きになっていらっしゃいました。",
            "「待って。」と彼女は言った。それから走り出した。",
            "",
            "。。。",
        ] {
            XCTAssertEqual(SentenceSplitter.sentences(in: text).joined(), text, "「\(text)」拼不回原文")
        }
    }
}

final class ReaderSentenceIndexTests: XCTestCase {

    func testWordsCarryTheirSentenceIndex() {
        let words = ReaderText.words(annotated: "{今日|きょう}はいい{天気|てんき}です。{明日|あした}も{晴|は}れます。")
        let first = words.filter { $0.sentenceIndex == 0 }.map(\.surface).joined()
        let second = words.filter { $0.sentenceIndex == 1 }.map(\.surface).joined()

        XCTAssertEqual(first, "今日はいい天気です。")
        XCTAssertEqual(second, "明日も晴れます。")
    }

    func testSingleSentenceParagraphIsAllIndexZero() {
        let words = ReaderText.words(annotated: "{学校|がっこう}へ{行|い}きます。")
        XCTAssertTrue(words.allSatisfy { $0.sentenceIndex == 0 })
    }

    func testSentenceGroupingSurvivesRubyUnits() {
        // 注音单元不能被句子切分拆开
        let words = ReaderText.words(annotated: "{大人|おとな}です。{子供|こども}です。")
        for word in words {
            for segment in word.segments {
                if case .ruby(let base, _) = segment {
                    XCTAssertTrue(word.surface.contains(base))
                }
            }
        }
        XCTAssertEqual(Set(words.map(\.sentenceIndex)).count, 2)
    }
}
