import Foundation

/// 考纲等级。`Comparable` 按难度排序（N5 最简单），方便做「N4 范围包含 N5」这类过滤。
public enum JLPTLevel: String, Codable, CaseIterable, Sendable, Comparable {
    case n5 = "N5"
    case n4 = "N4"
    case n3 = "N3"
    case n2 = "N2"
    case n1 = "N1"

    /// 数字越小越简单。
    public var difficulty: Int {
        switch self {
        case .n5: 0
        case .n4: 1
        case .n3: 2
        case .n2: 3
        case .n1: 4
        }
    }

    public static func < (lhs: JLPTLevel, rhs: JLPTLevel) -> Bool {
        lhs.difficulty < rhs.difficulty
    }

    /// 备考某个等级时需要覆盖的全部等级（考 N4 要连 N5 一起背）。
    public var cumulativeScope: Set<JLPTLevel> {
        Set(JLPTLevel.allCases.filter { $0.difficulty <= difficulty })
    }
}

/// 进 SRS 队列的内容类型。单词和语法共用一套调度，靠它区分来源。
public enum ReviewItemKind: String, Codable, CaseIterable, Sendable {
    case vocab
    case grammar
}
