import XCTest
import SwiftData
@testable import JLPTContent
import JLPTCore

@MainActor
final class ReviewSessionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private lazy var now = date(2026, 7, 27, 9)

    private func session(newPerDay: Int = 15, maxReviews: Int = 200) -> ReviewSession {
        ReviewSession(
            queueConfig: DailyQueueConfig(newCardsPerDay: newPerDay, maxReviewsPerDay: maxReviews, dayCutoffHour: 4),
            calendar: calendar
        )
    }

    override func setUpWithError() throws {
        container = try JLPTStore.container(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    @discardableResult
    private func makeItem(
        _ slug: String,
        kind: ReviewItemKind = .vocab,
        level: JLPTLevel = .n5,
        srs: SRSState = .new,
        suspended: Bool = false
    ) -> ReviewItemEntity {
        let item = ReviewItemEntity(kind: kind, contentSlug: slug, level: level, srs: srs, isSuspended: suspended)
        context.insert(item)
        return item
    }

    private func reviewSRS(dueDaysFromNow: Int) -> SRSState {
        SRSState(
            intervalDays: 10,
            repetitions: 3,
            dueDate: now.addingTimeInterval(Double(dueDaysFromNow) * secondsPerDay),
            stage: .review
        )
    }

    // MARK: - 队列

    func testQueueMixesDueReviewsAndNewCards() throws {
        makeItem("due1", srs: reviewSRS(dueDaysFromNow: -1))
        makeItem("due2", srs: reviewSRS(dueDaysFromNow: -2))
        makeItem("future", srs: reviewSRS(dueDaysFromNow: 3))
        makeItem("new1")
        makeItem("new2")
        try context.save()

        let q = try session().todayQueue(in: context, now: now)
        XCTAssertEqual(q.review.count, 2)
        XCTAssertEqual(q.new.count, 2)
        XCTAssertEqual(q.count, 4)
        XCTAssertFalse(q.ordered.contains { $0.contentSlug == "future" })
    }

    func testSuspendedItemsNeverAppear() throws {
        makeItem("a", srs: reviewSRS(dueDaysFromNow: -1), suspended: true)
        makeItem("b")
        makeItem("c", suspended: true)
        try context.save()

        let q = try session().todayQueue(in: context, now: now)
        XCTAssertEqual(q.ordered.map(\.contentSlug), ["b"])
    }

    func testKindFilterSeparatesVocabAndGrammar() throws {
        makeItem("v1", kind: .vocab)
        makeItem("g1", kind: .grammar)
        try context.save()

        XCTAssertEqual(try session().todayQueue(in: context, now: now, kinds: [.vocab]).count, 1)
        XCTAssertEqual(try session().todayQueue(in: context, now: now, kinds: [.grammar]).count, 1)
        XCTAssertEqual(try session().todayQueue(in: context, now: now).count, 2, "默认混合出卡")
    }

    func testLevelScopeIsCumulative() throws {
        makeItem("v5", level: .n5)
        makeItem("v4", level: .n4)
        makeItem("v3", level: .n3)
        try context.save()

        let n5Only = try session().todayQueue(in: context, now: now, levels: JLPTLevel.n5.cumulativeScope)
        XCTAssertEqual(n5Only.new.map(\.contentSlug), ["v5"])

        let n4Scope = try session().todayQueue(in: context, now: now, levels: JLPTLevel.n4.cumulativeScope)
        XCTAssertEqual(Set(n4Scope.new.map(\.contentSlug)), ["v5", "v4"], "考 N4 要连 N5 一起背")
    }

    // MARK: - 新卡配额

    func testNewCardQuotaCountsWhatWasAlreadyStudiedToday() throws {
        for i in 1...10 { makeItem("n\(i)") }
        try context.save()

        let s = session(newPerDay: 3)
        XCTAssertEqual(try s.todayQueue(in: context, now: now).new.count, 3)

        // 学掉两张
        let queue = try s.todayQueue(in: context, now: now)
        try s.answer(queue.new[0], rating: .good, now: now, in: context)
        try s.answer(queue.new[1], rating: .good, now: now, in: context)

        XCTAssertEqual(try s.newCardsIntroduced(in: context, now: now), 2)
        XCTAssertEqual(try s.todayQueue(in: context, now: now).new.count, 1, "配额只剩 1 张")
    }

    func testQuotaResetsAfterTheDayCutoff() throws {
        for i in 1...10 { makeItem("n\(i)") }
        try context.save()

        let s = session(newPerDay: 3)
        let queue = try s.todayQueue(in: context, now: now)
        for item in queue.new { try s.answer(item, rating: .good, now: now, in: context) }
        XCTAssertEqual(try s.todayQueue(in: context, now: now).new.count, 0)

        // 第二天凌晨 3 点还算「今天」
        let stillToday = date(2026, 7, 28, 3)
        XCTAssertEqual(try s.newCardsIntroduced(in: context, now: stillToday), 3)

        // 过了 4 点才是新的一天
        let tomorrow = date(2026, 7, 28, 5)
        XCTAssertEqual(try s.newCardsIntroduced(in: context, now: tomorrow), 0)
        XCTAssertEqual(try s.todayQueue(in: context, now: tomorrow).new.count, 3)
    }

    func testIntroducedAtIsStampedOnceAndNotOverwritten() throws {
        let item = makeItem("a")
        try context.save()
        let s = session()

        try s.answer(item, rating: .good, now: now, in: context)
        XCTAssertEqual(item.introducedAt, now)

        try s.answer(item, rating: .good, now: now.addingTimeInterval(600), in: context)
        XCTAssertEqual(item.introducedAt, now, "第二次评分不该重置引入时间")
    }

    // MARK: - 打分

    func testAnswerAdvancesSRSAndWritesLog() throws {
        let item = makeItem("a", srs: reviewSRS(dueDaysFromNow: 0))
        try context.save()

        let log = try session().answer(item, rating: .good, now: now, in: context)

        XCTAssertEqual(item.srs.intervalDays, 25)  // 10 × 2.5
        XCTAssertEqual(item.srs.repetitions, 4)
        XCTAssertEqual(item.srs.lastReviewedAt, now)

        XCTAssertEqual(log.itemID, item.uuid)
        XCTAssertEqual(log.intervalBeforeDays, 10)
        XCTAssertEqual(log.intervalAfterDays, 25)

        let logs = try context.fetch(FetchDescriptor<ReviewLogEntity>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].itemUUID, item.uuid)
        XCTAssertEqual(logs[0].rating, .good)
    }

    func testEveryAnswerIsLoggedForFutureFSRSMigration() throws {
        let item = makeItem("a")
        try context.save()
        let s = session()

        var t = now
        for rating in [Rating.good, .again, .good, .hard, .easy] {
            try s.answer(item, rating: rating, now: t, in: context)
            t = t.addingTimeInterval(3600)
        }

        let logs = try context.fetch(FetchDescriptor<ReviewLogEntity>()).sorted { $0.reviewedAt < $1.reviewedAt }
        XCTAssertEqual(logs.count, 5)
        XCTAssertEqual(logs.map(\.rating), [.good, .again, .good, .hard, .easy])
    }

    func testAnsweredCardLeavesTodayQueueAndComesBackWhenDue() throws {
        let item = makeItem("a", srs: reviewSRS(dueDaysFromNow: 0))
        try context.save()
        let s = session(newPerDay: 0)

        XCTAssertEqual(try s.todayQueue(in: context, now: now).count, 1)
        try s.answer(item, rating: .good, now: now, in: context)
        XCTAssertEqual(try s.todayQueue(in: context, now: now).count, 0)

        let whenDue = now.addingTimeInterval(25 * secondsPerDay)
        XCTAssertEqual(try s.todayQueue(in: context, now: whenDue).count, 1)
    }

    func testNewCardReappearsAfterItsLearningStep() throws {
        let item = makeItem("a")
        try context.save()
        let s = session()

        try s.answer(item, rating: .good, now: now, in: context)  // → 10 分钟后
        XCTAssertEqual(try s.todayQueue(in: context, now: now).learning.count, 0)

        let later = now.addingTimeInterval(601)
        let q = try s.todayQueue(in: context, now: later)
        XCTAssertEqual(q.learning.count, 1)
        XCTAssertEqual(q.ordered.first?.contentSlug, "a", "到点的巩固卡排最前")
    }

    // MARK: - 统计

    func testCountsBreakDownByStage() throws {
        makeItem("new1")
        makeItem("new2")
        makeItem("learn", srs: SRSState(dueDate: now, stage: .learning, stepIndex: 1))
        makeItem("relearn", srs: SRSState(intervalDays: 1, dueDate: now, stage: .relearning))
        makeItem("rev", srs: reviewSRS(dueDaysFromNow: 5))
        makeItem("susp", suspended: true)
        try context.save()

        let c = try session().counts(in: context)
        XCTAssertEqual(c.new, 2)
        XCTAssertEqual(c.learning, 2, "relearning 也算在巩固里")
        XCTAssertEqual(c.review, 1)
        XCTAssertEqual(c.suspended, 1)
        XCTAssertEqual(c.total, 6)
    }

    // MARK: - 导入 → 复习 全链路

    func testImportThenStudyThenReimport() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json")
        )
        let importer = ContentImporter()
        try importer.importVocabPack(data: Data(contentsOf: url), into: context, now: now)

        let s = session(newPerDay: 5)
        let queue = try s.todayQueue(in: context, now: now)
        XCTAssertEqual(queue.new.count, 5, "56 个词，今天只出 5 张新卡")

        for item in queue.new { try s.answer(item, rating: .good, now: now, in: context) }

        // 内容包改一个字重新导入，学过的 5 张卡状态不能变
        var pack = try ContentPackSchema.decoder().decode(VocabPack.self, from: Data(contentsOf: url))
        pack.vocab[0].meaningZh = "改过的释义"
        let report = try importer.importVocabPack(pack, into: context, now: now)
        XCTAssertEqual(report.updated, 1)
        XCTAssertEqual(report.reviewItemsCreated, 0)

        let studied = try context.fetch(
            FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.introducedAt != nil })
        )
        XCTAssertEqual(studied.count, 5)
        XCTAssertTrue(studied.allSatisfy { $0.srs.stage == .learning && $0.srs.stepIndex == 1 })
        XCTAssertEqual(try s.newCardsIntroduced(in: context, now: now), 5)
    }
}
