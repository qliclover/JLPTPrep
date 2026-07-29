import XCTest
@testable import JLPTCore

private struct TestCard: Reviewable {
    var id = UUID()
    var label: String
    var srs: SRSState
}

final class DailyQueueBuilderTests: XCTestCase {
    /// 固定 UTC 日历，跨天边界的断言才不会随本机时区飘。
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func builder(
        newPerDay: Int = 15,
        maxReviews: Int = 200,
        order: NewCardOrder = .mixed
    ) -> DailyQueueBuilder {
        DailyQueueBuilder(
            config: DailyQueueConfig(
                newCardsPerDay: newPerDay,
                maxReviewsPerDay: maxReviews,
                dayCutoffHour: 4,
                newCardOrder: order
            ),
            calendar: calendar
        )
    }

    private func newCard(_ label: String) -> TestCard {
        TestCard(label: label, srs: .new)
    }

    private func reviewCard(_ label: String, due: Date) -> TestCard {
        TestCard(label: label, srs: SRSState(intervalDays: 10, repetitions: 3, dueDate: due, stage: .review))
    }

    private func learningCard(_ label: String, due: Date) -> TestCard {
        TestCard(label: label, srs: SRSState(dueDate: due, stage: .learning, stepIndex: 1))
    }

    // MARK: - 学习日边界

    func testDayEndIsNextCutoffHour() {
        let b = builder()
        // 早上 9 点 → 学习日结束于明天凌晨 4 点
        XCTAssertEqual(b.dayEnd(after: date(2026, 7, 27, 9)), date(2026, 7, 28, 4))
        // 凌晨 2 点（还算前一天）→ 结束于今天凌晨 4 点
        XCTAssertEqual(b.dayEnd(after: date(2026, 7, 27, 2)), date(2026, 7, 27, 4))
        // 正好 4 点 → 已进入新的一天
        XCTAssertEqual(b.dayEnd(after: date(2026, 7, 27, 4)), date(2026, 7, 28, 4))
    }

    func testReviewDueLaterTodayIsAvailableNow() {
        let now = date(2026, 7, 27, 9)
        let cards = [
            reviewCard("今晚到期", due: date(2026, 7, 27, 23)),
            reviewCard("凌晨到期", due: date(2026, 7, 28, 3)),   // 仍在本学习日内
            reviewCard("明天到期", due: date(2026, 7, 28, 10)),  // 跨过 cutoff，不该出现
            reviewCard("早就过期", due: date(2026, 7, 20, 8)),
        ]
        let q = builder(newPerDay: 0).build(items: cards, now: now)
        XCTAssertEqual(q.review.map(\.label), ["早就过期", "今晚到期", "凌晨到期"], "按到期时间排序，且不含明天的卡")
    }

    func testLearningCardsOnlyWhenTheMinuteHasArrived() {
        let now = date(2026, 7, 27, 9)
        let cards = [
            learningCard("刚到点", due: date(2026, 7, 27, 8, 55)),
            learningCard("还没到", due: date(2026, 7, 27, 9, 30)),
        ]
        let q = builder(newPerDay: 0).build(items: cards, now: now)
        XCTAssertEqual(q.learning.map(\.label), ["刚到点"])
    }

    func testLearningCardsAlwaysComeFirst() {
        let now = date(2026, 7, 27, 9)
        let cards = [
            reviewCard("r1", due: date(2026, 7, 26, 9)),
            learningCard("l1", due: date(2026, 7, 27, 8)),
            newCard("n1"),
        ]
        let q = builder().build(items: cards, now: now)
        XCTAssertEqual(q.ordered.first?.label, "l1")
        XCTAssertEqual(q.count, 3)
    }

    // MARK: - 配额

    func testNewCardQuotaIsReducedByWhatWasAlreadyDoneToday() {
        let now = date(2026, 7, 27, 9)
        let cards = (1...20).map { newCard("n\($0)") }

        let full = builder(newPerDay: 15).build(items: cards, now: now)
        XCTAssertEqual(full.new.count, 15)

        let partial = builder(newPerDay: 15).build(items: cards, now: now, newCardsIntroducedToday: 5)
        XCTAssertEqual(partial.new.count, 10)

        let exhausted = builder(newPerDay: 15).build(items: cards, now: now, newCardsIntroducedToday: 40)
        XCTAssertEqual(exhausted.new.count, 0, "超额也不能算成负数")
    }

    func testReviewCapKeepsTheOldestDueCards() {
        let now = date(2026, 7, 27, 9)
        // 到期时间递减，越靠后的越旧
        let cards = (1...300).map { i in
            reviewCard("r\(i)", due: date(2026, 7, 27, 0).addingTimeInterval(-Double(i) * 60))
        }
        let q = builder(newPerDay: 0, maxReviews: 200).build(items: cards, now: now)
        XCTAssertEqual(q.review.count, 200)
        XCTAssertEqual(q.review.first?.label, "r300", "最早到期的排最前")
        XCTAssertEqual(q.review.last?.label, "r101")
    }

    func testNewCardsAreNotSubjectToDueDate() {
        let q = builder().build(items: [newCard("n1")], now: date(2026, 7, 27, 9))
        XCTAssertEqual(q.new.count, 1)
        XCTAssertFalse(SRSState.new.isDue(at: date(2026, 7, 27, 9)), "新卡没有到期时间，靠配额出队")
    }

    // MARK: - 出卡顺序

    func testMixedOrderSpreadsNewCardsAcrossReviews() {
        let now = date(2026, 7, 27, 9)
        let reviews = (1...4).map { i in
            reviewCard("r\(i)", due: date(2026, 7, 26, 0).addingTimeInterval(Double(i) * 60))
        }
        let news = [newCard("n1"), newCard("n2")]
        let q = builder(newPerDay: 2, order: .mixed).build(items: reviews + news, now: now)
        XCTAssertEqual(q.ordered.map(\.label), ["n1", "r1", "r2", "n2", "r3", "r4"])
    }

    func testExplicitOrderings() {
        let now = date(2026, 7, 27, 9)
        let items = [reviewCard("r1", due: date(2026, 7, 26, 9)), newCard("n1")]

        XCTAssertEqual(
            builder(order: .beforeReviews).build(items: items, now: now).ordered.map(\.label),
            ["n1", "r1"]
        )
        XCTAssertEqual(
            builder(order: .afterReviews).build(items: items, now: now).ordered.map(\.label),
            ["r1", "n1"]
        )
    }

    func testInterleaveHandlesLopsidedInputs() {
        XCTAssertEqual(DailyQueueBuilder.interleave([1, 2, 3], []), [1, 2, 3])
        XCTAssertEqual(DailyQueueBuilder.interleave([], [1, 2]), [1, 2])
        XCTAssertEqual(DailyQueueBuilder.interleave(["r"], ["a", "b", "c"]).count, 4)
        // 新卡多于复习卡时，多出来的接在尾部，一张都不能丢
        XCTAssertEqual(Set(DailyQueueBuilder.interleave(["r"], ["a", "b", "c"])), ["r", "a", "b", "c"])
    }

    func testEmptyQueue() {
        let q = builder().build(items: [TestCard](), now: date(2026, 7, 27, 9))
        XCTAssertTrue(q.isEmpty)
    }

    // MARK: - 与调度器串起来

    func testCardScheduledForTomorrowLeavesTodaysQueue() {
        let now = date(2026, 7, 27, 9)
        let scheduler = SM2Scheduler()
        var card = reviewCard("r1", due: date(2026, 7, 27, 8))

        XCTAssertEqual(builder(newPerDay: 0).build(items: [card], now: now).review.count, 1)

        card.srs = scheduler.schedule(state: card.srs, rating: .good, now: now)
        XCTAssertEqual(builder(newPerDay: 0).build(items: [card], now: now).review.count, 0, "答完就该离开今天的队列")

        // 但短期巩固的卡 10 分钟后要回来
        var fresh = newCard("n1")
        fresh.srs = scheduler.schedule(state: fresh.srs, rating: .good, now: now)
        XCTAssertEqual(builder().build(items: [fresh], now: now).learning.count, 0)
        XCTAssertEqual(builder().build(items: [fresh], now: now.addingTimeInterval(601)).learning.count, 1)
    }
}
