import Foundation

/// 把调度出来的间隔说成人话，用在四个评分按钮下面的预览上
/// （「按 Good 会是 6 天后」），这是 Anki 最有用的一个交互。
public enum IntervalFormatter {
    /// 从现在到 `date` 的距离。
    public static func string(from now: Date, to date: Date) -> String {
        string(seconds: date.timeIntervalSince(now))
    }

    public static func string(seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        switch s {
        case ..<60:
            return "<1分"
        case ..<3600:
            return "\(Int((s / 60).rounded()))分"
        case ..<secondsPerDay:
            return "\(Int((s / 3600).rounded()))小时"
        // 三个月以内都按天说。「34天」比「1.1个月」好判断得多，
        // 而按钮预览的全部意义就是让人一眼估出下次什么时候见。
        case ..<(secondsPerDay * 90):
            return "\(Int((s / secondsPerDay).rounded()))天"
        case ..<(secondsPerDay * 365):
            return trimmed(s / (secondsPerDay * 30)) + "个月"
        default:
            return trimmed(s / (secondsPerDay * 365)) + "年"
        }
    }

    /// 1.0 → "1"，1.5 → "1.5"。避免出现「1.0个月」。
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }
}

extension SchedulerProtocol {
    /// 四个按钮各自会把卡片推到多远。纯函数，随便算，不产生副作用。
    public func preview(state: SRSState, now: Date) -> [Rating: String] {
        var result: [Rating: String] = [:]
        for rating in Rating.allCases {
            let next = schedule(state: state, rating: rating, now: now)
            result[rating] = next.dueDate.map { IntervalFormatter.string(from: now, to: $0) } ?? "—"
        }
        return result
    }
}
