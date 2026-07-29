import XCTest
@testable import JLPTContent
@testable import JLPTJapanese
import JLPTCore

/// 拿一本真书跑管线。
///
/// 合成数据测不出的东西这里能测出来：真实的青空文庫文件是 Shift_JIS，
/// 头部凡例块的格式和我手写的不完全一样，正文里混着 `［＃７字下げ］` 这类
/// 我没预料到的注记，还有中见出し标记。
final class RealAozoraFileTests: XCTestCase {

    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "kumo_no_ito", withExtension: "txt", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "kumo_no_ito", withExtension: "txt"),
            "缺少真实青空文庫夹具"
        )
        return try Data(contentsOf: url)
    }

    func testRealAozoraFileIsShiftJIS() throws {
        let decoded = try XCTUnwrap(TextDecoder.decode(try fixtureData()))
        XCTAssertEqual(decoded.encoding, .shiftJIS, "青空文庫的 txt 是 Shift_JIS，嗅探必须认出来")
        XCTAssertTrue(decoded.text.contains("蜘蛛の糸"))
    }

    func testRealAozoraFileImports() throws {
        let (book, report) = try BookImporter().makeBook(
            data: try fixtureData(),
            filename: "kumo_no_ito.txt"
        )

        XCTAssertTrue(report.wasAozora)
        XCTAssertEqual(book.title, "蜘蛛の糸", "书名该从正文头两行取，而不是用文件名")
        XCTAssertEqual(book.author, "芥川龍之介")
        XCTAssertEqual(book.encodingName, "Shift_JIS")
        XCTAssertTrue(book.hasEmbeddedRuby, "原文自带人工注音")
        XCTAssertGreaterThan(book.paragraphCount, 10)
        XCTAssertGreaterThan(book.charCount, 2000)
    }

    func testBoilerplateAndTypesettingNotesAreGone() throws {
        let (book, _) = try BookImporter().makeBook(data: try fixtureData(), filename: "kumo_no_ito.txt")

        XCTAssertFalse(book.text.contains("底本："), "文末的底本信息该删掉")
        XCTAssertFalse(book.text.contains("入力："), "校对者信息该删掉")
        XCTAssertFalse(book.text.contains("［＃"), "排版注记该删掉")
        XCTAssertFalse(book.text.contains("《"), "注音标记该已经转成我们的格式")
        XCTAssertFalse(book.text.contains("【テキスト中に現れる記号について】"), "凡例块该删掉")
    }

    func testRubyConvertedIntoOurFormat() throws {
        let (book, _) = try BookImporter().makeBook(data: try fixtureData(), filename: "kumo_no_ito.txt")

        // 转换后应该有大量 {漢字|かんじ}，且每一个都合法
        var rubyCount = 0
        for paragraph in book.splitParagraphs() {
            for segment in FuriganaParser.parse(paragraph) {
                if case .ruby(let base, let reading) = segment {
                    rubyCount += 1
                    XCTAssertFalse(base.isEmpty)
                    XCTAssertFalse(reading.isEmpty)
                    XCTAssertFalse(Kana.containsKanji(reading), "注音「\(reading)」里混进了汉字")
                }
            }
        }
        XCTAssertGreaterThan(rubyCount, 50, "这本书原文有大量注音，转换后不该所剩无几")
    }

    func testEveryParagraphIsTappableWithoutLosingText() throws {
        let (book, _) = try BookImporter().makeBook(data: try fixtureData(), filename: "kumo_no_ito.txt")

        for (index, paragraph) in book.splitParagraphs().enumerated() {
            let words = ReaderText.words(annotated: paragraph)
            XCTAssertEqual(
                words.map(\.surface).joined(),
                FuriganaParser.plainText(paragraph),
                "第 \(index) 段切词后拼不回原文 —— 点击位置会错位"
            )
        }
    }

    /// 真实文本里的活用能被还原多少。和振假名那次一样，给个可以拿去做决策的数字。
    func testDeinflectionCoverageOnRealText() throws {
        let (book, _) = try BookImporter().makeBook(data: try fixtureData(), filename: "kumo_no_ito.txt")

        var lookupable = 0
        var deinflected = 0
        for paragraph in book.splitParagraphs() {
            for word in ReaderText.words(annotated: paragraph) where word.isLookupable {
                lookupable += 1
                if Deinflector.best(word.surface) != nil { deinflected += 1 }
            }
        }

        let rate = Double(deinflected) / Double(max(lookupable, 1)) * 100
        print(String(
            format: "\n┌─ 《蜘蛛の糸》可点词 %d 个，其中 %d 个能给出原形（%.1f%%）\n└─ 其余多为名词、助词、专有名词，本来就没有活用\n",
            lookupable, deinflected, rate
        ))
        XCTAssertGreaterThan(lookupable, 200, "一本短篇该切出几百个可点词")
    }
}
