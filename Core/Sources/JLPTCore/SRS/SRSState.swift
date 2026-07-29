import Foundation

/// 一张可复习卡片的记忆状态。纯值类型，方便单测和将来换算法。
///
/// SwiftData 侧会有一个 `@Model` 镜像它的字段，Core 只认这个 struct，
/// 这样调度逻辑完全不依赖持久化框架。
public struct SRSState: Codable, Equatable, Sendable {
    /// SM-2 的难度因子，越小复习越频繁。下限见 `SRSConfig.minEase`。
    public var easeFactor: Double
    /// 当前间隔（天）。只对 `.review` 阶段有意义；learning 阶段用 `stepIndex`。
    public var intervalDays: Int
    /// 毕业后连续答对的次数，用于 SM-2 的 1天 → 6天 → interval*ease 阶梯。
    public var repetitions: Int
    /// 一共忘掉过多少次（review 阶段按 Again 的次数）。
    public var lapses: Int
    /// 下次到期时间。新卡为 nil。
    public var dueDate: Date?
    public var stage: LearningStage
    /// 在 learning / relearning 步骤数组中的下标。
    public var stepIndex: Int
    /// 连续答对次数。攒够 `SRSConfig.requiredCorrectToGraduate` 才允许毕业进长间隔，
    /// 答错归零 —— 一次蒙对不算学会，选择题有 25% 的瞎猜基线，必须靠重复来滤掉。
    public var correctStreak: Int
    public var lastReviewedAt: Date?

    public init(
        easeFactor: Double = 2.5,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        lapses: Int = 0,
        dueDate: Date? = nil,
        stage: LearningStage = .new,
        stepIndex: Int = 0,
        correctStreak: Int = 0,
        lastReviewedAt: Date? = nil
    ) {
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
        self.dueDate = dueDate
        self.stage = stage
        self.stepIndex = stepIndex
        self.correctStreak = correctStreak
        self.lastReviewedAt = lastReviewedAt
    }

    /// 全新未学的卡片。
    public static var new: SRSState { SRSState() }

    /// 到 `date` 这一刻是否已经到期（新卡永远返回 false，新卡由配额控制而非到期时间）。
    public func isDue(at date: Date) -> Bool {
        guard let dueDate else { return false }
        return dueDate <= date
    }
}

/// 任何能进 SRS 队列的东西（单词、语法点）都实现它。
///
/// 刻意不要求 `id` —— SwiftData 的 `PersistentModel` 已经用 `id` 表示 `PersistentIdentifier`，
/// 再声明一个 `id: UUID` 会撞车。需要标识时由调用方自己提供（见 `ReviewLog.itemID`）。
public protocol Reviewable {
    var srs: SRSState { get set }
}
