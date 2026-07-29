import XCTest
@testable import JLPTCore

final class SM2SchedulerTests: XCTestCase {
    let scheduler = SM2Scheduler()
    let now = Date(timeIntervalSince1970: 1_774_000_000)  // 固定时刻，避免测试依赖系统时钟

    private func reviewState(interval: Int, ease: Double = 2.5, repetitions: Int = 3, lapses: Int = 0) -> SRSState {
        SRSState(
            easeFactor: ease,
            intervalDays: interval,
            repetitions: repetitions,
            lapses: lapses,
            dueDate: now,
            stage: .review
        )
    }

    private func assertDue(_ state: SRSState, secondsFromNow: TimeInterval, line: UInt = #line) {
        guard let due = state.dueDate else { return XCTFail("dueDate 为 nil", line: line) }
        XCTAssertEqual(due.timeIntervalSince(now), secondsFromNow, accuracy: 0.5, line: line)
    }

    private func assertDue(_ state: SRSState, daysFromNow: Int, line: UInt = #line) {
        assertDue(state, secondsFromNow: Double(daysFromNow) * secondsPerDay, line: line)
    }

    // MARK: - 新卡：learning steps

    func testNewCardGoodAdvancesToSecondStep() {
        let s = scheduler.schedule(state: .new, rating: .good, now: now)
        XCTAssertEqual(s.stage, .learning)
        XCTAssertEqual(s.stepIndex, 1)
        assertDue(s, secondsFromNow: 600)
        XCTAssertEqual(s.easeFactor, 2.5, "learning 阶段不应改动 ease")
    }

    func testNewCardGraduatesAfterAllSteps() {
        // 三个学习步骤 = 要答对三次才毕业（见 MasteryGateTests）
        var s = scheduler.schedule(state: .new, rating: .good, now: now)
        s = scheduler.schedule(state: s, rating: .good, now: now)
        XCTAssertEqual(s.stage, .learning, "才两次，还不能毕业")

        s = scheduler.schedule(state: s, rating: .good, now: now)
        XCTAssertEqual(s.stage, .review)
        XCTAssertEqual(s.intervalDays, 1)
        XCTAssertEqual(s.repetitions, 1)
        XCTAssertEqual(s.stepIndex, 0)
        assertDue(s, daysFromNow: 1)
    }

    func testAgainInLearningResetsToFirstStep() {
        var s = scheduler.schedule(state: .new, rating: .good, now: now)
        XCTAssertEqual(s.stepIndex, 1)
        s = scheduler.schedule(state: s, rating: .again, now: now)
        XCTAssertEqual(s.stage, .learning)
        XCTAssertEqual(s.stepIndex, 0)
        assertDue(s, secondsFromNow: 60)
        XCTAssertEqual(s.lapses, 0, "learning 阶段的 Again 不算 lapse")
    }

    func testHardInLearningRepeatsCurrentStep() {
        var s = scheduler.schedule(state: .new, rating: .good, now: now)  // stepIndex 1
        s = scheduler.schedule(state: s, rating: .hard, now: now)
        XCTAssertEqual(s.stepIndex, 1)
        assertDue(s, secondsFromNow: 600)
    }

    /// Easy 不再是「一步登天」：答对次数的门槛对它同样生效。
    /// 攒够之后它才兑现自己的奖励间隔。
    func testEasyRespectsTheMasteryGateThenGivesItsBonus() {
        var s = scheduler.schedule(state: .new, rating: .easy, now: now)
        XCTAssertEqual(s.stage, .learning, "一次 Easy 不能直接毕业")

        s = scheduler.schedule(state: s, rating: .easy, now: now)
        s = scheduler.schedule(state: s, rating: .easy, now: now)
        XCTAssertEqual(s.stage, .review)
        XCTAssertEqual(s.intervalDays, 4, "毕业时 Easy 仍然给 4 天而不是 1 天")
        XCTAssertEqual(s.repetitions, 1)
        assertDue(s, daysFromNow: 4)
    }

    func testEmptyLearningStepsGraduateImmediately() {
        let s = SM2Scheduler(config: SRSConfig(learningSteps: []))
            .schedule(state: .new, rating: .good, now: now)
        XCTAssertEqual(s.stage, .review)
        XCTAssertEqual(s.intervalDays, 1)
    }

    // MARK: - review 阶段的间隔演进

    func testGoodLadderOneSixThenEaseMultiplier() {
        var s = reviewState(interval: 1, repetitions: 1)
        s = scheduler.schedule(state: s, rating: .good, now: now)
        XCTAssertEqual(s.intervalDays, 6)
        XCTAssertEqual(s.repetitions, 2)

        s = scheduler.schedule(state: s, rating: .good, now: now)
        XCTAssertEqual(s.intervalDays, 15)  // 6 × 2.5
        XCTAssertEqual(s.repetitions, 3)

        s = scheduler.schedule(state: s, rating: .good, now: now)
        XCTAssertEqual(s.intervalDays, 38)  // 15 × 2.5 = 37.5 → 38
        XCTAssertEqual(s.easeFactor, 2.5, "Good 不改 ease")
        assertDue(s, daysFromNow: 38)
    }

    func testHardShrinksEaseAndUses1_2Multiplier() {
        let s = scheduler.schedule(state: reviewState(interval: 15), rating: .hard, now: now)
        XCTAssertEqual(s.easeFactor, 2.35, accuracy: 1e-9)
        XCTAssertEqual(s.intervalDays, 18)  // 15 × 1.2
        assertDue(s, daysFromNow: 18)
    }

    func testEasyRaisesEaseAndAppliesBonus() {
        let s = scheduler.schedule(state: reviewState(interval: 15), rating: .easy, now: now)
        XCTAssertEqual(s.easeFactor, 2.65, accuracy: 1e-9)
        XCTAssertEqual(s.intervalDays, 52)  // 15 × 2.65 × 1.3 = 51.675 → 52
    }

    func testIntervalAlwaysGrowsOnSuccess() {
        // 1 × 1.2 = 1.2 → 四舍五入还是 1，会让卡片永远卡在 1 天。必须至少 +1。
        let s = scheduler.schedule(state: reviewState(interval: 1), rating: .hard, now: now)
        XCTAssertEqual(s.intervalDays, 2)
    }

    // MARK: - 忘掉与回炉

    func testAgainInReviewLapsesIntoRelearning() {
        let before = reviewState(interval: 15, lapses: 2)
        let s = scheduler.schedule(state: before, rating: .again, now: now)
        XCTAssertEqual(s.stage, .relearning)
        XCTAssertEqual(s.lapses, 3)
        XCTAssertEqual(s.repetitions, 0)
        XCTAssertEqual(s.easeFactor, 2.30, accuracy: 1e-9)
        XCTAssertEqual(s.intervalDays, 1, "lapse 后间隔归 1 天")
        XCTAssertEqual(s.stepIndex, 0)
        assertDue(s, secondsFromNow: 600)
    }

    func testRelearningGoodReturnsToReview() {
        var s = scheduler.schedule(state: reviewState(interval: 15), rating: .again, now: now)
        s = scheduler.schedule(state: s, rating: .good, now: now)
        XCTAssertEqual(s.stage, .review)
        XCTAssertEqual(s.intervalDays, 1)
        XCTAssertEqual(s.repetitions, 1)
        assertDue(s, daysFromNow: 1)
    }

    func testRelearningAgainStaysInRelearning() {
        var s = scheduler.schedule(state: reviewState(interval: 15), rating: .again, now: now)
        s = scheduler.schedule(state: s, rating: .again, now: now)
        XCTAssertEqual(s.stage, .relearning)
        XCTAssertEqual(s.lapses, 1, "回炉期间再按 Again 不重复计 lapse")
        assertDue(s, secondsFromNow: 600)
    }

    func testRelearningEasyGetsBonusInterval() {
        var s = scheduler.schedule(state: reviewState(interval: 15), rating: .again, now: now)
        s = scheduler.schedule(state: s, rating: .easy, now: now)
        XCTAssertEqual(s.stage, .review)
        XCTAssertEqual(s.intervalDays, 4)
    }

    // MARK: - 边界

    func testEaseNeverDropsBelowFloor() {
        var s = reviewState(interval: 10, ease: 1.4)
        s = scheduler.schedule(state: s, rating: .again, now: now)
        XCTAssertEqual(s.easeFactor, 1.3, accuracy: 1e-9)

        // 已经在下限了，再扣也不动
        var r = reviewState(interval: 10, ease: 1.3)
        r = scheduler.schedule(state: r, rating: .hard, now: now)
        XCTAssertEqual(r.easeFactor, 1.3, accuracy: 1e-9)
    }

    func testIntervalClampedToMax() {
        let capped = SM2Scheduler(config: SRSConfig(maxIntervalDays: 10))
        let s = capped.schedule(state: reviewState(interval: 8), rating: .good, now: now)
        XCTAssertEqual(s.intervalDays, 10)  // 8 × 2.5 = 20，被削到 10
    }

    func testScheduleIsPureAndStampsReviewTime() {
        let before = reviewState(interval: 15)
        let after = scheduler.schedule(state: before, rating: .good, now: now)
        XCTAssertEqual(before.intervalDays, 15, "入参不应被改动")
        XCTAssertNil(before.lastReviewedAt)
        XCTAssertEqual(after.lastReviewedAt, now)
    }

    func testEveryRatingProducesAFutureDueDate() {
        let states: [SRSState] = [.new, reviewState(interval: 1, repetitions: 1), reviewState(interval: 30)]
        for state in states {
            for rating in Rating.allCases {
                let s = scheduler.schedule(state: state, rating: rating, now: now)
                guard let due = s.dueDate else { return XCTFail("\(state.stage)/\(rating) 没有到期时间") }
                XCTAssertGreaterThan(due, now, "\(state.stage)/\(rating) 的到期时间必须在未来")
                XCTAssertGreaterThanOrEqual(s.intervalDays, 0)
            }
        }
    }

    // MARK: - ReviewLog

    func testReviewLogCapturesBeforeAndAfter() {
        let id = UUID()
        let before = reviewState(interval: 15)
        let after = scheduler.schedule(state: before, rating: .hard, now: now)
        let log = ReviewLog(itemID: id, rating: .hard, at: now, before: before, after: after)

        XCTAssertEqual(log.itemID, id)
        XCTAssertEqual(log.intervalBeforeDays, 15)
        XCTAssertEqual(log.intervalAfterDays, 18)
        XCTAssertEqual(log.easeBefore, 2.5)
        XCTAssertEqual(log.easeAfter, 2.35, accuracy: 1e-9)
        XCTAssertEqual(log.stageBefore, .review)
        XCTAssertEqual(log.stageAfter, .review)
    }
}
