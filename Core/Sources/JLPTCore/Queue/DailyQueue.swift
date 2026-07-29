import Foundation

/// 新卡插入位置。默认 `.mixed`：把新卡均匀撒进复习卡里，
/// 避免"开头连着 15 张生词"那种劝退开局。
public enum NewCardOrder: String, CaseIterable, Sendable {
    case mixed
    case beforeReviews
    case afterReviews
}

public struct DailyQueueConfig: Equatable, Sendable {
    /// 每天引入的新卡上限。
    public var newCardsPerDay: Int
    /// 每天复习卡上限，防止长假回来被 800 张淹没。
    public var maxReviewsPerDay: Int
    /// "一天"的分界小时。凌晨 4 点前算前一天，跟 Anki 一致 —— 熬夜刷卡不该算成第二天的额度。
    public var dayCutoffHour: Int
    public var newCardOrder: NewCardOrder

    public init(
        newCardsPerDay: Int = 15,
        maxReviewsPerDay: Int = 200,
        dayCutoffHour: Int = 4,
        newCardOrder: NewCardOrder = .mixed
    ) {
        self.newCardsPerDay = newCardsPerDay
        self.maxReviewsPerDay = maxReviewsPerDay
        self.dayCutoffHour = dayCutoffHour
        self.newCardOrder = newCardOrder
    }
}

/// 某一刻算出来的当日学习队列。
public struct DailyQueue<Item> {
    /// 已经到点的 learning / relearning 卡（分钟级，必须现在做）。
    public let learning: [Item]
    /// 今天到期的复习卡（已按配额裁剪）。
    public let review: [Item]
    /// 今天配额内的新卡。
    public let new: [Item]
    /// 实际出卡顺序。
    public let ordered: [Item]

    public var isEmpty: Bool { ordered.isEmpty }
    public var count: Int { ordered.count }

    public init(learning: [Item], review: [Item], new: [Item], ordered: [Item]) {
        self.learning = learning
        self.review = review
        self.new = new
        self.ordered = ordered
    }
}
