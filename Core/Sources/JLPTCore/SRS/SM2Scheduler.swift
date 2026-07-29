import Foundation

/// SM-2 变体（Anki 风格）：新卡走 learning steps 巩固，毕业后按 ease 拉长间隔，
/// 忘掉则回炉 relearning。
///
/// 与教科书 SM-2 的两点有意偏离，都是 Anki 的实践经验：
/// 1. learning / relearning 阶段不动 `easeFactor` —— 新卡还没形成记忆强度，
///    在这里扣 ease 会让卡片一开始就被判成"难"。ease 只在 review 阶段调整。
/// 2. 答对时保证间隔至少 +1 天，避免 `1 × 1.2 → 1` 这种卡在原地不动的情况。
public struct SM2Scheduler: SchedulerProtocol {
    public let config: SRSConfig

    public init(config: SRSConfig = SRSConfig()) {
        self.config = config
    }

    public func schedule(state: SRSState, rating: Rating, now: Date) -> SRSState {
        var s = state
        // 连续答对计数。Again 归零 —— 蒙对一次不算学会，
        // 选择题有 25% 的瞎猜基线，只能靠重复把运气滤掉。
        s.correctStreak = rating == .again ? 0 : s.correctStreak + 1

        switch state.stage {
        case .new, .learning:
            step(&s, rating: rating, now: now, steps: config.learningSteps, relearning: false)
        case .relearning:
            step(&s, rating: rating, now: now, steps: config.relearningSteps, relearning: true)
        case .review:
            review(&s, rating: rating, now: now)
        }
        s.lastReviewedAt = now
        return s
    }

    // MARK: - learning / relearning

    private func step(
        _ s: inout SRSState,
        rating: Rating,
        now: Date,
        steps: [TimeInterval],
        relearning: Bool
    ) {
        // 配置成空步骤数组时，等于关掉短期巩固，直接毕业。
        guard !steps.isEmpty else {
            graduate(&s, now: now, intervalDays: graduationInterval(for: rating, s: s, relearning: relearning))
            return
        }

        let stage: LearningStage = relearning ? .relearning : .learning

        switch rating {
        case .again:
            s.stage = stage
            s.stepIndex = 0
            s.dueDate = now.addingTimeInterval(steps[0])

        case .hard:
            // 原地重复当前步骤。
            s.stage = stage
            let idx = min(s.stepIndex, steps.count - 1)
            s.stepIndex = idx
            s.dueDate = now.addingTimeInterval(steps[idx])

        case .good:
            let next = s.stepIndex + 1
            if next >= steps.count, canGraduate(s, relearning: relearning) {
                graduate(&s, now: now, intervalDays: graduationInterval(for: .good, s: s, relearning: relearning))
            } else {
                // 步骤走完了但答对次数还不够，就停在最后一步再来一次。
                s.stage = stage
                s.stepIndex = min(next, steps.count - 1)
                s.dueDate = now.addingTimeInterval(steps[s.stepIndex])
            }

        case .easy:
            if canGraduate(s, relearning: relearning) {
                graduate(&s, now: now, intervalDays: graduationInterval(for: .easy, s: s, relearning: relearning))
            } else {
                s.stage = stage
                s.stepIndex = min(s.stepIndex + 1, steps.count - 1)
                s.dueDate = now.addingTimeInterval(steps[s.stepIndex])
            }
        }
    }

    /// 答对次数够了吗。回炉阶段不设这道门槛 —— 那是已经学会过又忘掉的卡，
    /// 让它重新攒三次会把复习队列撑爆。
    private func canGraduate(_ s: SRSState, relearning: Bool) -> Bool {
        relearning || s.correctStreak >= config.requiredCorrectToGraduate
    }

    private func graduationInterval(for rating: Rating, s: SRSState, relearning: Bool) -> Int {
        if relearning {
            // 回炉毕业时沿用 lapse 之后的间隔（通常是 1 天）；Easy 则给个奖励。
            return rating == .easy ? max(s.intervalDays, config.easyIntervalDays) : max(s.intervalDays, 1)
        }
        return rating == .easy ? config.easyIntervalDays : config.graduatingIntervalDays
    }

    private func graduate(_ s: inout SRSState, now: Date, intervalDays: Int) {
        s.stage = .review
        s.stepIndex = 0
        s.repetitions = 1
        s.intervalDays = clampInterval(intervalDays)
        s.dueDate = now.addingTimeInterval(Double(s.intervalDays) * secondsPerDay)
    }

    // MARK: - review

    private func review(_ s: inout SRSState, rating: Rating, now: Date) {
        let previousInterval = s.intervalDays
        s.easeFactor = clampEase(s.easeFactor + config.easeDelta(for: rating))

        switch rating {
        case .again:
            s.lapses += 1
            s.repetitions = 0
            s.intervalDays = clampInterval(
                Int((Double(previousInterval) * config.lapseIntervalMultiplier).rounded())
            )
            if let firstStep = config.relearningSteps.first {
                s.stage = .relearning
                s.stepIndex = 0
                s.dueDate = now.addingTimeInterval(firstStep)
            } else {
                s.stage = .review
                s.dueDate = now.addingTimeInterval(Double(s.intervalDays) * secondsPerDay)
            }

        case .hard:
            s.intervalDays = grow(previousInterval, by: config.hardMultiplier)
            s.repetitions += 1
            s.dueDate = now.addingTimeInterval(Double(s.intervalDays) * secondsPerDay)

        case .good:
            let next: Int = switch s.repetitions {
            case 0: config.graduatingIntervalDays
            case 1: config.secondIntervalDays
            default: Int((Double(previousInterval) * s.easeFactor).rounded())
            }
            s.intervalDays = clampInterval(max(next, previousInterval + 1))
            s.repetitions += 1
            s.dueDate = now.addingTimeInterval(Double(s.intervalDays) * secondsPerDay)

        case .easy:
            s.intervalDays = grow(previousInterval, by: s.easeFactor * config.easyBonus)
            s.repetitions += 1
            s.dueDate = now.addingTimeInterval(Double(s.intervalDays) * secondsPerDay)
        }
    }

    // MARK: - helpers

    private func grow(_ interval: Int, by factor: Double) -> Int {
        clampInterval(max(Int((Double(interval) * factor).rounded()), interval + 1))
    }

    private func clampEase(_ ease: Double) -> Double {
        max(config.minEase, ease)
    }

    private func clampInterval(_ days: Int) -> Int {
        min(max(days, 1), config.maxIntervalDays)
    }
}
