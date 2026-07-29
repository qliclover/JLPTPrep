import XCTest
@testable import JLPTJapanese

final class TextDecoderTests: XCTestCase {

    private let sample = "吾輩は猫である。名前はまだ無い。\nどこで生れたかとんと見当がつかぬ。"

    private func encoded(_ text: String, _ encoding: String.Encoding) throws -> Data {
        try XCTUnwrap(text.data(using: encoding), "这台机器编不出 \(encoding)")
    }

    // MARK: - 各编码往返

    func testUTF8RoundTrip() throws {
        let decoded = try XCTUnwrap(TextDecoder.decode(encoded(sample, .utf8)))
        XCTAssertEqual(decoded.text, sample)
        XCTAssertEqual(decoded.encoding, .utf8)
    }

    func testShiftJISRoundTrip() throws {
        let decoded = try XCTUnwrap(TextDecoder.decode(encoded(sample, .shiftJIS)))
        XCTAssertEqual(decoded.text, sample, "Shift_JIS 猜错会得到一屏乱码，这条是主要防线")
        XCTAssertEqual(decoded.encoding, .shiftJIS)
    }

    func testEUCJPRoundTrip() throws {
        let decoded = try XCTUnwrap(TextDecoder.decode(encoded(sample, .japaneseEUC)))
        XCTAssertEqual(decoded.text, sample)
        XCTAssertEqual(decoded.encoding, .japaneseEUC)
    }

    func testISO2022JPRoundTrip() throws {
        // 7-bit 编码，字节全在 ASCII 范围，会被 UTF-8 成功解出转义垃圾，
        // 所以必须在 UTF-8 之前靠转义序列识别出来。
        let decoded = try XCTUnwrap(TextDecoder.decode(encoded(sample, .iso2022JP)))
        XCTAssertEqual(decoded.text, sample)
        XCTAssertEqual(decoded.encoding, .iso2022JP)
    }

    // MARK: - BOM

    func testUTF8BOMIsStripped() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(try encoded(sample, .utf8))
        let decoded = try XCTUnwrap(TextDecoder.decode(data))
        XCTAssertEqual(decoded.text, sample, "BOM 不能留在正文里")
    }

    func testUTF16WithBOM() throws {
        var data = Data([0xFF, 0xFE])
        data.append(try encoded(sample, .utf16LittleEndian))
        let decoded = try XCTUnwrap(TextDecoder.decode(data))
        XCTAssertEqual(decoded.text, sample)
        XCTAssertEqual(decoded.encoding, .utf16LittleEndian)
    }

    // MARK: - 边界

    func testASCIIIsTreatedAsUTF8() throws {
        let decoded = try XCTUnwrap(TextDecoder.decode(Data("Hello, world.".utf8)))
        XCTAssertEqual(decoded.text, "Hello, world.")
        XCTAssertEqual(decoded.encoding, .utf8)
    }

    func testEmptyDataYieldsNil() {
        XCTAssertNil(TextDecoder.decode(Data()))
    }

    func testLongDocumentKeepsCorrectEncoding() throws {
        let long = String(repeating: sample + "\n", count: 500)
        let decoded = try XCTUnwrap(TextDecoder.decode(encoded(long, .shiftJIS)))
        XCTAssertEqual(decoded.text, long)
        XCTAssertEqual(decoded.encoding, .shiftJIS)
    }

    // MARK: - 打分函数

    func testJaponesenessRewardsRealJapanese() {
        let good = TextDecoder.japaneseness(of: sample)
        let garbage = TextDecoder.japaneseness(of: "\u{0001}\u{0002}\u{E000}\u{E001}\u{0003}")
        XCTAssertGreaterThan(good, 0.9)
        XCTAssertLessThan(garbage, 0)
    }

    func testEncodingNamesAreHumanReadable() throws {
        let decoded = try XCTUnwrap(TextDecoder.decode(encoded(sample, .shiftJIS)))
        XCTAssertEqual(decoded.encodingName, "Shift_JIS")
    }
}

final class AozoraMarkupTests: XCTestCase {

    // MARK: - 注音

    func testRubyWithExplicitBaseMarker() {
        XCTAssertEqual(
            AozoraMarkup.convertRuby("やって｜来《き》た"),
            "やって{来|き}た"
        )
    }

    func testRubyWithoutMarkerAttachesToPrecedingKanji() {
        XCTAssertEqual(AozoraMarkup.convertRuby("大人《おとな》"), "{大人|おとな}")
        XCTAssertEqual(
            AozoraMarkup.convertRuby("吾輩《わがはい》は猫《ねこ》である。"),
            "{吾輩|わがはい}は{猫|ねこ}である。"
        )
    }

    func testRubyStopsAtKanaBoundary() {
        // 「を食《た》べる」的注音只能盖住「食」
        XCTAssertEqual(AozoraMarkup.convertRuby("ご飯を食《た》べる"), "ご飯を{食|た}べる")
    }

    func testMalformedRubyIsLeftAlone() {
        XCTAssertEqual(AozoraMarkup.convertRuby("《かんじ》"), "《かんじ》", "没有注音对象就原样保留")
        XCTAssertEqual(AozoraMarkup.convertRuby("漢字《"), "漢字《", "没闭合不能吞掉后文")
        XCTAssertEqual(AozoraMarkup.convertRuby("かな《よみ》"), "かな《よみ》", "前面不是汉字，不该硬套")
    }

    func testTextWithoutRubyIsUnchanged() {
        let text = "普通の文章です。\n改行もあります。"
        XCTAssertEqual(AozoraMarkup.convertRuby(text), text)
    }

    // MARK: - 注记

    func testTypesettingNotesAreRemoved() {
        XCTAssertEqual(AozoraMarkup.stripNotes("本文［＃「本文」に傍点］です"), "本文です")
        XCTAssertEqual(AozoraMarkup.stripNotes("［＃改ページ］次の章"), "次の章")
    }

    func testUnclosedNoteDoesNotEatTheRest() {
        let text = "本文［＃壊れた注記 そのあとの文章"
        XCTAssertEqual(AozoraMarkup.stripNotes(text), text, "没闭合就当普通文本，不能把后半篇吞了")
    }

    // MARK: - 页眉页脚

    func testHeaderFenceBlockIsRemoved() {
        let text = """
        坊っちゃん
        夏目漱石

        -------------------------------------------------------
        【テキスト中に現れる記号について】
        《》：ルビ
        -------------------------------------------------------

        親譲りの無鉄砲で子供の時から損ばかりしている。
        """
        let stripped = AozoraMarkup.stripBoilerplate(text)
        XCTAssertFalse(stripped.contains("ルビ"))
        XCTAssertFalse(stripped.contains("---"))
        XCTAssertTrue(stripped.contains("親譲りの無鉄砲"))
        XCTAssertTrue(stripped.contains("坊っちゃん"), "书名要留着，导入时还要用")
    }

    func testColophonIsRemoved() {
        let text = "本文です。\n\n底本：「坊っちゃん」新潮文庫\n入力：青空文庫"
        let stripped = AozoraMarkup.stripBoilerplate(text)
        XCTAssertTrue(stripped.contains("本文です。"))
        XCTAssertFalse(stripped.contains("底本"))
        XCTAssertFalse(stripped.contains("入力"))
    }

    func testFullNormalizePipeline() {
        let text = """
        坊っちゃん
        夏目漱石

        -------------------------------------------------------
        【テキスト中に現れる記号について】
        -------------------------------------------------------

        親譲《おやゆず》りの無鉄砲［＃「無鉄砲」に傍点］で損ばかりしている。

        底本：「坊っちゃん」
        """
        let result = AozoraMarkup.normalize(text)
        XCTAssertTrue(result.contains("{親譲|おやゆず}り"))
        XCTAssertTrue(result.contains("無鉄砲で損ばかり"))
        XCTAssertFalse(result.contains("［＃"))
        XCTAssertFalse(result.contains("底本"))
    }

    func testDetection() {
        XCTAssertTrue(AozoraMarkup.looksLikeAozora("吾輩《わがはい》は猫である"))
        XCTAssertTrue(AozoraMarkup.looksLikeAozora("本文\n底本：「something」"))
        XCTAssertFalse(AozoraMarkup.looksLikeAozora("ただの日本語のテキストです。"))
    }
}
