import Foundation
import SwiftData
import JLPTCore

/// 用户的复习进度。单词和语法共用这一张表 —— 这正是 PRD 里「一套记忆内核」的落点：
/// 每日队列只查这一张表按 `dueDate` 排序，天然就是混合队列，不用在上层合并两个列表。
///
/// `levelRaw` / `kindRaw` 是从内容表冗余过来的，为了让筛选完全不用 join。
@Model
public final class ReviewItemEntity: Reviewable {
    /// `"vocab#n5-taberu"`。SwiftData 不支持复合唯一键，所以拼成一个字符串。
    @Attribute(.unique) public var key: String
    /// 稳定的业务标识，用来关联 `ReviewLogEntity`。
    public var uuid: UUID
    public var kindRaw: String
    public var contentSlug: String
    public var levelRaw: String
    /// 来源内容包。和 `levelRaw` 一样是从内容表冗余过来的 ——
    /// 队列要按「已启用的包」过滤，冗余在这里就完全不用 join。
    public var packID: String = ""

    // MARK: SRS 状态（对应 Core 的 SRSState，拍平存储以便直接写 Predicate）
    public var easeFactor: Double
    public var intervalDays: Int
    public var repetitions: Int
    public var lapses: Int
    public var dueDate: Date?
    public var stageRaw: String
    public var stepIndex: Int
    /// 连续答对次数。攒够阈值才允许毕业，见 SRSConfig.requiredCorrectToGraduate。
    public var correctStreak: Int = 0
    public var lastReviewedAt: Date?

    // MARK: 用户标记
    /// 第一次被学习的时刻。用来算「今天已经引入了几张新卡」，而不是靠单独计数器 ——
    /// 计数器会在删库重装、跨设备同步时对不上，这个字段是自证的。
    public var introducedAt: Date?
    /// 暂时不想背（如超纲词），彻底不进队列。
    public var isSuspended: Bool
    /// 收藏 / 重点。
    public var isStarred: Bool
    public var createdAt: Date

    public var kind: ReviewItemKind {
        get { ReviewItemKind(rawValue: kindRaw) ?? .vocab }
        set { kindRaw = newValue.rawValue }
    }

    public var level: JLPTLevel {
        get { JLPTLevel(rawValue: levelRaw) ?? .n5 }
        set { levelRaw = newValue.rawValue }
    }

    /// 与 Core 调度器之间的桥。Core 只认这个 struct，完全不知道 SwiftData 的存在。
    public var srs: SRSState {
        get {
            SRSState(
                easeFactor: easeFactor,
                intervalDays: intervalDays,
                repetitions: repetitions,
                lapses: lapses,
                dueDate: dueDate,
                stage: LearningStage(rawValue: stageRaw) ?? .new,
                stepIndex: stepIndex,
                correctStreak: correctStreak,
                lastReviewedAt: lastReviewedAt
            )
        }
        set {
            easeFactor = newValue.easeFactor
            intervalDays = newValue.intervalDays
            repetitions = newValue.repetitions
            lapses = newValue.lapses
            dueDate = newValue.dueDate
            stageRaw = newValue.stage.rawValue
            stepIndex = newValue.stepIndex
            correctStreak = newValue.correctStreak
            lastReviewedAt = newValue.lastReviewedAt
        }
    }

    public static func key(kind: ReviewItemKind, slug: String) -> String {
        "\(kind.rawValue)#\(slug)"
    }

    public init(
        kind: ReviewItemKind,
        contentSlug: String,
        level: JLPTLevel,
        packID: String = "",
        uuid: UUID = UUID(),
        srs: SRSState = .new,
        introducedAt: Date? = nil,
        isSuspended: Bool = false,
        isStarred: Bool = false,
        createdAt: Date = Date()
    ) {
        self.key = Self.key(kind: kind, slug: contentSlug)
        self.uuid = uuid
        self.kindRaw = kind.rawValue
        self.contentSlug = contentSlug
        self.levelRaw = level.rawValue
        self.packID = packID
        self.easeFactor = srs.easeFactor
        self.intervalDays = srs.intervalDays
        self.repetitions = srs.repetitions
        self.lapses = srs.lapses
        self.dueDate = srs.dueDate
        self.stageRaw = srs.stage.rawValue
        self.stepIndex = srs.stepIndex
        self.correctStreak = srs.correctStreak
        self.lastReviewedAt = srs.lastReviewedAt
        self.introducedAt = introducedAt
        self.isSuspended = isSuspended
        self.isStarred = isStarred
        self.createdAt = createdAt
    }
}

/// 复习历史。除了做统计，它还是将来切 FSRS 的训练数据 ——
/// FSRS 要重放完整评分序列，所以从第一天就得记全，事后补不回来。
@Model
public final class ReviewLogEntity {
    /// 稳定标识。撤销要靠它精确删掉刚写的那一条。
    @Attribute(.unique) public var id: UUID
    public var itemUUID: UUID
    public var ratingRaw: Int
    public var reviewedAt: Date
    public var stageBeforeRaw: String
    public var stageAfterRaw: String
    public var intervalBeforeDays: Int
    public var intervalAfterDays: Int
    public var easeBefore: Double
    public var easeAfter: Double

    public var rating: Rating { Rating(rawValue: ratingRaw) ?? .good }

    public init(log: ReviewLog) {
        self.id = log.id
        self.itemUUID = log.itemID
        self.ratingRaw = log.rating.rawValue
        self.reviewedAt = log.reviewedAt
        self.stageBeforeRaw = log.stageBefore.rawValue
        self.stageAfterRaw = log.stageAfter.rawValue
        self.intervalBeforeDays = log.intervalBeforeDays
        self.intervalAfterDays = log.intervalAfterDays
        self.easeBefore = log.easeBefore
        self.easeAfter = log.easeAfter
    }
}

/// 记录某个内容包最近一次导入的指纹，内容没变就整包跳过。
@Model
public final class ImportRecordEntity {
    @Attribute(.unique) public var packID: String
    public var contentHash: String
    public var schemaVersion: Int
    public var importedAt: Date
    public var itemCount: Int

    public init(packID: String, contentHash: String, schemaVersion: Int, importedAt: Date, itemCount: Int) {
        self.packID = packID
        self.contentHash = contentHash
        self.schemaVersion = schemaVersion
        self.importedAt = importedAt
        self.itemCount = itemCount
    }
}
