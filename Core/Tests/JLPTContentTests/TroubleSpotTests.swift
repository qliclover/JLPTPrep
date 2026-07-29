import XCTest
import SwiftData
@testable import JLPTContent
import JLPTCore

/// 错题本的取数与排序。
///
/// 排序口径是这个功能的全部价值 —— 排错了就是让人把时间花在不该花的词上。
@MainActor
final class TroubleSpotTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    private lazy var now = date(2026, 7, 28)

    private func session() -> ReviewSession {
        ReviewSession(calendar: calendar)
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
    private func item(_ slug: String, level: JLPTLevel = .n5, lapses: Int = 0) -> ReviewItemEntity {
        let srs = SRSState(intervalDays: 5, repetitions: 2, lapses: lapses, stage: .review)
        let entity = ReviewItemEntity(kind: .vocab, contentSlug: slug, level: level, srs: srs)
        context.insert(entity)
        return entity
    }

    private func log(_ item: ReviewItemEntity, _ rating: Rating, daysAgo: Int) {
        let at = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        context.insert(ReviewLogEntity(log: ReviewLog(
            itemID: item.uuid, rating: rating, reviewedAt: at,
            stageBefore: .review, stageAfter: .review,
            intervalBeforeDays: 5, intervalAfterDays: 1,
            easeBefore: 2.5, easeAfter: 2.3
        )))
    }

    // MARK: - 只收错过的

    func testOnlyItemsWithFailuresAppear() throws {
        let bad = item("bad")
        let good = item("good")
        log(bad, .again, daysAgo: 2)
        log(good, .good, daysAgo: 2)
        log(good, .easy, daysAgo: 1)
        try context.save()

        let spots = try session().troubleSpots(in: context, now: now)
        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(spots[0].item.contentSlug, "bad")
    }

    func testNoFailuresGivesEmptyList() throws {
        let a = item("a")
        log(a, .good, daysAgo: 1)
        try context.save()
        XCTAssertTrue(try session().troubleSpots(in: context, now: now).isEmpty)
    }

    // MARK: - 排序

    /// 首要是错的次数。
    func testSortedByFailureCount() throws {
        let once = item("once")
        let thrice = item("thrice")
        log(once, .again, daysAgo: 1)
        for d in 1...3 { log(thrice, .again, daysAgo: d) }
        try context.save()

        let spots = try session().troubleSpots(in: context, now: now)
        XCTAssertEqual(spots.map(\.item.contentSlug), ["thrice", "once"])
        XCTAssertEqual(spots[0].againCount, 3)
    }

    /// 错的次数相同时，正确率低的排前面 —— 错 2 次做过 3 次，比错 2 次做过 10 次严重。
    func testTiesBrokenByAccuracy() throws {
        let fragile = item("fragile")   // 3 次里错 2 次
        let sturdy = item("sturdy")     // 10 次里错 2 次
        for d in 1...2 { log(fragile, .again, daysAgo: d) }
        log(fragile, .good, daysAgo: 3)
        for d in 1...2 { log(sturdy, .again, daysAgo: d) }
        for d in 3...10 { log(sturdy, .good, daysAgo: d) }
        try context.save()

        let spots = try session().troubleSpots(in: context, now: now)
        XCTAssertEqual(spots.map(\.item.contentSlug), ["fragile", "sturdy"])
        XCTAssertEqual(spots[0].accuracy, 1.0 / 3.0, accuracy: 0.001)
    }

    /// 「只做过一次且错了」不该冲到最前面 —— 那是没学熟，不是难点。
    func testSingleFailureDoesNotOutrankRepeatedFailures() throws {
        let brandNew = item("brandNew")     // 正确率 0%，但只错过 1 次
        let chronic = item("chronic")       // 错过 4 次
        log(brandNew, .again, daysAgo: 1)
        for d in 1...4 { log(chronic, .again, daysAgo: d) }
        for d in 5...8 { log(chronic, .good, daysAgo: d) }
        try context.save()

        let spots = try session().troubleSpots(in: context, now: now)
        XCTAssertEqual(spots.first?.item.contentSlug, "chronic",
                       "正确率 0% 但只错一次的卡不该压过反复错的卡")
    }

    /// 次数和正确率都一样时，最近错的排前面。
    func testTiesBrokenByRecency() throws {
        let old = item("old")
        let recent = item("recent")
        log(old, .again, daysAgo: 30)
        log(recent, .again, daysAgo: 2)
        try context.save()

        let spots = try session().troubleSpots(in: context, now: now)
        XCTAssertEqual(spots.map(\.item.contentSlug), ["recent", "old"])
    }

    // MARK: - 时间窗口

    /// 三个月前错过、现在已经稳了的卡，不该继续摆在错题本里。
    func testFailuresOutsideTheWindowAreIgnored() throws {
        let ancient = item("ancient")
        log(ancient, .again, daysAgo: 90)
        try context.save()

        XCTAssertTrue(try session().troubleSpots(in: context, days: 60, now: now).isEmpty)
        XCTAssertEqual(try session().troubleSpots(in: context, days: 120, now: now).count, 1)
    }

    // MARK: - 过滤与上限

    func testLevelFilterApplies() throws {
        let n5 = item("easy", level: .n5)
        let n1 = item("hard", level: .n1)
        log(n5, .again, daysAgo: 1)
        log(n1, .again, daysAgo: 1)
        try context.save()

        let spots = try session().troubleSpots(in: context, now: now, levels: [.n5])
        XCTAssertEqual(spots.map(\.item.contentSlug), ["easy"])
    }

    func testLimitCapsResults() throws {
        for i in 0..<30 {
            let entity = item("w\(i)")
            log(entity, .again, daysAgo: 1)
        }
        try context.save()
        XCTAssertEqual(try session().troubleSpots(in: context, limit: 10, now: now).count, 10)
    }

    // MARK: - 字段

    func testCountsAndLapsesAreReported() throws {
        let entity = item("w", lapses: 7)
        for d in 1...3 { log(entity, .again, daysAgo: d) }
        for d in 4...5 { log(entity, .good, daysAgo: d) }
        try context.save()

        let spot = try XCTUnwrap(try session().troubleSpots(in: context, now: now).first)
        XCTAssertEqual(spot.againCount, 3)
        XCTAssertEqual(spot.totalCount, 5)
        XCTAssertEqual(spot.lapses, 7, "累计遗忘次数来自 SRS 状态，不是窗口内的计数")
        XCTAssertEqual(spot.accuracy, 0.4, accuracy: 0.001)
        XCTAssertEqual(spot.lastAgainAt, calendar.date(byAdding: .day, value: -1, to: now))
    }
}
