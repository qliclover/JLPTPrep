import XCTest
@testable import JLPTCore

/// 「同一个词答对三次才算过」这条规则的测试。
///
/// 关键不只是「数到三」，还有**这三次必须分散在时间上**：
/// 十分钟内连答三遍是突击，对长期记忆几乎没贡献。
final class MasteryGateTests: XCTestCase {
    let scheduler = SM2Scheduler()
    let now = Date(timeIntervalSince1970: 1_774_000_000)

    private func answer(_ state: SRSState, _ rating: Rating, after seconds: TimeInterval = 0) -> SRSState {
        scheduler.schedule(state: state, rating: rating, now: now.addingTimeInterval(seconds))
    }

    // MARK: - 计数

    func testCorrectAnswersAccumulate() {
        var state = SRSState.new
        XCTAssertEqual(state.correctStreak, 0)

        state = answer(state, .good)
        XCTAssertEqual(state.correctStreak, 1)
        state = answer(state, .good, after: 60)
        XCTAssertEqual(state.correctStreak, 2)
        state = answer(state, .good, after: 660)
        XCTAssertEqual(state.correctStreak, 3)
    }

    func testWrongAnswerResetsTheStreak() {
        var state = SRSState.new
        state = answer(state, .good)
        state = answer(state, .good, after: 60)
        XCTAssertEqual(state.correctStreak, 2)

        state = answer(state, .again, after: 120)
        XCTAssertEqual(state.correctStreak, 0, "答错就得从头再来 —— 蒙对两次不算学会")
    }

    // MARK: - 毕业门槛

    func testCardCannotGraduateBeforeThreeCorrect() {
        var state = SRSState.new

        state = answer(state, .good)
        XCTAssertEqual(state.stage, .learning, "第一次答对还在巩固期")
        state = answer(state, .good, after: 60)
        XCTAssertEqual(state.stage, .learning, "第二次也是")

        state = answer(state, .good, after: 660)
        XCTAssertEqual(state.stage, .review, "第三次才毕业进长间隔")
        XCTAssertEqual(state.correctStreak, 3)
    }

    /// 三次答对自然落在 1分 → 10分 → 1天 上，不是十分钟内连点三下。
    func testTheThreeCorrectAnswersAreSpreadOverTime() throws {
        var state = SRSState.new
        var elapsed: TimeInterval = 0

        state = answer(state, .good, after: elapsed)
        XCTAssertEqual(try XCTUnwrap(state.dueDate).timeIntervalSince(now), 600, accuracy: 1, "第一次答对后 10 分钟再见")

        elapsed = 600
        state = answer(state, .good, after: elapsed)
        XCTAssertEqual(
            try XCTUnwrap(state.dueDate).timeIntervalSince(now), elapsed + secondsPerDay, accuracy: 1,
            "第二次答对后要隔一天 —— 这是防突击的关键一步"
        )

        elapsed += secondsPerDay
        state = answer(state, .good, after: elapsed)
        XCTAssertEqual(state.stage, .review)
        XCTAssertEqual(state.intervalDays, 1)
    }

    func testFailingMidwayRestartsTheCount() {
        var state = SRSState.new
        state = answer(state, .good)
        state = answer(state, .good, after: 600)
        XCTAssertEqual(state.correctStreak, 2)

        state = answer(state, .again, after: 700)
        XCTAssertEqual(state.stepIndex, 0, "答错回到第一步")

        // 还得重新攒三次
        state = answer(state, .good, after: 800)
        state = answer(state, .good, after: 900)
        XCTAssertEqual(state.stage, .learning, "只攒了两次，还不能毕业")
        state = answer(state, .good, after: 1000)
        XCTAssertEqual(state.stage, .review)
    }

    /// Easy 也不能跳过门槛：选择题里根本没有「简单」这个档，
    /// 但四键模式还在，不该给它开后门。
    func testEasyDoesNotBypassTheGate() {
        var state = SRSState.new
        state = answer(state, .easy)
        XCTAssertEqual(state.stage, .learning, "一次 Easy 不能直接毕业")
        XCTAssertEqual(state.correctStreak, 1)

        state = answer(state, .easy, after: 600)
        state = answer(state, .easy, after: 1200)
        XCTAssertEqual(state.stage, .review, "攒够三次才行")
    }

    // MARK: - 阈值可配

    func testThresholdIsConfigurable() {
        let lenient = SM2Scheduler(config: SRSConfig(
            requiredCorrectToGraduate: 1,
            learningSteps: [60]
        ))
        let state = lenient.schedule(state: .new, rating: .good, now: now)
        XCTAssertEqual(state.stage, .review, "阈值设成 1 就该一次毕业")
    }

    func testHigherThresholdRepeatsTheLastStep() {
        // 阈值 5 但只有 3 个步骤：走完步骤后停在最后一步重复，直到攒够
        let strict = SM2Scheduler(config: SRSConfig(requiredCorrectToGraduate: 5))
        var state = SRSState.new
        for _ in 0..<4 {
            state = strict.schedule(state: state, rating: .good, now: now)
            XCTAssertEqual(state.stage, .learning)
        }
        state = strict.schedule(state: state, rating: .good, now: now)
        XCTAssertEqual(state.stage, .review)
        XCTAssertEqual(state.correctStreak, 5)
    }

    // MARK: - 回炉不受门槛限制

    /// 已经学会又忘掉的卡，重新攒三次会把复习队列撑爆。
    func testRelearningGraduatesWithoutTheGate() {
        var state = SRSState(
            intervalDays: 20, repetitions: 5,
            dueDate: now, stage: .review, correctStreak: 8
        )
        state = answer(state, .again)
        XCTAssertEqual(state.stage, .relearning)
        XCTAssertEqual(state.correctStreak, 0)

        state = answer(state, .good, after: 600)
        XCTAssertEqual(state.stage, .review, "回炉答对一次就能回去，不用重攒三次")
    }
}
