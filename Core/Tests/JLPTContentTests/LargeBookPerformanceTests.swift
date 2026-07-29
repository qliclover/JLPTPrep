import XCTest
@testable import JLPTContent
@testable import JLPTJapanese

/// 大书性能。目标是**不对书的大小设限**，所以这里的数字是硬约束，不是参考值。
///
/// 三档规模：
/// - 中篇（约 30 万字）：一般小说
/// - 长篇（约 300 万字）：《战争与和平》量级
/// - 退化输入（300 万字single line，无换行）：用户可以导入任何文件，
///   包括一整本没有分段的文本。这是最容易把朴素实现拖成 O(n²) 的形状。
final class LargeBookPerformanceTests: XCTestCase {

    /// 造一段带注音的日语文本。
    private func paragraph(_ index: Int) -> String {
        "　第\(index)段落《だんらく》では、主人公《しゅじんこう》が学校《がっこう》へ行《い》って、"
            + "友達《ともだち》と話《はな》しました。天気《てんき》はとても良《よ》かったです。"
    }

    private func book(paragraphs count: Int, singleLine: Bool = false) -> String {
        let body = (1...count).map(paragraph).joined(separator: singleLine ? "" : "\n")
        return "テスト長編\n作者名\n\n" + body + "\n\n底本：テスト"
    }

    private func measureSeconds(_ label: String, _ work: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now()
        try work()
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        print(String(format: "  %@ %.3f 秒", label.padding(toLength: 34, withPad: " ", startingAt: 0), seconds))
        return seconds
    }

    // MARK: - 中篇

    func testMediumNovelImportsQuickly() throws {
        let text = book(paragraphs: 4_000)   // 约 30 万字
        let data = Data(text.utf8)
        print("\n── 中篇 \(text.count) 字 ──")

        var result: (BookEntity, BookImportReport)?
        let seconds = try measureSeconds("导入总耗时") {
            result = try BookImporter().makeBook(data: data, filename: "medium.txt")
        }
        let book = try XCTUnwrap(result?.0)

        XCTAssertEqual(book.paragraphCount, 4_000)
        XCTAssertTrue(book.hasEmbeddedRuby)
        XCTAssertLessThan(seconds, 3.0, "30 万字的书导入不该超过 3 秒")
    }

    // MARK: - 长篇

    func testVeryLongNovelImportsWithoutBlowingUp() throws {
        let text = book(paragraphs: 40_000)  // 约 300 万字
        let data = Data(text.utf8)
        print("\n── 长篇 \(text.count) 字 / \(data.count / 1_048_576) MB ──")

        var result: (BookEntity, BookImportReport)?
        let seconds = try measureSeconds("导入总耗时") {
            result = try BookImporter().makeBook(data: data, filename: "long.txt")
        }
        let book = try XCTUnwrap(result?.0)

        XCTAssertEqual(book.paragraphCount, 40_000)
        // 10 倍的量，耗时也该是大致 10 倍 —— 超过就说明有 O(n²)
        XCTAssertLessThan(seconds, 20.0, "300 万字的书导入超过 20 秒，说明复杂度不是线性的")
    }

    // MARK: - 退化输入

    /// 整本书一行不分段。朴素的「往回找注音对象」实现会在这里退化成 O(n²)。
    func testSingleLineBookDoesNotDegrade() throws {
        let text = book(paragraphs: 20_000, singleLine: true)
        let data = Data(text.utf8)
        print("\n── 无换行退化输入 \(text.count) 字 ──")

        var result: (BookEntity, BookImportReport)?
        let seconds = try measureSeconds("导入总耗时") {
            result = try BookImporter().makeBook(data: data, filename: "oneline.txt")
        }
        _ = try XCTUnwrap(result?.0)
        XCTAssertLessThan(seconds, 20.0, "无换行的长文本把注音解析拖垮了")
    }

    /// 只有开括号没有闭括号 —— 每个 `《` 都会触发一次「找不到的搜索」。
    func testManyUnclosedRubyMarkersDoNotDegrade() throws {
        let text = String(repeating: "漢字《", count: 60_000)
        let data = Data(text.utf8)
        print("\n── 6 万个未闭合注音标记 ──")

        let seconds = try measureSeconds("注音解析") {
            _ = AozoraMarkup.convertRuby(text)
        }
        XCTAssertLessThan(seconds, 5.0, "未闭合标记导致了全文重复扫描")
        _ = data
    }

    // MARK: - 编码嗅探

    func testEncodingSniffingDoesNotDecodeHugeFilesRepeatedly() throws {
        let text = book(paragraphs: 40_000)
        let data = try XCTUnwrap(text.data(using: .shiftJIS))
        print("\n── Shift_JIS 长篇 \(data.count / 1_048_576) MB ──")

        var decoded: TextDecoder.DecodedText?
        let seconds = try measureSeconds("编码嗅探 + 解码") {
            decoded = TextDecoder.decode(data)
        }
        XCTAssertEqual(decoded?.encoding, .shiftJIS)
        XCTAssertLessThan(seconds, 10.0, "候选编码逐个全量解码，大文件上代价太高")
    }

    // MARK: - 段落访问

    /// 阅读器每次访问 `paragraphs` 都会重新切分全文。
    /// 如果 UI 在滚动时反复读它，几百万字的书会卡死。
    func testParagraphAccessIsNotAccidentallyQuadratic() throws {
        let text = book(paragraphs: 40_000)
        let (book, _) = try BookImporter().makeBook(data: Data(text.utf8), filename: "long.txt")
        print("\n── 段落访问（40000 段）──")

        let seconds = try measureSeconds("连续取 20 次 paragraphs") {
            for _ in 0..<20 {
                _ = book.splitParagraphs().count
            }
        }
        XCTAssertLessThan(seconds, 5.0, "反复切分全文太慢，阅读器需要缓存或索引")
    }
}
