import Foundation

/// 把「未来几天的负荷」转成「几点推什么通知」。
///
/// 放在 Core 而不是 App 层，是因为这里有两处最容易写错、又最难在真机上发现的地方：
///
/// 1. **`dayEnd` 是次日凌晨 4 点**（学习日的分界），换算成自然日要往回退一天。
///    弄反了就会把周一的提醒排到周二。
/// 2. **已经过去的时刻不能排**。晚上 9 点打开 App，今天 20:00 那条早过了；
///    照排的话 iOS 会当场触发，用户刚放下手机就收到一条「今天 15 张」。
///
/// 这两条都是「排出来之后要等一天才知道错了」的那种 bug，必须在测试里钉死。
public enum ReminderPlanner {

    public struct Planned: Equatable, Sendable {
        /// 第几天，用来生成稳定的通知标识。
        public var offset: Int
        public var fireDate: Date
        public var body: String
        public var total: Int
    }

    public static func plan(
        loads: [ReviewSession.DayLoad],
        hour: Int,
        minute: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [Planned] {
        loads.enumerated().compactMap { offset, load in
            // 那天没有任何卡就不推 —— 推一条「今天 0 张」纯属骚扰
            guard load.total > 0 else { return nil }
            guard let day = calendar.date(byAdding: .day, value: -1, to: load.dayEnd),
                  let fireDate = calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: day
                  ),
                  fireDate > now
            else { return nil }
            return Planned(
                offset: offset, fireDate: fireDate, body: body(for: load), total: load.total
            )
        }
    }

    /// 通知正文。
    ///
    /// 带上预计时长 —— 「23 张」听着像个任务，「23 张 · 约 4 分钟」听着像顺手就做了。
    /// 每张按 10 秒估，和首页那个估算口径保持一致。
    public static func body(for load: ReviewSession.DayLoad) -> String {
        let minutes = max(1, Int((Double(load.total) * 10 / 60).rounded()))
        var parts = ["\(load.total) 张待办", "约 \(minutes) 分钟"]
        // 两类都有才拆开写；只有一类时「15 张待办 · 15 生词」是废话
        if load.new > 0, load.due > 0 {
            parts.insert("\(load.new) 生词 · \(load.due) 复习", at: 1)
        }
        return parts.joined(separator: " · ")
    }
}
