import Foundation

/// 复习时用户的四档自评，对应 UI 上的四个按钮。
public enum Rating: Int, Codable, CaseIterable, Sendable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3
}

/// 卡片在记忆流程中所处的阶段。
public enum LearningStage: String, Codable, CaseIterable, Sendable {
    /// 还没学过
    case new
    /// 新卡的短期巩固步骤中（1min → 10min）
    case learning
    /// 已毕业，按天为单位间隔复习
    case review
    /// 复习中忘掉了，回炉重学
    case relearning
}
