import XCTest
import CoreGraphics
import CoreText
@testable import JLPTContent

final class PDFImportTests: XCTestCase {

    /// 现场生成一份带文字层的 PDF。
    /// 比塞个二进制夹具好：内容可控，而且能验证「文字型 PDF 能抽出准确文本」这条。
    private func makePDF(pages: [String]) throws -> Data {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))

        for page in pages {
            context.beginPDFPage(nil)
            let attributed = NSAttributedString(
                string: page,
                attributes: [.font: CTFontCreateWithName("HiraginoSans-W3" as CFString, 14, nil)]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(rect: mediaBox.insetBy(dx: 40, dy: 40), transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRangeMake(0, attributed.length), path, nil
            )
            CTFrameDraw(frame, context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// 一份没有文字层的 PDF（只画了个方块），模拟扫描件。
    private func makeImageOnlyPDF() throws -> Data {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for _ in 0..<3 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 100, y: 100, width: 300, height: 300))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    // MARK: - 抽取

    func testExtractsTextFromTextBasedPDF() throws {
        let pdf = try makePDF(pages: ["これはテストです。\n日本語の文章を読みます。"])
        let result = try XCTUnwrap(PDFTextExtractor.extract(from: pdf))

        XCTAssertEqual(result.pageCount, 1)
        XCTAssertEqual(result.pagesWithText, 1)
        XCTAssertTrue(result.text.contains("これはテストです"))
        XCTAssertTrue(result.text.contains("日本語"))
        XCTAssertFalse(result.isLikelyScanned)
    }

    func testMultiplePagesAreConcatenated() throws {
        let pdf = try makePDF(pages: ["一ページ目です。", "二ページ目です。", "三ページ目です。"])
        let result = try XCTUnwrap(PDFTextExtractor.extract(from: pdf))

        XCTAssertEqual(result.pageCount, 3)
        XCTAssertEqual(result.pagesWithText, 3)
        for page in ["一ページ目", "二ページ目", "三ページ目"] {
            XCTAssertTrue(result.text.contains(page), "缺了 \(page)")
        }
    }

    func testNonPDFDataReturnsNil() {
        XCTAssertNil(PDFTextExtractor.extract(from: Data("これはただのテキストです".utf8)))
        XCTAssertNil(PDFTextExtractor.extract(from: Data()))
    }

    func testScannedPDFIsDetected() throws {
        let result = try XCTUnwrap(PDFTextExtractor.extract(from: try makeImageOnlyPDF()))
        XCTAssertEqual(result.pageCount, 3)
        XCTAssertEqual(result.pagesWithText, 0)
        XCTAssertTrue(result.isLikelyScanned, "没有文字层的 PDF 该被识别出来，而不是导入一本空书")
    }

    // MARK: - 清洗

    func testInvisibleCharactersAreStripped() {
        let dirty = "日本\u{00AD}語\u{200B}のテキスト\u{FEFF}です。"
        XCTAssertEqual(PDFTextExtractor.clean(dirty), "日本語のテキストです。")
    }

    /// PDF 常常每显示一行就断行，把一句话劈成好几段。
    func testBrokenLinesAreRejoinedAtSentenceBoundaries() {
        let broken = "これは長い文章で\nあり、途中で改行\nされています。\n次の段落です。"
        XCTAssertEqual(
            PDFTextExtractor.clean(broken),
            "これは長い文章であり、途中で改行されています。\n次の段落です。"
        )
    }

    func testDialogueLinesAreNotMerged() {
        // 「」开头的行是新的一段，不该被缝到上一行去
        let text = "彼は言った\n「おはよう」\n「こんにちは」"
        XCTAssertEqual(PDFTextExtractor.clean(text), "彼は言った\n「おはよう」\n「こんにちは」")
    }

    func testBlankLinesAreDropped() {
        XCTAssertEqual(PDFTextExtractor.clean("一。\n\n\n二。"), "一。\n二。")
    }

    // MARK: - 走完整个导入管线

    func testPDFImportsAsABook() throws {
        let pdf = try makePDF(pages: [
            "吾輩は猫である。\n名前はまだ無い。",
            "どこで生れたかとんと見当がつかぬ。",
        ])
        let (book, report) = try BookImporter().makeBook(data: pdf, filename: "neko.pdf")

        XCTAssertTrue(report.wasPDF)
        XCTAssertEqual(report.pageCount, 2)
        XCTAssertEqual(book.encodingName, "PDF")
        XCTAssertEqual(book.title, "neko", "PDF 没有青空那样的头部，用文件名当书名")
        XCTAssertGreaterThan(book.paragraphCount, 0)
        XCTAssertTrue(book.text.contains("吾輩は猫である"))
    }

    func testScannedPDFIsRejectedWithAClearError() throws {
        XCTAssertThrowsError(
            try BookImporter().makeBook(data: try makeImageOnlyPDF(), filename: "scan.pdf")
        ) { error in
            XCTAssertEqual(error as? BookImportError, .scannedPDF(filename: "scan.pdf", pageCount: 3))
        }
    }

    /// 扩展名不作数：改成 .txt 的 PDF 照样该按 PDF 处理。
    func testFormatIsDetectedFromContentNotExtension() throws {
        let pdf = try makePDF(pages: ["中身はPDFです。"])
        let (_, report) = try BookImporter().makeBook(data: pdf, filename: "misnamed.txt")
        XCTAssertTrue(report.wasPDF)
    }
}
