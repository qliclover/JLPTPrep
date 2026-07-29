import XCTest
import SwiftData
@testable import JLPTContent
import JLPTCore
import JLPTJapanese

/// 笔记的读写闭环。
///
/// 这组测试是补写的：界面改版时笔记的入口被整个弄丢了 ——
/// `NoteEntity` 在 App 层零引用，写不进也读不出，而没有任何测试发现这件事，
/// 因为之前只测了「能存进去」，没测「存进去之后取得回来」。
@MainActor
final class NotesTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let now = Date(timeIntervalSince1970: 1_774_000_000)

    override func setUpWithError() throws {
        container = try JLPTStore.container(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func makeBook(_ title: String) throws -> BookEntity {
        try BookImporter().importBook(
            // 用青空原文格式（《》），这样书名和作者行才会被剥掉，
            // 正文才是两段。写成内部的 {漢字|かんじ} 格式不会走青空分支。
            data: Data("\(title)\n作者\n\n吾輩《わがはい》は猫《ねこ》である。\n名前《なまえ》はまだ無《な》い。".utf8),
            filename: "\(title).txt",
            into: context,
            now: now
        )
    }

    private func notes(for book: BookEntity) throws -> [NoteEntity] {
        let uuid = book.uuid
        return try context.fetch(
            FetchDescriptor<NoteEntity>(
                predicate: #Predicate { $0.bookUUID == uuid },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }

    // MARK: - 写进去要取得回来

    func testNoteRoundTrip() throws {
        let book = try makeBook("猫")
        context.insert(NoteEntity(
            bookUUID: book.uuid,
            paragraphIndex: 1,
            quotedText: "名前はまだ無い。",
            body: "「まだ〜ない」是「还没…」",
            createdAt: now
        ))
        try context.save()

        let saved = try notes(for: book)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.quotedText, "名前はまだ無い。")
        XCTAssertEqual(saved.first?.body, "「まだ〜ない」是「还没…」")
        XCTAssertEqual(saved.first?.paragraphIndex, 1)
    }

    /// 换一个 context 重新读 —— 确认是真的落库，不是只活在内存里。
    func testNoteSurvivesAFreshContext() throws {
        let book = try makeBook("猫")
        let bookID = book.uuid
        context.insert(NoteEntity(
            bookUUID: bookID, paragraphIndex: 0,
            quotedText: "吾輩", body: "第一人称，古风", createdAt: now
        ))
        try context.save()

        let fresh = ModelContext(container)
        let reloaded = try fresh.fetch(
            FetchDescriptor<NoteEntity>(predicate: #Predicate { $0.bookUUID == bookID })
        )
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.body, "第一人称，古风")
    }

    // MARK: - 跳回原文

    /// 笔记记的是段落下标，点开要能定位回去。
    func testNotePointsAtARealParagraph() throws {
        let book = try makeBook("猫")
        let paragraphs = book.splitParagraphs()
        XCTAssertEqual(paragraphs.count, 2)

        context.insert(NoteEntity(
            bookUUID: book.uuid, paragraphIndex: 1,
            quotedText: "名前", body: "n", createdAt: now
        ))
        try context.save()

        let note = try XCTUnwrap(notes(for: book).first)
        XCTAssertTrue(paragraphs.indices.contains(note.paragraphIndex), "段落下标越界，跳回去会崩")
        XCTAssertTrue(
            FuriganaParser.plainText(paragraphs[note.paragraphIndex]).contains(note.quotedText),
            "笔记引用的原文不在它标记的那一段里"
        )
    }

    // MARK: - 分组与删除

    func testNotesGroupByBook() throws {
        let neko = try makeBook("猫")
        let kumo = try makeBook("蜘蛛")
        for (book, count) in [(neko, 2), (kumo, 3)] {
            for index in 0..<count {
                context.insert(NoteEntity(
                    bookUUID: book.uuid, paragraphIndex: 0,
                    quotedText: "q\(index)", body: "b\(index)", createdAt: now
                ))
            }
        }
        try context.save()

        XCTAssertEqual(try notes(for: neko).count, 2)
        XCTAssertEqual(try notes(for: kumo).count, 3)
    }

    func testDeletingANote() throws {
        let book = try makeBook("猫")
        context.insert(NoteEntity(
            bookUUID: book.uuid, paragraphIndex: 0,
            quotedText: "q", body: "b", createdAt: now
        ))
        try context.save()

        let note = try XCTUnwrap(notes(for: book).first)
        context.delete(note)
        try context.save()
        XCTAssertTrue(try notes(for: book).isEmpty)
    }

    /// 删掉书之后笔记会变成孤儿 —— 不能因此崩，界面要能显示成「已删除的书」。
    func testNotesSurviveTheirBookBeingDeleted() throws {
        let book = try makeBook("猫")
        let bookID = book.uuid
        context.insert(NoteEntity(
            bookUUID: bookID, paragraphIndex: 0,
            quotedText: "q", body: "b", createdAt: now
        ))
        try context.save()

        context.delete(book)
        try context.save()

        let orphans = try context.fetch(
            FetchDescriptor<NoteEntity>(predicate: #Predicate { $0.bookUUID == bookID })
        )
        XCTAssertEqual(orphans.count, 1, "笔记不该跟着书一起消失")
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<BookEntity>()).allSatisfy { $0.uuid != bookID },
            "书确实已删除"
        )
    }
}
