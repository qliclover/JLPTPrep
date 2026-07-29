import Foundation

/// 一次复习的历史记录。用于统计，也是将来切 FSRS 时的训练数据 ——
/// FSRS 需要完整的评分序列，所以从第一天就得记全。
public struct ReviewLog: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var itemID: UUID
    public var rating: Rating
    public var reviewedAt: Date
    public var stageBefore: LearningStage
    public var stageAfter: LearningStage
    public var intervalBeforeDays: Int
    public var intervalAfterDays: Int
    public var easeBefore: Double
    public var easeAfter: Double

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        rating: Rating,
        reviewedAt: Date,
        stageBefore: LearningStage,
        stageAfter: LearningStage,
        intervalBeforeDays: Int,
        intervalAfterDays: Int,
        easeBefore: Double,
        easeAfter: Double
    ) {
        self.id = id
        self.itemID = itemID
        self.rating = rating
        self.reviewedAt = reviewedAt
        self.stageBefore = stageBefore
        self.stageAfter = stageAfter
        self.intervalBeforeDays = intervalBeforeDays
        self.intervalAfterDays = intervalAfterDays
        self.easeBefore = easeBefore
        self.easeAfter = easeAfter
    }

    /// 从一次调度的前后状态生成日志。
    public init(itemID: UUID, rating: Rating, at date: Date, before: SRSState, after: SRSState) {
        self.init(
            itemID: itemID,
            rating: rating,
            reviewedAt: date,
            stageBefore: before.stage,
            stageAfter: after.stage,
            intervalBeforeDays: before.intervalDays,
            intervalAfterDays: after.intervalDays,
            easeBefore: before.easeFactor,
            easeAfter: after.easeFactor
        )
    }
}
