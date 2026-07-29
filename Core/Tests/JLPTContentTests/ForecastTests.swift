import XCTest
import SwiftData
@testable import JLPTContent
import JLPTCore

/// 未来负荷预测。
///
/// 这些数字会原样出现在提醒通知里（「明天 23 张」），所以口径必须钉死：
/// 算错了就是每天给用户推一个假数字，比不推更糟。
@MainActor
final class ForecastTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    /// 上午 9 点。当天的学习日在次日凌晨 4 点结束。
    private lazy var now = date(2026, 7, 27, 9)

    private func session(newPerDay: Int = 15, maxReviews: Int = 200) -> ReviewSession {
        ReviewSession(
            queueConfig: DailyQueueConfig(
                newCardsPerDay: newPerDay, maxReviewsPerDay: maxReviews, dayCutoffHour: 4
            ),
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
    private func newCard(_ slug: String) -> ReviewItemEntity {
        let item = ReviewItemEntity(kind: .vocab, contentSlug: slug, level: .n5, srs: .new)
        context.insert(item)
        return item
    }

    @discardableResult
    private func reviewCard(_ slug: String, dueHoursFromNow: Double) -> ReviewItemEntity {
        let srs = SRSState(
            intervalDays: 10,
            repetitions: 3,
            dueDate: now.addingTimeInterval(dueHoursFromNow * 3600),
            stage: .review
        )
        let item = ReviewItemEntity(kind: .vocab, contentSlug: slug, level: .n5, srs: srs)
        context.insert(item)
        return item
    }

    // MARK: - 新卡按额度铺开，并被剩余存量封顶

    func testNewCardsSpreadAcrossDaysAndRunOut() throws {
        for i in 0..<25 { newCard("w\(i)") }
        let load = try session(newPerDay: 10).forecast(days: 4, in: context, now: now)

        XCTAssertEqual(load.map(\.new), [10, 10, 5, 0], "25 张未学按每天 10 张铺，第三天只剩 5 张，第四天没了")
        XCTAssertEqual(load.map(\.due), [0, 0, 0, 0], "没有复习卡")
    }

    func testNewCardQuotaIsNotExceeded() throws {
        for i in 0..<100 { newCard("w\(i)") }
        let load = try session(newPerDay: 15).forecast(days: 3, in: context, now: now)
        XCTAssertEqual(load.map(\.new), [15, 15, 15])
    }

    // MARK: - 过期卡全部算在第一天

    /// 三天没打开积下的卡是「今天的债」，不该分摊到未来。
    func testOverdueCardsAllLandOnDayOne() throws {
        reviewCard("a", dueHoursFromNow: -72)
        reviewCard("b", dueHoursFromNow: -48)
        reviewCard("c", dueHoursFromNow: -1)

        let load = try session(newPerDay: 0).forecast(days: 3, in: context, now: now)
        XCTAssertEqual(load[0].due, 3, "三张过期卡全部归第一天")
        XCTAssertEqual(load[1].due, 0)
        XCTAssertEqual(load[2].due, 0)
    }

    /// 今天晚些时候到期的，也算今天 —— 学习日在次日凌晨 4 点才结束。
    func testCardsDueLaterTodayCountAsToday() throws {
        reviewCard("evening", dueHoursFromNow: 12)   // 27 日 21:00
        reviewCard("lateNight", dueHoursFromNow: 18) // 28 日 03:00，仍在 4 点分界之前

        let load = try session(newPerDay: 0).forecast(days: 2, in: context, now: now)
        XCTAssertEqual(load[0].due, 2)
        XCTAssertEqual(load[1].due, 0)
    }

    func testCardsLandOnTheirOwnDay() throws {
        reviewCard("d1", dueHoursFromNow: 10)   // 今天
        reviewCard("d2", dueHoursFromNow: 30)   // 明天
        reviewCard("d3", dueHoursFromNow: 34)   // 明天
        reviewCard("d4", dueHoursFromNow: 60)   // 后天

        let load = try session(newPerDay: 0).forecast(days: 3, in: context, now: now)
        XCTAssertEqual(load.map(\.due), [1, 2, 1])
    }

    // MARK: - 上限与过滤

    func testDueIsCappedByDailyReviewLimit() throws {
        for i in 0..<50 { reviewCard("r\(i)", dueHoursFromNow: -1) }
        let load = try session(newPerDay: 0, maxReviews: 20).forecast(days: 1, in: context, now: now)
        XCTAssertEqual(load[0].due, 20, "超过每日复习上限的部分不该吓唬用户")
    }

    func testSuspendedCardsAreExcluded() throws {
        let item = reviewCard("dropped", dueHoursFromNow: -1)
        item.isSuspended = true
        reviewCard("kept", dueHoursFromNow: -1)

        let load = try session(newPerDay: 0).forecast(days: 1, in: context, now: now)
        XCTAssertEqual(load[0].due, 1)
    }

    func testLevelFilterApplies() throws {
        let n1 = ReviewItemEntity(kind: .vocab, contentSlug: "hard", level: .n1, srs: .new)
        context.insert(n1)
        for i in 0..<3 { newCard("easy\(i)") }

        let load = try session(newPerDay: 10).forecast(
            days: 1, in: context, now: now, levels: [.n5]
        )
        XCTAssertEqual(load[0].new, 3, "N1 那张不在备考范围内，不该算进来")
    }

    // MARK: - 今日已学的要从第一天额度里扣掉

    func testAlreadyIntroducedTodayReducesDayOneQuota() throws {
        for i in 0..<20 { newCard("w\(i)") }
        // 今天已经引入了 6 张
        let items = try context.fetch(FetchDescriptor<ReviewItemEntity>())
        for item in items.prefix(6) {
            item.introducedAt = now.addingTimeInterval(-3600)
            item.srs = SRSState(intervalDays: 0, repetitions: 1, dueDate: now, stage: .learning)
        }
        try context.save()

        let load = try session(newPerDay: 10).forecast(days: 2, in: context, now: now)
        XCTAssertEqual(load[0].new, 4, "今天额度 10 张，已引入 6 张，只剩 4 张")
        XCTAssertEqual(load[1].new, 10, "明天额度重置")
    }

    // MARK: - 边界

    func testZeroDaysReturnsEmpty() throws {
        newCard("w")
        XCTAssertTrue(try session().forecast(days: 0, in: context, now: now).isEmpty)
    }

    func testEmptyDatabaseGivesZeroLoad() throws {
        let load = try session().forecast(days: 3, in: context, now: now)
        XCTAssertEqual(load.count, 3)
        XCTAssertTrue(load.allSatisfy { $0.total == 0 })
    }

    /// 每一天的 `dayEnd` 必须严格递增，否则排通知会撞在同一时刻。
    func testDayEndsAreStrictlyIncreasing() throws {
        let load = try session().forecast(days: 7, in: context, now: now)
        for (a, b) in zip(load, load.dropFirst()) {
            XCTAssertLessThan(a.dayEnd, b.dayEnd)
        }
    }
}
