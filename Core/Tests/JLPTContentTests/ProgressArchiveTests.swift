import XCTest
import SwiftData
@testable import JLPTContent
import JLPTCore

/// 备份导出与恢复。
///
/// 这里的测试重点不是「能导出」，而是**恢复不能弄坏现有数据**。
/// 一个把这周进度推回上周的「备份」比没有备份更糟 —— 没有备份你至少知道自己没有。
@MainActor
final class ProgressArchiveTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    let now = Date(timeIntervalSince1970: 1_785_000_000)

    override func setUpWithError() throws {
        container = try JLPTStore.container(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    /// 另起一个空库，模拟「换了台设备」。
    private func freshContext() throws -> (ModelContainer, ModelContext) {
        let c = try JLPTStore.container(inMemory: true)
        return (c, ModelContext(c))
    }

    @discardableResult
    private func item(
        _ slug: String, in ctx: ModelContext,
        reps: Int = 0, lastReviewed: Date? = nil, starred: Bool = false, streak: Int = 0
    ) -> ReviewItemEntity {
        let srs = SRSState(
            intervalDays: reps * 3, repetitions: reps, stage: reps > 0 ? .review : .new,
            correctStreak: streak, lastReviewedAt: lastReviewed
        )
        let entity = ReviewItemEntity(kind: .vocab, contentSlug: slug, level: .n5, srs: srs)
        entity.isStarred = starred
        ctx.insert(entity)
        return entity
    }

    // MARK: - 往返

    func testRoundTripPreservesProgress() throws {
        let source = item("taberu", in: context, reps: 4, lastReviewed: now, starred: true, streak: 2)
        source.introducedAt = now.addingTimeInterval(-86_400 * 10)
        try context.save()

        let data = try ProgressArchive.encode(ProgressArchive.export(from: context, now: now))

        // 换一台「设备」：卡片存在但完全没学过
        let (holder, fresh) = try freshContext()
        _ = holder
        item("taberu", in: fresh)
        try fresh.save()

        let report = try ProgressArchive.restore(ProgressArchive.decode(data), into: fresh)
        XCTAssertEqual(report.itemsUpdated, 1)

        let restored = try XCTUnwrap(try fresh.fetch(FetchDescriptor<ReviewItemEntity>()).first)
        XCTAssertEqual(restored.repetitions, 4)
        XCTAssertEqual(restored.intervalDays, 12)
        XCTAssertEqual(restored.correctStreak, 2, "掌握进度必须跟着走，否则三次答对的门槛白攒了")
        XCTAssertTrue(restored.isStarred)
        XCTAssertEqual(restored.lastReviewedAt, now)
        XCTAssertEqual(restored.introducedAt, now.addingTimeInterval(-86_400 * 10))
    }

    // MARK: - 合并规则：不能把新进度推回去

    /// 导入一份**旧**备份，不该抹掉这之后学的东西。
    func testOlderBackupDoesNotOverwriteNewerProgress() throws {
        item("taberu", in: context, reps: 2, lastReviewed: now.addingTimeInterval(-86_400 * 7))
        try context.save()
        let oldBackup = try ProgressArchive.export(from: context, now: now)

        // 这一周又学了几次
        let current = try XCTUnwrap(try context.fetch(FetchDescriptor<ReviewItemEntity>()).first)
        current.repetitions = 9
        current.lastReviewedAt = now
        try context.save()

        let report = try ProgressArchive.restore(oldBackup, into: context)
        XCTAssertEqual(report.itemsUpdated, 0)
        XCTAssertEqual(report.itemsSkipped, 1)

        let after = try XCTUnwrap(try context.fetch(FetchDescriptor<ReviewItemEntity>()).first)
        XCTAssertEqual(after.repetitions, 9, "旧备份把这周的进度推回去了")
    }

    /// 反过来：备份比现状新，就该采用备份。
    func testNewerBackupWins() throws {
        item("taberu", in: context, reps: 9, lastReviewed: now)
        try context.save()
        let newBackup = try ProgressArchive.export(from: context, now: now)

        let (holder, fresh) = try freshContext()
        _ = holder
        item("taberu", in: fresh, reps: 2, lastReviewed: now.addingTimeInterval(-86_400 * 7))
        try fresh.save()

        try ProgressArchive.restore(newBackup, into: fresh)
        let after = try XCTUnwrap(try fresh.fetch(FetchDescriptor<ReviewItemEntity>()).first)
        XCTAssertEqual(after.repetitions, 9)
    }

    /// 库里没有这张卡（词包没启用）时跳过，不凭空造卡。
    func testUnknownItemsAreSkippedNotCreated() throws {
        item("ghost", in: context, reps: 3, lastReviewed: now)
        try context.save()
        let backup = try ProgressArchive.export(from: context, now: now)

        let (holder, fresh) = try freshContext()
        _ = holder
        let report = try ProgressArchive.restore(backup, into: fresh)

        XCTAssertEqual(report.itemsSkipped, 1)
        XCTAssertEqual(report.itemsUpdated, 0)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<ReviewItemEntity>()).isEmpty,
                      "不该凭空造出内容库里没有的卡")
    }

    // MARK: - 日志只补不改

    func testLogsAreDeduplicatedByID() throws {
        let entity = item("w", in: context, reps: 1, lastReviewed: now)
        let log = ReviewLog(
            itemID: entity.uuid, rating: .good, reviewedAt: now,
            stageBefore: .new, stageAfter: .learning,
            intervalBeforeDays: 0, intervalAfterDays: 1, easeBefore: 2.5, easeAfter: 2.5
        )
        context.insert(ReviewLogEntity(log: log))
        try context.save()

        let backup = try ProgressArchive.export(from: context, now: now)
        // 往自己身上恢复两次，日志不该翻倍
        try ProgressArchive.restore(backup, into: context)
        try ProgressArchive.restore(backup, into: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewLogEntity>()).count, 1)
    }

    func testLogsAreCarriedToAFreshDevice() throws {
        let entity = item("w", in: context, reps: 1, lastReviewed: now)
        for offset in 1...5 {
            context.insert(ReviewLogEntity(log: ReviewLog(
                itemID: entity.uuid, rating: .good,
                reviewedAt: now.addingTimeInterval(Double(-offset) * 86_400),
                stageBefore: .review, stageAfter: .review,
                intervalBeforeDays: 1, intervalAfterDays: 3, easeBefore: 2.5, easeAfter: 2.5
            )))
        }
        try context.save()
        let backup = try ProgressArchive.export(from: context, now: now)

        let (holder, fresh) = try freshContext()
        _ = holder
        item("w", in: fresh)
        try fresh.save()

        let report = try ProgressArchive.restore(backup, into: fresh)
        XCTAssertEqual(report.logsInserted, 5, "复习历史是将来换算法的训练数据，不能丢")
    }

    // MARK: - 书与笔记

    /// 用户自己导入的书要连正文一起备份 —— 原文件可能早就删了。
    func testUserImportedBookCarriesItsText() throws {
        let book = try BookImporter().importBook(
            data: Data("私の本\n作者\n\n本文です。\n二段目。".utf8),
            filename: "mine.txt", into: context, now: now
        )
        context.insert(NoteEntity(
            bookUUID: book.uuid, paragraphIndex: 1,
            quotedText: "二段目。", body: "笔记", createdAt: now
        ))
        try context.save()

        let backup = try ProgressArchive.export(from: context, now: now)
        XCTAssertNotNil(backup.books.first?.text)

        let (holder, fresh) = try freshContext()
        _ = holder
        let report = try ProgressArchive.restore(backup, into: fresh)

        XCTAssertEqual(report.booksInserted, 1)
        XCTAssertEqual(report.notesInserted, 1)

        let restored = try XCTUnwrap(try fresh.fetch(FetchDescriptor<BookEntity>()).first)
        XCTAssertFalse(restored.text.isEmpty)
        let note = try XCTUnwrap(try fresh.fetch(FetchDescriptor<NoteEntity>()).first)
        XCTAssertEqual(note.bookUUID, restored.uuid, "笔记必须还能挂回它那本书")
        XCTAssertTrue(restored.splitParagraphs().indices.contains(note.paragraphIndex),
                      "段落下标越界，点笔记跳回去会崩")
    }

    /// 随包书籍不带正文 —— 重装就有，塞进去只是让文件白白大几 MB。
    func testBundledBookTextIsOmitted() throws {
        let book = try BookImporter().importBook(
            data: Data("蜘蛛の糸\n芥川龍之介\n\n本文。".utf8),
            filename: "kumo_no_ito.txt", into: context, now: now
        )
        _ = book
        try context.save()

        let backup = try ProgressArchive.export(from: context, now: now)
        XCTAssertNil(backup.books.first?.text)
    }

    /// 阅读进度要跟着走。
    func testReadingPositionSurvives() throws {
        let book = try BookImporter().importBook(
            data: Data("私の本\n作者\n\n一。\n二。\n三。".utf8),
            filename: "mine.txt", into: context, now: now
        )
        book.paragraphIndex = 2
        book.lastOpenedAt = now
        try context.save()

        let backup = try ProgressArchive.export(from: context, now: now)
        let (holder, fresh) = try freshContext()
        _ = holder
        try ProgressArchive.restore(backup, into: fresh)

        let restored = try XCTUnwrap(try fresh.fetch(FetchDescriptor<BookEntity>()).first)
        XCTAssertEqual(restored.paragraphIndex, 2)
        XCTAssertEqual(restored.lastOpenedAt, now)
    }

    func testRestoringTwiceIsIdempotent() throws {
        let book = try BookImporter().importBook(
            data: Data("私の本\n作者\n\n本文。".utf8),
            filename: "mine.txt", into: context, now: now
        )
        context.insert(NoteEntity(
            bookUUID: book.uuid, paragraphIndex: 0, quotedText: "本文。", body: "n", createdAt: now
        ))
        try context.save()
        let backup = try ProgressArchive.export(from: context, now: now)

        let (holder, fresh) = try freshContext()
        _ = holder
        try ProgressArchive.restore(backup, into: fresh)
        let second = try ProgressArchive.restore(backup, into: fresh)

        XCTAssertEqual(second.booksInserted, 0)
        XCTAssertEqual(second.notesInserted, 0)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<BookEntity>()).count, 1)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<NoteEntity>()).count, 1)
    }

    // MARK: - 格式

    func testRejectsNewerFormatVersion() throws {
        var archive = try ProgressArchive.export(from: context, now: now)
        archive.version = ProgressArchive.currentVersion + 1
        let data = try ProgressArchive.encode(archive)

        XCTAssertThrowsError(try ProgressArchive.decode(data)) { error in
            // 必须是能看懂的话，不能是 "error 1"
            XCTAssertTrue(
                (error as? LocalizedError)?.errorDescription?.contains("格式版本") == true,
                "错误信息要说人话：\(error)"
            )
        }
    }

    func testEncodedArchiveIsReadableJSON() throws {
        item("taberu", in: context, reps: 3, lastReviewed: now)
        try context.save()
        let data = try ProgressArchive.encode(ProgressArchive.export(from: context, now: now))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("\"slug\" : \"taberu\""), "出问题时要能自己打开看")
        XCTAssertTrue(text.contains("\"version\""))
    }

    func testEmptyDatabaseExportsAndRestoresCleanly() throws {
        let backup = try ProgressArchive.export(from: context, now: now)
        let report = try ProgressArchive.restore(backup, into: context)
        XCTAssertEqual(report, ProgressArchive.RestoreReport())
    }

    /// 恢复到自己身上应该是彻底的空操作 —— 一个字段都不该写。
    ///
    /// 不加这条判断的话，从没学过的卡（两边 `lastReviewedAt` 都是 nil）会被
    /// 全部重写一遍同样的值：1382 张卡标脏落盘，还报告「更新了 1382 个词」。
    func testRestoringOntoItselfChangesNothing() throws {
        item("studied", in: context, reps: 3, lastReviewed: now)
        item("untouched", in: context)
        item("starred", in: context, starred: true)
        try context.save()

        let backup = try ProgressArchive.export(from: context, now: now)
        let report = try ProgressArchive.restore(backup, into: context)

        XCTAssertEqual(report.itemsUpdated, 0, "自恢复不该改动任何卡")
        XCTAssertEqual(report.itemsSkipped, 3)
    }

    /// 但从没学过的卡上的标记（收藏、搁置）要能恢复到空白设备。
    func testFlagsRestoreEvenWhenNeverStudied() throws {
        let source = item("starred", in: context, starred: true)
        source.isSuspended = true
        try context.save()
        let backup = try ProgressArchive.export(from: context, now: now)

        let (holder, fresh) = try freshContext()
        _ = holder
        item("starred", in: fresh)
        try fresh.save()

        let report = try ProgressArchive.restore(backup, into: fresh)
        XCTAssertEqual(report.itemsUpdated, 1)

        let restored = try XCTUnwrap(try fresh.fetch(FetchDescriptor<ReviewItemEntity>()).first)
        XCTAssertTrue(restored.isStarred, "没学过但收藏了的词，标记也得跟着走")
        XCTAssertTrue(restored.isSuspended)
    }
}
