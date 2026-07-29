import Foundation

/// 把"所有卡片"筛成"今天该做的卡片"。纯函数，时间和日历都从外面注入，方便测跨天边界。
public struct DailyQueueBuilder {
    public var config: DailyQueueConfig
    public var calendar: Calendar

    public init(config: DailyQueueConfig = DailyQueueConfig(), calendar: Calendar = .current) {
        self.config = config
        self.calendar = calendar
    }

    /// `now` 所属的这个"学习日"的结束时刻（下一个 `dayCutoffHour`）。
    /// 到期时间早于它的复习卡，今天都该做 —— 这样晚上 23:00 到期的卡早上就能刷掉，
    /// 而不是逼你等到晚上。
    public func dayEnd(after now: Date) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = config.dayCutoffHour
        comps.minute = 0
        comps.second = 0
        guard let cutoffToday = calendar.date(from: comps) else { return now }
        if cutoffToday > now { return cutoffToday }
        return calendar.date(byAdding: .day, value: 1, to: cutoffToday) ?? cutoffToday
    }

    /// - Parameter newCardsIntroducedToday: 今天已经引入过的新卡数，用来扣减配额。
    public func build<Item: Reviewable>(
        items: [Item],
        now: Date,
        newCardsIntroducedToday: Int = 0
    ) -> DailyQueue<Item> {
        let horizon = dayEnd(after: now)

        var learning: [Item] = []
        var review: [Item] = []
        var fresh: [Item] = []

        for item in items {
            switch item.srs.stage {
            case .new:
                fresh.append(item)
            case .learning, .relearning:
                // 分钟级步骤：只有真到点了才出，不能提前拉进来。
                if let due = item.srs.dueDate, due <= now { learning.append(item) }
            case .review:
                if let due = item.srs.dueDate, due < horizon { review.append(item) }
            }
        }

        learning.sort { ($0.srs.dueDate ?? .distantPast) < ($1.srs.dueDate ?? .distantPast) }
        review.sort { ($0.srs.dueDate ?? .distantPast) < ($1.srs.dueDate ?? .distantPast) }

        review = Array(review.prefix(max(0, config.maxReviewsPerDay)))
        let quota = max(0, config.newCardsPerDay - newCardsIntroducedToday)
        fresh = Array(fresh.prefix(quota))

        let tail: [Item] = switch config.newCardOrder {
        case .mixed: Self.interleave(review, fresh)
        case .beforeReviews: fresh + review
        case .afterReviews: review + fresh
        }

        return DailyQueue(learning: learning, review: review, new: fresh, ordered: learning + tail)
    }

    /// 把 `news` 均匀铺进 `reviews` 之间。
    static func interleave<T>(_ reviews: [T], _ news: [T]) -> [T] {
        guard !news.isEmpty else { return reviews }
        guard !reviews.isEmpty else { return news }

        let gap = Double(reviews.count) / Double(news.count)
        var out: [T] = []
        out.reserveCapacity(reviews.count + news.count)
        var n = 0
        for (i, r) in reviews.enumerated() {
            while n < news.count, Double(n) * gap <= Double(i) {
                out.append(news[n])
                n += 1
            }
            out.append(r)
        }
        out.append(contentsOf: news[n...])
        return out
    }
}
