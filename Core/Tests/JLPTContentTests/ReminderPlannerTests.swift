import XCTest
@testable import JLPTContent
import JLPTCore

/// 提醒排程。
///
/// 这里排出来的东西会出现在用户的通知栏里，而且错了要等一整天才能发现 ——
/// 「周一的提醒排到了周二」这种 bug，真机上跑一次是看不出来的。
final class ReminderPlannerTests: XCTestCase {

    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// 构造一天的负荷。`dayEnd` 传的是**次日凌晨 4 点** —— 学习日的分界。
    private func load(dayEnd: Date, due: Int = 0, new: Int = 0) -> ReviewSession.DayLoad {
        ReviewSession.DayLoad(dayEnd: dayEnd, due: due, new: new)
    }

    // MARK: - 日期换算

    /// `dayEnd = 7/29 04:00` 代表的是 **7/28 那一天**，提醒该排在 7/28 20:00。
    func testDayEndMapsBackToTheCorrectCalendarDay() {
        let plan = ReminderPlanner.plan(
            loads: [load(dayEnd: date(2026, 7, 29, 4), new: 15)],
            hour: 20, minute: 0,
            now: date(2026, 7, 28, 9),
            calendar: calendar
        )
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].fireDate, date(2026, 7, 28, 20), "排到了错误的自然日")
    }

    func testConsecutiveDaysMapToConsecutiveFireDates() {
        let loads = (0..<3).map { offset in
            load(dayEnd: date(2026, 7, 29 + offset, 4), new: 10)
        }
        let plan = ReminderPlanner.plan(
            loads: loads, hour: 20, minute: 30,
            now: date(2026, 7, 28, 9), calendar: calendar
        )
        XCTAssertEqual(plan.map(\.fireDate), [
            date(2026, 7, 28, 20, 30),
            date(2026, 7, 29, 20, 30),
            date(2026, 7, 30, 20, 30),
        ])
        XCTAssertEqual(plan.map(\.offset), [0, 1, 2], "标识用的 offset 要和天序一致")
    }

    // MARK: - 已过去的时刻不排

    /// 晚上 9 点打开 App，今天 20:00 那条早过了。照排的话 iOS 会当场触发。
    func testPastFireTimeIsSkipped() {
        let loads = [
            load(dayEnd: date(2026, 7, 29, 4), new: 15),   // 今天，20:00 已过
            load(dayEnd: date(2026, 7, 30, 4), new: 15),   // 明天
        ]
        let plan = ReminderPlanner.plan(
            loads: loads, hour: 20, minute: 0,
            now: date(2026, 7, 28, 21), calendar: calendar
        )
        XCTAssertEqual(plan.count, 1, "今天那条该跳过")
        XCTAssertEqual(plan[0].fireDate, date(2026, 7, 29, 20))
        XCTAssertEqual(plan[0].offset, 1, "跳过之后 offset 仍是原来那天的序号")
    }

    /// 刚好卡在提醒时刻上：已经到点就算过去了，不再排。
    func testExactlyAtFireTimeIsSkipped() {
        let plan = ReminderPlanner.plan(
            loads: [load(dayEnd: date(2026, 7, 29, 4), new: 15)],
            hour: 20, minute: 0,
            now: date(2026, 7, 28, 20), calendar: calendar
        )
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - 空的日子不推

    func testDaysWithNothingDueAreSkipped() {
        let loads = [
            load(dayEnd: date(2026, 7, 29, 4), new: 5),
            load(dayEnd: date(2026, 7, 30, 4)),              // 空
            load(dayEnd: date(2026, 7, 31, 4), due: 3),
        ]
        let plan = ReminderPlanner.plan(
            loads: loads, hour: 20, minute: 0,
            now: date(2026, 7, 28, 9), calendar: calendar
        )
        XCTAssertEqual(plan.count, 2, "空的那天不该推「今天 0 张」")
        XCTAssertEqual(plan.map(\.offset), [0, 2])
    }

    // MARK: - 文案

    func testBodyShowsTotalAndEstimatedMinutes() {
        let text = ReminderPlanner.body(for: load(dayEnd: .now, new: 18))
        XCTAssertTrue(text.contains("18 张待办"), text)
        XCTAssertTrue(text.contains("约 3 分钟"), text)
    }

    /// 生词和复习都有时才拆开写；只有一类时拆开是废话。
    func testBodySplitsOnlyWhenBothKindsPresent() {
        let mixed = ReminderPlanner.body(for: load(dayEnd: .now, due: 8, new: 15))
        XCTAssertTrue(mixed.contains("15 生词 · 8 复习"), mixed)

        let newOnly = ReminderPlanner.body(for: load(dayEnd: .now, new: 15))
        XCTAssertFalse(newOnly.contains("生词 ·"), "只有一类时不该拆：\(newOnly)")
    }

    /// 一张卡也要显示「约 1 分钟」，不能出现「约 0 分钟」。
    func testMinutesNeverRoundsToZero() {
        let text = ReminderPlanner.body(for: load(dayEnd: .now, due: 1))
        XCTAssertTrue(text.contains("约 1 分钟"), text)
    }

    func testEmptyInputGivesEmptyPlan() {
        XCTAssertTrue(ReminderPlanner.plan(
            loads: [], hour: 20, minute: 0, now: .now, calendar: calendar
        ).isEmpty)
    }
}
