import XCTest
@testable import JLPTJapanese

final class KanaTests: XCTestCase {

    func testCharacterClassification() {
        XCTAssertTrue(Kana.isKanji("食".unicodeScalars.first!))
        XCTAssertTrue(Kana.isKanji("々".unicodeScalars.first!), "叠字符要算汉字，「時々」得整体注音")
        XCTAssertFalse(Kana.isKanji("た".unicodeScalars.first!))
        XCTAssertFalse(Kana.isKanji("ア".unicodeScalars.first!))
        XCTAssertFalse(Kana.isKanji("A".unicodeScalars.first!))

        XCTAssertTrue(Kana.isHiragana("ぁ".unicodeScalars.first!))
        XCTAssertTrue(Kana.isKatakana("ヴ".unicodeScalars.first!))
        XCTAssertTrue(Kana.containsKanji("食べる"))
        XCTAssertFalse(Kana.containsKanji("たべる"))
        XCTAssertFalse(Kana.containsKanji("コーヒー"))
    }

    func testKatakanaToHiragana() {
        XCTAssertEqual(Kana.toHiragana("カタカナ"), "かたかな")
        XCTAssertEqual(Kana.toHiragana("コーヒー"), "こーひー", "长音符原样保留")
        XCTAssertEqual(Kana.toHiragana("ひらがな"), "ひらがな")
        XCTAssertEqual(Kana.toHiragana("パーティー"), "ぱーてぃー")
        XCTAssertEqual(Kana.toHiragana("漢字とカナ"), "漢字とかな", "汉字不动")
    }

    func testLatinToHiragana() {
        XCTAssertEqual(Kana.hiragana(fromLatin: "tabemasu"), "たべます")
        XCTAssertEqual(Kana.hiragana(fromLatin: "gakkou"), "がっこう")
        XCTAssertNil(Kana.hiragana(fromLatin: ""))
    }
}

final class JapaneseTokenizerTests: XCTestCase {
    let tokenizer = JapaneseTokenizer()

    func testTokensReassembleIntoTheOriginalText() {
        for text in [
            "毎朝コーヒーを飲みます。",
            "ねえ、ちょっと待って！",
            "ABC と 123 が混ざった文",
            "",
            "。",
            "   ",
        ] {
            XCTAssertEqual(tokenizer.tokenize(text).map(\.surface).joined(), text, "「\(text)」拼不回去")
        }
    }

    func testRangesAreContiguousAndCoverEverything() {
        let text = "毎朝コーヒーを飲みます。"
        let tokens = tokenizer.tokenize(text)
        XCTAssertFalse(tokens.isEmpty)
        XCTAssertEqual(tokens.first?.utf16Range.lowerBound, 0)
        XCTAssertEqual(tokens.last?.utf16Range.upperBound, text.utf16.count)
        for (a, b) in zip(tokens, tokens.dropFirst()) {
            XCTAssertEqual(a.utf16Range.upperBound, b.utf16Range.lowerBound, "区间必须首尾相接")
        }
    }

    func testPunctuationHasNoReading() {
        let tokens = tokenizer.tokenize("はい。")
        XCTAssertEqual(tokens.last?.surface, "。")
        XCTAssertNil(tokens.last?.reading)
        XCTAssertFalse(tokens.last?.isWord ?? true)
    }

    func testWordsGetHiraganaReadings() {
        let tokens = tokenizer.tokenize("学校へ行きます。")
        let readings = tokens.compactMap(\.reading).joined()
        XCTAssertFalse(readings.isEmpty)
        XCTAssertFalse(Kana.containsKanji(readings), "读音里不该有汉字")
    }
}

final class RubyAlignmentTests: XCTestCase {

    private func align(_ surface: String, _ reading: String) -> String? {
        RubyAnnotator.align(surface: surface, reading: reading)
    }

    // MARK: - 送假名对齐，这是整个标注的核心

    func testOkuriganaStaysOutsideTheAnnotation() {
        XCTAssertEqual(align("食べる", "たべる"), "{食|た}べる")
        XCTAssertEqual(align("飲みます", "のみます"), "{飲|の}みます")
        XCTAssertEqual(align("新しい", "あたらしい"), "{新|あたら}しい")
    }

    func testLeadingKanaStaysOutside() {
        XCTAssertEqual(align("お名前", "おなまえ"), "お{名前|なまえ}")
        XCTAssertEqual(align("ご飯", "ごはん"), "ご{飯|はん}")
    }

    func testKanaSandwichedBetweenKanji() {
        XCTAssertEqual(align("取り引き", "とりひき"), "{取|と}り{引|ひ}き")
        XCTAssertEqual(align("申し込む", "もうしこむ"), "{申|もう}し{込|こ}む")
    }

    func testPureKanjiWordGetsOneAnnotation() {
        XCTAssertEqual(align("学校", "がっこう"), "{学校|がっこう}")
        XCTAssertEqual(align("日本語", "にほんご"), "{日本語|にほんご}")
    }

    func testNoKanjiMeansNoAnnotation() {
        XCTAssertEqual(align("ちょっと", "ちょっと"), "ちょっと")
        XCTAssertEqual(align("コーヒー", "こーひー"), "コーヒー")
    }

    func testKatakanaInSurfaceIsNormalizedForMatching() {
        // 表记里的片假名要和平假名读音对得上
        XCTAssertEqual(align("食パン", "しょくぱん"), "{食|しょく}パン")
    }

    // MARK: - 对不齐要返回 nil，让上层走整词标注的兜底

    func testMismatchedReadingIsRejected() {
        XCTAssertNil(align("食べる", "のむ"), "读音和字面完全不匹配")
        XCTAssertNil(align("食べる", "た"), "读音不够长，覆盖不了送假名")
        XCTAssertNil(align("お名前", "なまえ"), "开头的假名对不上")
        XCTAssertNil(align("食べる", "たべるよ"), "读音有富余")
    }

    func testWholeTokenFallbackWhenAlignmentFails() {
        let token = JapaneseToken(surface: "食べる", reading: "のむ", utf16Range: 0..<3)
        XCTAssertEqual(RubyAnnotator.annotate(token: token), "{食べる|のむ}", "对不齐也不能丢读音")
    }

    func testTokenWithoutReadingIsLeftAlone() {
        let token = JapaneseToken(surface: "。", reading: nil, utf16Range: 0..<1)
        XCTAssertEqual(RubyAnnotator.annotate(token: token), "。")
    }

    // MARK: - 切分

    func testRunSplitting() {
        XCTAssertEqual(
            RubyAnnotator.runs(of: "取り引き"),
            [
                .init(text: "取", isKanji: true),
                .init(text: "り", isKanji: false),
                .init(text: "引", isKanji: true),
                .init(text: "き", isKanji: false),
            ]
        )
        XCTAssertEqual(RubyAnnotator.runs(of: "学校"), [.init(text: "学校", isKanji: true)])
        XCTAssertEqual(RubyAnnotator.runs(of: ""), [])
    }
}

final class ReadingOverridesTests: XCTestCase {

    func testOverrideBeatsTheTokenizer() {
        let text = "日本語を勉強します。"
        let bare = RubyAnnotator.annotate(text, overrides: ReadingOverrides())
        let fixed = RubyAnnotator.annotate(text, overrides: .common)

        XCTAssertTrue(bare.contains("にっぽん"), "裸分词器会读成 にっぽん —— 这正是覆盖表要修的")
        XCTAssertTrue(fixed.contains("にほんご"))
        XCTAssertFalse(fixed.contains("にっぽん"))
    }

    /// 覆盖表最重要的能力：把分词器拆散的复合词合并回来。
    /// 土曜日 被切成 土曜 + 日，「日」单独读作 ひ，连浊就丢了。
    func testOverrideMergesSplitCompounds() {
        let fixed = RubyAnnotator.annotate("土曜日に掃除します。", overrides: .common)
        XCTAssertTrue(fixed.contains("{土曜日|どようび}"))
        XCTAssertFalse(fixed.contains("ようひ"))
    }

    func testLongestMatchWins() {
        let overrides = ReadingOverrides(["日本": "にほん", "日本語": "にほんご"])
        let annotated = RubyAnnotator.annotate("日本語", overrides: overrides)
        XCTAssertEqual(annotated, "{日本語|にほんご}", "该匹配更长的词条")
    }

    func testOverridesNeverLoseText() {
        let texts = ["土曜日と日曜日", "私は日本人です。", "四人で九時に会います。"]
        for text in texts {
            let annotated = RubyAnnotator.annotate(text, overrides: .common)
            XCTAssertEqual(
                annotated.replacingOccurrences(of: #"\{([^|]+)\|[^}]+\}"#, with: "$1", options: .regularExpression),
                text,
                "「\(text)」在合并 token 时丢字了"
            )
        }
    }

    func testEmptyOverridesAreANoOp() {
        let text = "毎朝コーヒーを飲みます。"
        XCTAssertEqual(
            RubyAnnotator.annotate(text, overrides: ReadingOverrides()),
            RubyAnnotator.annotate(text, using: JapaneseTokenizer(), overrides: ReadingOverrides())
        )
        XCTAssertTrue(ReadingOverrides().isEmpty)
    }

    func testCommonTableIsNotAccidentallyEmpty() {
        XCTAssertGreaterThan(ReadingOverrides.common.count, 30)
        XCTAssertEqual(ReadingOverrides.common.reading(for: "明日"), "あした")
        XCTAssertNil(ReadingOverrides.common.reading(for: "食べる"), "常规词不该进覆盖表")
    }
}

final class VerticalGlyphTests: XCTestCase {

    func testKanjiAndKanaStayUpright() {
        // CJK 本来就是直立的，什么都不该做
        for character in "食べる漢字ひらがなカタカナ" {
            XCTAssertEqual(VerticalGlyph.placement(for: character), .upright, "「\(character)」不该被动")
        }
    }

    func testExtendersAndBracketsRotate() {
        // 长音符不旋转的话会横躺在字中间
        for character in "ー〜―…（）「」『』【】" {
            XCTAssertEqual(
                VerticalGlyph.placement(for: character).rotation, 90,
                "「\(character)」在竖排里该旋转 90°"
            )
            XCTAssertTrue(VerticalGlyph.needsRotation(character))
        }
    }

    func testPunctuationMovesToTheUpperRight() {
        for character in "、。，．" {
            let placement = VerticalGlyph.placement(for: character)
            XCTAssertEqual(placement.rotation, 0, "句读点是挪位不是旋转")
            XCTAssertGreaterThan(placement.offsetX, 0, "「\(character)」该往右挪")
            XCTAssertLessThan(placement.offsetY, 0, "「\(character)」该往上挪")
        }
    }

    func testSmallKanaShiftLessThanPunctuation() {
        let small = VerticalGlyph.placement(for: "っ")
        let punctuation = VerticalGlyph.placement(for: "、")
        XCTAssertGreaterThan(small.offsetX, 0)
        XCTAssertLessThan(small.offsetX, punctuation.offsetX, "小书き假名的偏移该比句读点小")
    }

    func testLatinIsLeftAlone() {
        // 拉丁字母在竖排里的处理各家不一，这里不动它，交给字体
        XCTAssertEqual(VerticalGlyph.placement(for: "A"), .upright)
        XCTAssertEqual(VerticalGlyph.placement(for: "1"), .upright)
    }
}

final class TateChuYokoTests: XCTestCase {

    func testShortDigitRunsStayUpright() {
        // 两位以内横着塞进一个字格，保持直立
        XCTAssertEqual(
            TateChuYoko.runs(in: "12月"),
            [.init(text: "12", mode: .upright), .init(text: "月", mode: .japanese)]
        )
    }

    func testLongRunsRotate() {
        // 四位数整组旋转，读的时候侧头 —— 拆成四个直立数字会像密码
        XCTAssertEqual(
            TateChuYoko.runs(in: "2026年"),
            [.init(text: "2026", mode: .rotated), .init(text: "年", mode: .japanese)]
        )
    }

    func testJapaneseIsUntouched() {
        XCTAssertEqual(
            TateChuYoko.runs(in: "日本語"),
            [
                .init(text: "日", mode: .japanese),
                .init(text: "本", mode: .japanese),
                .init(text: "語", mode: .japanese),
            ]
        )
    }

    func testMixedText() {
        let runs = TateChuYoko.runs(in: "第3章とABCDE")
        XCTAssertEqual(runs.map(\.text), ["第", "3", "章", "と", "ABCDE"])
        XCTAssertEqual(runs.map(\.mode), [.japanese, .upright, .japanese, .japanese, .rotated])
    }

    func testRunsReassembleIntoTheOriginal() {
        for text in ["2026年12月にJLPTのN4を受ける。", "", "ABC", "あ1い2う3"] {
            XCTAssertEqual(TateChuYoko.runs(in: text).map(\.text).joined(), text, "「\(text)」拼不回去")
        }
    }

    func testFullWidthDigitsAreNotGrouped() {
        // 全角数字本来就是直立占一格的日文字符，不该被当成拉丁串
        XCTAssertEqual(TateChuYoko.runs(in: "１２").map(\.mode), [.japanese, .japanese])
    }
}

final class LineBreakRulesTests: XCTestCase {

    func testPunctuationCannotStartAColumn() {
        for character in "、。」』）！？ーっゃ" {
            XCTAssertFalse(LineBreakRules.canStartColumn(character), "「\(character)」不该出现在列首")
        }
        XCTAssertTrue(LineBreakRules.canStartColumn("日"))
    }

    func testOpeningBracketsCannotEndAColumn() {
        for character in "「『（【" {
            XCTAssertFalse(LineBreakRules.canEndColumn(character), "「\(character)」不该出现在列尾")
        }
        XCTAssertTrue(LineBreakRules.canEndColumn("日"))
    }

    /// 断点落在句号前面时要往前退，把句号留在上一列。
    func testBreakShiftsBackToKeepPunctuationInPlace() {
        let characters = Array("あいうえお。かきくけこ")
        // 想在下标 5（也就是「。」）前断 —— 那会让「。」变成下一列的开头
        let adjusted = LineBreakRules.adjustedBreak(firstCharacters: characters, proposed: 5)
        XCTAssertEqual(adjusted, 4, "该往前退一位，把「。」留在上一列")
        XCTAssertTrue(LineBreakRules.canStartColumn(characters[adjusted]))
    }

    func testBreakShiftsBackForOpeningBracketAtColumnEnd() {
        let characters = Array("あいうえ「おかきく")
        // 在下标 5 断会让「「」落在列尾
        let adjusted = LineBreakRules.adjustedBreak(firstCharacters: characters, proposed: 5)
        XCTAssertEqual(adjusted, 4)
        XCTAssertTrue(LineBreakRules.canEndColumn(characters[adjusted - 1]))
    }

    /// 连续多个禁则字符时最多退两位 —— 退太多会让某一列明显短一截，比违反禁则更难看。
    func testShiftIsBounded() {
        let characters = Array("あい。。。。うえお")
        let adjusted = LineBreakRules.adjustedBreak(firstCharacters: characters, proposed: 6, maxShift: 2)
        XCTAssertGreaterThanOrEqual(adjusted, 4)
        XCTAssertLessThanOrEqual(adjusted, 6)
    }

    func testCleanBreakIsLeftAlone() {
        let characters = Array("あいうえおかきくけこ")
        XCTAssertEqual(LineBreakRules.adjustedBreak(firstCharacters: characters, proposed: 5), 5)
    }

    func testEdgeCases() {
        let characters = Array("あい")
        XCTAssertEqual(LineBreakRules.adjustedBreak(firstCharacters: characters, proposed: 0), 0)
        XCTAssertEqual(LineBreakRules.adjustedBreak(firstCharacters: characters, proposed: 9), 9)
    }
}
