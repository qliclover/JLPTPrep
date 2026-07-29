import Foundation

/// SM-2 调度器的全部可调参数。默认值 = PRD §5 描述的规则。
public struct SRSConfig: Equatable, Sendable {
    /// 毕业前需要连续答对几次。选择题有 25% 的瞎猜基线，一次答对说明不了什么。
    public var requiredCorrectToGraduate: Int
    /// 新卡的短期巩固步骤（秒）。默认 1min → 10min → 1天，走完且答对够次数才毕业。
    public var learningSteps: [TimeInterval]
    /// 忘掉之后的回炉步骤（秒）。
    public var relearningSteps: [TimeInterval]
    /// Good 毕业时的首个间隔（天）。
    public var graduatingIntervalDays: Int
    /// 新卡直接按 Easy 时的间隔（天）。
    public var easyIntervalDays: Int
    /// 毕业后第二次答对的间隔（天），SM-2 的固定阶梯。
    public var secondIntervalDays: Int

    public var minEase: Double
    public var maxIntervalDays: Int

    public var hardMultiplier: Double
    public var easyBonus: Double
    /// 忘掉后新间隔 = 旧间隔 × 这个系数（0 表示直接归 1 天，见 PRD）。
    public var lapseIntervalMultiplier: Double

    public var easeDeltaAgain: Double
    public var easeDeltaHard: Double
    public var easeDeltaGood: Double
    public var easeDeltaEasy: Double

    public init(
        requiredCorrectToGraduate: Int = 3,
        // 三个步骤对应三次答对，自然落在 1分 / 10分 / 1天 上。
        // 刻意跨天：十分钟内连答三遍是突击，对长期记忆几乎没贡献。
        learningSteps: [TimeInterval] = [60, 600, 86_400],
        relearningSteps: [TimeInterval] = [600],
        graduatingIntervalDays: Int = 1,
        easyIntervalDays: Int = 4,
        secondIntervalDays: Int = 6,
        minEase: Double = 1.3,
        maxIntervalDays: Int = 365 * 5,
        hardMultiplier: Double = 1.2,
        easyBonus: Double = 1.3,
        lapseIntervalMultiplier: Double = 0.0,
        easeDeltaAgain: Double = -0.20,
        easeDeltaHard: Double = -0.15,
        easeDeltaGood: Double = 0.0,
        easeDeltaEasy: Double = 0.15
    ) {
        self.requiredCorrectToGraduate = requiredCorrectToGraduate
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.graduatingIntervalDays = graduatingIntervalDays
        self.easyIntervalDays = easyIntervalDays
        self.secondIntervalDays = secondIntervalDays
        self.minEase = minEase
        self.maxIntervalDays = maxIntervalDays
        self.hardMultiplier = hardMultiplier
        self.easyBonus = easyBonus
        self.lapseIntervalMultiplier = lapseIntervalMultiplier
        self.easeDeltaAgain = easeDeltaAgain
        self.easeDeltaHard = easeDeltaHard
        self.easeDeltaGood = easeDeltaGood
        self.easeDeltaEasy = easeDeltaEasy
    }

    public func easeDelta(for rating: Rating) -> Double {
        switch rating {
        case .again: easeDeltaAgain
        case .hard: easeDeltaHard
        case .good: easeDeltaGood
        case .easy: easeDeltaEasy
        }
    }
}

public let secondsPerDay: TimeInterval = 86_400
