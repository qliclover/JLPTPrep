import Foundation
import SwiftData
import JLPTCore

/// 数据库与 Core 调度器之间的胶水：取今天的队列、给卡片打分、记日志。
/// UI 层只跟它打交道，不直接碰 `SM2Scheduler` 也不直接写 SwiftData。
public struct ReviewSession {
    public var scheduler: any SchedulerProtocol
    public var queueConfig: DailyQueueConfig
    public var calendar: Calendar

    public init(
        scheduler: any SchedulerProtocol = SM2Scheduler(),
        queueConfig: DailyQueueConfig = DailyQueueConfig(),
        calendar: Calendar = .current
    ) {
        self.scheduler = scheduler
        self.queueConfig = queueConfig
        self.calendar = calendar
    }

    private var builder: DailyQueueBuilder {
        DailyQueueBuilder(config: queueConfig, calendar: calendar)
    }

    // MARK: - 取队列

    /// 今天该做的卡。
    ///
    /// - Parameters:
    ///   - kinds: 只要单词、只要语法，或两者混合。
    ///   - levels: 等级过滤；nil = 不限。考 N4 时传 `JLPTLevel.n4.cumulativeScope`。
    ///   - packIDs: 只出这些包里的卡；nil = 不限。停用一个包就是把它从这里摘掉，
    ///     卡片的进度一点不动 —— 重新启用时接着背。
    ///
    /// 实现上先用 Predicate 滤掉 suspended，剩下的筛选放内存里做。
    /// N5+N4 满打满算 1500 张卡，全量取出是微秒级；而 SwiftData 的 Predicate
    /// 一旦涉及可选 Date 比较和集合 contains 就很容易编译不过或行为诡异，不值得赌。
    public func todayQueue(
        in context: ModelContext,
        now: Date = Date(),
        kinds: Set<ReviewItemKind> = Set(ReviewItemKind.allCases),
        levels: Set<JLPTLevel>? = nil,
        packIDs: Set<String>? = nil
    ) throws -> DailyQueue<ReviewItemEntity> {
        let all = try context.fetch(
            FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.isSuspended == false })
        )
        let candidates = all
            .filter { item in
                guard kinds.contains(item.kind) else { return false }
                if let levels, !levels.contains(item.level) { return false }
                // 用户自己收的生词不属于任何词库包，永远跟着走
                if let packIDs, !item.packID.isEmpty, !packIDs.contains(item.packID) { return false }
                return true
            }
            // 新加进来的排前面。新卡受每日额度限制，不排序的话，
            // 你刚从书里收的生词会排在整个词库后面，几天都轮不到 ——
            // 而刚遇到它的那一刻正是学它最好的时机。
            // （复习卡和巩固卡在下游按到期时间排序，这里的顺序不影响它们。）
            .sorted { $0.createdAt > $1.createdAt }
        let introduced = try newCardsIntroduced(in: context, now: now)
        return builder.build(items: candidates, now: now, newCardsIntroducedToday: introduced)
    }

    /// 本学习日已经引入了多少张新卡。直接数 `introducedAt` 落在今天的记录，
    /// 不维护额外的计数器 —— 计数器在重装、回滚、跨设备同步后必然对不上。
    public func newCardsIntroduced(in context: ModelContext, now: Date = Date()) throws -> Int {
        let end = builder.dayEnd(after: now)
        let start = calendar.date(byAdding: .day, value: -1, to: end) ?? end.addingTimeInterval(-secondsPerDay)
        let items = try context.fetch(
            FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.introducedAt != nil })
        )
        return items.count { item in
            guard let at = item.introducedAt else { return false }
            return at >= start && at < end
        }
    }

    // MARK: - 打分

    @discardableResult
    public func answer(
        _ item: ReviewItemEntity,
        rating: Rating,
        now: Date = Date(),
        in context: ModelContext
    ) throws -> ReviewLog {
        let before = item.srs
        let after = scheduler.schedule(state: before, rating: rating, now: now)

        if before.stage == .new && item.introducedAt == nil {
            item.introducedAt = now
        }
        item.srs = after

        let log = ReviewLog(itemID: item.uuid, rating: rating, at: now, before: before, after: after)
        context.insert(ReviewLogEntity(log: log))
        try context.save()
        return log
    }

    // MARK: - 撤销

    /// 一次评分的完整快照，够把卡片原样放回去。
    public struct Undoable: Sendable {
        public let itemUUID: UUID
        public let previousState: SRSState
        public let previousIntroducedAt: Date?
        public let logID: UUID
    }

    /// 评分并返回可撤销的快照。这是 UI 该用的入口。
    public func answerUndoably(
        _ item: ReviewItemEntity,
        rating: Rating,
        now: Date = Date(),
        in context: ModelContext
    ) throws -> Undoable {
        let before = item.srs
        let introducedBefore = item.introducedAt
        let log = try answer(item, rating: rating, now: now, in: context)
        return Undoable(
            itemUUID: item.uuid,
            previousState: before,
            previousIntroducedAt: introducedBefore,
            logID: log.id
        )
    }

    /// 把一次评分整个撤回。
    ///
    /// 手滑按错「忘了」，一张 interval 已经 60 天的卡会直接归 1 天、ease 扣 0.2，
    /// 而 SM-2 是不可逆的 —— 没有撤销的话这个损失就永久留在那了。
    public func undo(_ record: Undoable, in context: ModelContext) throws {
        let uuid = record.itemUUID
        var descriptor = FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        guard let item = try context.fetch(descriptor).first else { return }

        item.srs = record.previousState
        item.introducedAt = record.previousIntroducedAt

        // 日志也要撤掉，否则统计和将来的 FSRS 训练数据里会留下一次没发生过的复习。
        let logID = record.logID
        let logs = try context.fetch(
            FetchDescriptor<ReviewLogEntity>(predicate: #Predicate { $0.id == logID })
        )
        for log in logs { context.delete(log) }

        try context.save()
    }

    // MARK: - 暂停

    /// 搁置一张卡：不再进队列，但保留全部进度。
    /// 遇到超纲词或者标错的词，得有个出口。
    public func setSuspended(_ item: ReviewItemEntity, _ suspended: Bool, in context: ModelContext) throws {
        item.isSuspended = suspended
        try context.save()
    }

    // MARK: - 连续天数

    /// 最近 `days` 天每天有没有复习过，最早的一天在前、今天在最后。
    ///
    /// 直接读 `ReviewLogEntity` —— 这张表从第一天就在写，但一直没人读过。
    /// 不另存「打卡记录」：那种计数器在删库重装、跨设备同步后必然和事实对不上。
    public func activity(days: Int, in context: ModelContext, now: Date = Date()) throws -> [Bool] {
        guard days > 0 else { return [] }
        let end = builder.dayEnd(after: now)
        let start = calendar.date(byAdding: .day, value: -days, to: end) ?? end

        let logs = try context.fetch(
            FetchDescriptor<ReviewLogEntity>(
                predicate: #Predicate { $0.reviewedAt >= start && $0.reviewedAt < end }
            )
        )

        var result = [Bool](repeating: false, count: days)
        for log in logs {
            // 距离「今天结束」多少个学习日
            let offset = Int(end.timeIntervalSince(log.reviewedAt) / secondsPerDay)
            let index = days - 1 - offset
            if result.indices.contains(index) { result[index] = true }
        }
        return result
    }

    /// 到今天为止连续学了几天。今天还没学不算断 —— 一天没过完就判人断更太苛刻了。
    public func streak(in context: ModelContext, now: Date = Date()) throws -> Int {
        let history = try activity(days: 60, in: context, now: now)
        var count = 0
        // 从昨天往前数；今天单独看
        for done in history.dropLast().reversed() {
            if done { count += 1 } else { break }
        }
        if history.last == true { count += 1 }
        return count
    }

    // MARK: - 统计

    public struct Counts: Equatable, Sendable {
        public var new = 0
        public var learning = 0
        public var review = 0
        public var suspended = 0
        public var total = 0

        public init() {}
    }

    public func counts(
        in context: ModelContext,
        kinds: Set<ReviewItemKind> = Set(ReviewItemKind.allCases),
        levels: Set<JLPTLevel>? = nil,
        packIDs: Set<String>? = nil
    ) throws -> Counts {
        let all = try context.fetch(FetchDescriptor<ReviewItemEntity>())
        var c = Counts()
        for item in all {
            guard kinds.contains(item.kind) else { continue }
            if let levels, !levels.contains(item.level) { continue }
            if let packIDs, !item.packID.isEmpty, !packIDs.contains(item.packID) { continue }
            c.total += 1
            if item.isSuspended { c.suspended += 1; continue }
            switch item.srs.stage {
            case .new: c.new += 1
            case .learning, .relearning: c.learning += 1
            case .review: c.review += 1
            }
        }
        return c
    }

    // MARK: - 错题本

    /// 一张卡的失败记录。
    ///
    /// 不声明 `Sendable` —— 它持有 `ReviewItemEntity`，而 SwiftData 的 `@Model`
    /// 绑在自己的 `ModelContext` 上，本来就不该跨线程传。调用方在主 actor 上用。
    public struct TroubleSpot {
        public var item: ReviewItemEntity
        /// 统计窗口内按「忘了」的次数。
        public var againCount: Int
        /// 统计窗口内总复习次数。
        public var totalCount: Int
        /// 最近一次按「忘了」的时刻。
        public var lastAgainAt: Date
        /// 累计遗忘次数（跨整个生命周期，来自 SRS 状态）。
        public var lapses: Int

        /// 窗口内的正确率。
        public var accuracy: Double {
            totalCount > 0 ? Double(totalCount - againCount) / Double(totalCount) : 0
        }
    }

    /// 最近反复答错的卡，错得最狠的排前面。
    ///
    /// 备考到后期，集中攻反复错的那几十个词比再背几百个新词有用 ——
    /// 但前提是你知道它们是哪几个。数据一直在 `ReviewLogEntity` 里，只是没人读。
    ///
    /// 排序口径：**先看错的次数，再看正确率，最后看谁错得更近**。
    /// 只按正确率排会让「只做过一次且错了」的卡冲到最前面（正确率 0%），
    /// 而那种卡只是没学熟，不是难点。
    ///
    /// - Parameter days: 统计窗口。默认 60 天 —— 三个月前错过、现在已经稳了的卡，
    ///   再摆在错题本里只会制造焦虑。
    public func troubleSpots(
        in context: ModelContext,
        days: Int = 60,
        limit: Int = 50,
        now: Date = Date(),
        levels: Set<JLPTLevel>? = nil,
        packIDs: Set<String>? = nil
    ) throws -> [TroubleSpot] {
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        let logs = try context.fetch(
            FetchDescriptor<ReviewLogEntity>(predicate: #Predicate { $0.reviewedAt >= start })
        )
        guard !logs.isEmpty else { return [] }

        var again: [UUID: Int] = [:]
        var total: [UUID: Int] = [:]
        var lastAgain: [UUID: Date] = [:]
        for log in logs {
            total[log.itemUUID, default: 0] += 1
            guard log.rating == .again else { continue }
            again[log.itemUUID, default: 0] += 1
            if let previous = lastAgain[log.itemUUID] {
                lastAgain[log.itemUUID] = max(previous, log.reviewedAt)
            } else {
                lastAgain[log.itemUUID] = log.reviewedAt
            }
        }
        guard !again.isEmpty else { return [] }

        let items = try context.fetch(FetchDescriptor<ReviewItemEntity>())
        var result: [TroubleSpot] = []
        for item in items {
            guard let count = again[item.uuid], let at = lastAgain[item.uuid] else { continue }
            if let levels, !levels.contains(item.level) { continue }
            if let packIDs, !item.packID.isEmpty, !packIDs.contains(item.packID) { continue }
            result.append(TroubleSpot(
                item: item,
                againCount: count,
                totalCount: total[item.uuid] ?? count,
                lastAgainAt: at,
                lapses: item.srs.lapses
            ))
        }

        result.sort {
            if $0.againCount != $1.againCount { return $0.againCount > $1.againCount }
            if $0.accuracy != $1.accuracy { return $0.accuracy < $1.accuracy }
            return $0.lastAgainAt > $1.lastAgainAt
        }
        return Array(result.prefix(limit))
    }

    // MARK: - 未来几天的负荷预测

    public struct DayLoad: Equatable, Sendable {
        /// 这一学习日的结束时刻（凌晨 4 点分界）。
        public var dayEnd: Date
        /// 到期的复习/巩固卡。
        public var due: Int
        /// 预计会引入的新卡。受每日额度和剩余未学数量双重限制。
        public var new: Int
        public var total: Int { due + new }
    }

    /// 预测未来 `days` 天每天要做多少张。
    ///
    /// 用途是提前排提醒通知 —— 通知内容要写「明天 23 张」这种具体数字，
    /// 而不是干巴巴一句「该复习了」。空口号的提醒会被忽略，具体数字不会。
    ///
    /// 两条口径要说清楚：
    ///
    /// - **过期卡算在第一天**。三天没打开积了 60 张，那 60 张是今天的债，
    ///   不是分摊到未来三天。
    /// - **新卡是估算**。每天按额度引入，但库里未学的总量会被逐日扣完；
    ///   剩下 5 张未学时，第二天就不再有新卡了。这是估算不是承诺，
    ///   因为期间你可能改额度、停用词包、或者从书里收新词。
    public func forecast(
        days: Int,
        in context: ModelContext,
        now: Date = Date(),
        kinds: Set<ReviewItemKind> = Set(ReviewItemKind.allCases),
        levels: Set<JLPTLevel>? = nil,
        packIDs: Set<String>? = nil
    ) throws -> [DayLoad] {
        guard days > 0 else { return [] }

        let all = try context.fetch(
            FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.isSuspended == false })
        )
        let scoped = all.filter { item in
            guard kinds.contains(item.kind) else { return false }
            if let levels, !levels.contains(item.level) { return false }
            if let packIDs, !item.packID.isEmpty, !packIDs.contains(item.packID) { return false }
            return true
        }

        // 还没学过的总量，用来给新卡估算封顶
        var remainingNew = scoped.filter { $0.srs.stage == .new }.count
        // 今天已经引入过的要从第一天的额度里扣掉
        let introducedToday = try newCardsIntroduced(in: context, now: now)

        var result: [DayLoad] = []
        var windowStart = now
        for offset in 0..<days {
            let end = builder.dayEnd(after: windowStart)

            // 第一天含所有过期卡（dueDate 早于窗口起点的也算）；
            // 之后每天只算落在那一天里的。
            let due = scoped.filter { item in
                guard item.srs.stage != .new, let dueDate = item.dueDate else { return false }
                if offset == 0 { return dueDate < end }
                return dueDate >= windowStart && dueDate < end
            }.count

            let quota = offset == 0
                ? max(0, queueConfig.newCardsPerDay - introducedToday)
                : queueConfig.newCardsPerDay
            let new = min(quota, remainingNew)
            remainingNew -= new

            result.append(DayLoad(
                dayEnd: end,
                due: min(due, queueConfig.maxReviewsPerDay),
                new: new
            ))
            windowStart = end
        }
        return result
    }
}
