import XCTest
@testable import JLPTCore

final class FuriganaTests: XCTestCase {

    func testPlainTextWithoutAnnotations() {
        XCTAssertEqual(FuriganaParser.parse("ちょっと"), [.plain("ちょっと")])
        XCTAssertEqual(FuriganaParser.parse(""), [])
    }

    func testSingleAnnotation() {
        XCTAssertEqual(FuriganaParser.parse("{学校|がっこう}"), [.ruby(base: "学校", reading: "がっこう")])
    }

    func testAnnotationFollowedByKana() {
        XCTAssertEqual(
            FuriganaParser.parse("{食|た}べる"),
            [.ruby(base: "食", reading: "た"), .plain("べる")]
        )
    }

    func testMultipleAnnotationsInASentence() {
        XCTAssertEqual(
            FuriganaParser.parse("{毎朝|まいあさ}パンを{食|た}べます。"),
            [
                .ruby(base: "毎朝", reading: "まいあさ"),
                .plain("パンを"),
                .ruby(base: "食", reading: "た"),
                .plain("べます。"),
            ]
        )
    }

    func testAdjacentAnnotations() {
        XCTAssertEqual(
            FuriganaParser.parse("{毎日|まいにち}{野菜|やさい}"),
            [.ruby(base: "毎日", reading: "まいにち"), .ruby(base: "野菜", reading: "やさい")]
        )
    }

    func testOkuriganaInsideWord() {
        // 「ご飯」这类中间夹假名的情况
        XCTAssertEqual(
            FuriganaParser.parse("{朝|あさ}ご{飯|はん}"),
            [.ruby(base: "朝", reading: "あさ"), .plain("ご"), .ruby(base: "飯", reading: "はん")]
        )
    }

    // MARK: - 容错：坏标注当普通文本，不能崩也不能吞字

    func testMalformedAnnotationsFallBackToLiteralText() {
        let cases = [
            "{食|た",          // 没闭合
            "{食べる}",         // 没有分隔符
            "{|た}",           // 空汉字
            "{食|}",           // 空读音
            "{食|た|べ}",       // 两个分隔符
            "}食{",            // 顺序反了
        ]
        for text in cases {
            let rebuilt = FuriganaParser.parse(text).map(\.base).joined()
            XCTAssertEqual(rebuilt, text, "「\(text)」应原样保留")
        }
    }

    func testNestedBracesRecoverTheInnerAnnotation() {
        // 外层 `{` 不成组，退化成普通字符；内层照常解析。
        // 结果是「{食}」带注音 —— 花括号会显示出来，正好提示这条数据要修。
        XCTAssertEqual(
            FuriganaParser.parse("{{食|た}}"),
            [.plain("{"), .ruby(base: "食", reading: "た"), .plain("}")]
        )
    }

    func testGoodAnnotationSurvivesNextToABadOne() {
        XCTAssertEqual(
            FuriganaParser.parse("{食|た}べる{壊れた"),
            [.ruby(base: "食", reading: "た"), .plain("べる{壊れた")]
        )
    }

    // MARK: - 派生文本

    func testPlainAndReadingProjections() {
        let text = "{毎朝|まいあさ}パンを{食|た}べます。"
        XCTAssertEqual(FuriganaParser.plainText(text), "毎朝パンを食べます。")
        XCTAssertEqual(FuriganaParser.readingText(text), "まいあさパンをたべます。")
    }

    func testPlainTextRoundTripsUnannotatedInput() {
        XCTAssertEqual(FuriganaParser.plainText("ちょっと待ってください。"), "ちょっと待ってください。")
    }
}

final class IntervalFormatterTests: XCTestCase {

    func testHumanReadableIntervals() {
        XCTAssertEqual(IntervalFormatter.string(seconds: 30), "<1分")
        XCTAssertEqual(IntervalFormatter.string(seconds: 60), "1分")
        XCTAssertEqual(IntervalFormatter.string(seconds: 600), "10分")
        XCTAssertEqual(IntervalFormatter.string(seconds: 3600 * 5), "5小时")
        XCTAssertEqual(IntervalFormatter.string(seconds: secondsPerDay), "1天")
        XCTAssertEqual(IntervalFormatter.string(seconds: secondsPerDay * 6), "6天")
        XCTAssertEqual(IntervalFormatter.string(seconds: secondsPerDay * 60), "60天")
        XCTAssertEqual(IntervalFormatter.string(seconds: secondsPerDay * 90), "3个月")
        XCTAssertEqual(IntervalFormatter.string(seconds: secondsPerDay * 135), "4.5个月")
        XCTAssertEqual(IntervalFormatter.string(seconds: secondsPerDay * 365), "1年")
        XCTAssertEqual(IntervalFormatter.string(seconds: secondsPerDay * 550), "1.5年")
    }

    func testNegativeIntervalsClampToZero() {
        XCTAssertEqual(IntervalFormatter.string(seconds: -5000), "<1分")
    }

    func testSchedulerPreviewShowsAllFourButtons() {
        let scheduler = SM2Scheduler()
        let now = Date(timeIntervalSince1970: 1_774_000_000)

        let newCard = scheduler.preview(state: .new, now: now)
        XCTAssertEqual(newCard[.again], "1分")
        XCTAssertEqual(newCard[.hard], "1分")
        XCTAssertEqual(newCard[.good], "10分")
        // Easy 不再能一步毕业：要攒够三次答对才进长间隔，
        // 所以它和 Good 一样只推进一个学习步骤。
        XCTAssertEqual(newCard[.easy], "10分")

        let mature = SRSState(intervalDays: 10, repetitions: 4, dueDate: now, stage: .review)
        let preview = scheduler.preview(state: mature, now: now)
        XCTAssertEqual(preview[.again], "10分")
        XCTAssertEqual(preview[.hard], "12天")
        XCTAssertEqual(preview[.good], "25天")
        XCTAssertEqual(preview[.easy], "34天")  // 10 × 2.65 × 1.3
    }
}
