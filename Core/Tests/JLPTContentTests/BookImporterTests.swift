import XCTest
import SwiftData
@testable import JLPTContent

@MainActor
final class BookImporterTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let importer = BookImporter()
    let now = Date(timeIntervalSince1970: 1_774_000_000)

    override func setUpWithError() throws {
        container = try JLPTStore.container(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func data(_ text: String, _ encoding: String.Encoding = .utf8) throws -> Data {
        try XCTUnwrap(text.data(using: encoding))
    }

    // MARK: - 普通 txt

    func testPlainTextImport() throws {
        let text = "一行目です。\n\n二行目です。\n三行目です。"
        let (book, report) = try importer.makeBook(data: try data(text), filename: "メモ.txt", now: now)

        XCTAssertEqual(book.title, "メモ", "没有书名信息时用文件名（去扩展名）")
        XCTAssertNil(book.author)
        XCTAssertEqual(book.paragraphCount, 3, "空行不算段落")
        XCTAssertEqual(book.splitParagraphs(), ["一行目です。", "二行目です。", "三行目です。"])
        XCTAssertEqual(book.encodingName, "UTF-8")
        XCTAssertFalse(report.wasAozora)
        XCTAssertFalse(book.hasEmbeddedRuby)
        XCTAssertEqual(book.paragraphIndex, 0)
    }

    func testShiftJISFileImportsCorrectly() throws {
        let text = "吾輩は猫である。\n名前はまだ無い。"
        let (book, _) = try importer.makeBook(data: try data(text, .shiftJIS), filename: "neko.txt", now: now)

        XCTAssertEqual(book.encodingName, "Shift_JIS")
        XCTAssertEqual(book.splitParagraphs(), ["吾輩は猫である。", "名前はまだ無い。"])
    }

    func testIndentationIsTrimmed() throws {
        // 日文正文常用全角空格缩进，留着会让每段左边多出一个空格
        let text = "\u{3000}全角空白で始まる段落。\n  半角空白の段落。"
        let (book, _) = try importer.makeBook(data: try data(text), filename: "a.txt", now: now)
        XCTAssertEqual(book.splitParagraphs(), ["全角空白で始まる段落。", "半角空白の段落。"])
    }

    func testWindowsLineEndings() throws {
        let (book, _) = try importer.makeBook(data: try data("一\r\n二\r\n三"), filename: "a.txt", now: now)
        XCTAssertEqual(book.splitParagraphs(), ["一", "二", "三"])
    }

    /// 青空文庫的真实文件是 CRLF。之前只测了纯文本的 CRLF，没测「CRLF + 青空头部」
    /// 这个组合，结果作者行被 `\r` 切出的空串顶掉，作者名混进了正文。
    func testAozoraHeaderWithWindowsLineEndings() throws {
        // 必须带青空特征标记（《》），否则根本不会走青空分支 —— 真实文件都有
        let text = "蜘蛛の糸\r\n芥川龍之介\r\n\r\n或日《あるひ》の事でございます。\r\n"
        let (book, _) = try importer.makeBook(data: try data(text), filename: "kumo.txt", now: now)

        XCTAssertEqual(book.title, "蜘蛛の糸")
        XCTAssertEqual(book.author, "芥川龍之介")
        XCTAssertEqual(book.splitParagraphs(), ["{或日|あるひ}の事でございます。"], "作者名不该出现在正文里")
    }

    // MARK: - 青空文庫

    func testAozoraImportUsesEmbeddedRuby() throws {
        let text = """
        坊っちゃん
        夏目漱石

        -------------------------------------------------------
        【テキスト中に現れる記号について】
        《》：ルビ
        -------------------------------------------------------

        親譲《おやゆず》りの無鉄砲［＃「無鉄砲」に傍点］で子供の時から損ばかりしている。

        底本：「坊っちゃん」新潮文庫
        """
        let (book, report) = try importer.makeBook(data: try data(text), filename: "789_14547.txt", now: now)

        XCTAssertTrue(report.wasAozora)
        XCTAssertEqual(book.title, "坊っちゃん", "青空文庫的头两行是书名和作者")
        XCTAssertEqual(book.author, "夏目漱石")
        XCTAssertTrue(book.hasEmbeddedRuby, "原文自带人工注音，阅读器就不用跑分词了")
        XCTAssertEqual(book.splitParagraphs(), ["{親譲|おやゆず}りの無鉄砲で子供の時から損ばかりしている。"])
        XCTAssertFalse(book.text.contains("底本"))
        XCTAssertFalse(book.text.contains("ルビ"))
    }

    func testTitleHeuristicDeclinesWhenFirstLineLooksLikeProse() throws {
        // 第一行是完整句子，那多半是正文而不是书名
        let text = "吾輩《わがはい》は猫である。名前はまだ無い。\nどこで生れたかとんと見当がつかぬ。"
        let (book, _) = try importer.makeBook(data: try data(text), filename: "wagahai.txt", now: now)

        XCTAssertEqual(book.title, "wagahai", "拿不准就退回文件名，别把正文第一句当书名")
        XCTAssertTrue(book.splitParagraphs()[0].contains("{吾輩|わがはい}"))
    }

    // MARK: - 错误

    func testEmptyDocumentIsRejected() throws {
        XCTAssertThrowsError(try importer.makeBook(data: try data("\n\n   \n"), filename: "empty.txt")) { error in
            XCTAssertEqual(error as? BookImportError, .emptyDocument(filename: "empty.txt"))
        }
    }

    func testUndecodableDataIsRejected() {
        XCTAssertThrowsError(try importer.makeBook(data: Data(), filename: "zero.txt")) { error in
            XCTAssertEqual(error as? BookImportError, .undecodable(filename: "zero.txt"))
        }
    }

    // MARK: - 落库与阅读位置

    func testImportPersistsAndProgressTracks() throws {
        let text = (1...100).map { "第\($0)段落です。" }.joined(separator: "\n")
        let book = try importer.importBook(data: try data(text), filename: "long.txt", into: context, now: now)

        let stored = try context.fetch(FetchDescriptor<BookEntity>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.paragraphCount, 100)

        XCTAssertEqual(book.progress, 0, accuracy: 1e-9)
        book.paragraphIndex = 99
        XCTAssertEqual(book.progress, 1, accuracy: 1e-9)
        book.paragraphIndex = 49
        XCTAssertEqual(book.progress, 49.0 / 99.0, accuracy: 1e-9)
    }

    func testNotesAttachToParagraphs() throws {
        let book = try importer.importBook(data: try data("一\n二\n三"), filename: "a.txt", into: context, now: now)
        context.insert(NoteEntity(
            bookUUID: book.uuid,
            paragraphIndex: 1,
            quotedText: "二",
            body: "这里不懂",
            createdAt: now
        ))
        try context.save()

        let bookID = book.uuid
        let notes = try context.fetch(
            FetchDescriptor<NoteEntity>(predicate: #Predicate { $0.bookUUID == bookID })
        )
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.paragraphIndex, 1)
        XCTAssertEqual(notes.first?.quotedText, "二")
    }

    func testImportingSameFileTwiceMakesTwoBooks() throws {
        // 书不做去重：同一本书用户可能故意导两份（不同版本、不同译本）。
        // 内容包才需要按指纹判重，那是完全不同的东西。
        try importer.importBook(data: try data("本文"), filename: "a.txt", into: context, now: now)
        try importer.importBook(data: try data("本文"), filename: "a.txt", into: context, now: now)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BookEntity>()).count, 2)
    }
}
