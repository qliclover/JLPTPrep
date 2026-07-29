import Foundation
import SwiftData
import JLPTCore

/// 一套导入的真题。
///
/// **真题不随包分发。** 官方真题集和商业教材都在卖，把题打进上架的 App 就是再分发。
/// 所以 App 出厂不带任何试卷，由用户导入自己的题库文件 —— 内容始终在自己设备上，
/// 这和你在 iPad 上打开 PDF 做题没有区别。
@Model
public final class ExamEntity {
    @Attribute(.unique) public var id: String
    public var level: String
    public var session: String
    public var importedAt: Date
    /// 这套题配有听力音频吗。有的话题目里的听力部分才有意义。
    public var hasAudio: Bool

    @Relationship(deleteRule: .cascade, inverse: \ExamQuestionEntity.exam)
    public var questions: [ExamQuestionEntity] = []

    public init(
        level: String, session: String, hasAudio: Bool = false, importedAt: Date = Date()
    ) {
        self.id = "\(level)-\(session)"
        self.level = level
        self.session = session
        self.hasAudio = hasAudio
        self.importedAt = importedAt
    }

    public var answeredCount: Int { questions.count { $0.picked != nil } }
    public var correctCount: Int { questions.count { $0.picked == $0.answer } }

    /// 做过的题里对了多少。没做过时为 nil —— 0% 和「还没开始」是两回事。
    public var accuracy: Double? {
        guard answeredCount > 0 else { return nil }
        return Double(correctCount) / Double(answeredCount)
    }
}

@Model
public final class ExamQuestionEntity {
    public var exam: ExamEntity?
    /// 「文字・語彙」「文法・読解」「聴解」
    public var subject: String
    public var section: Int
    public var number: Int
    public var stem: String
    /// 四个选项，顺序即序号。
    public var options: [String]
    /// 正确答案，1...4。
    public var answer: Int

    // MARK: 作答状态
    /// 用户选的，1...4。nil = 还没做。
    public var picked: Int?
    public var answeredAt: Date?

    public init(
        subject: String, section: Int, number: Int,
        stem: String, options: [String], answer: Int
    ) {
        self.subject = subject
        self.section = section
        self.number = number
        self.stem = stem
        self.options = options
        self.answer = answer
    }

    public var isCorrect: Bool? { picked.map { $0 == answer } }
    /// 听力题的题干在音频里，纸面上只有选项。
    public var isListening: Bool { subject.contains("聴解") }
}

// MARK: - 导入

public enum ExamImporter {

    /// `Tools/ParseExam` 输出的 JSON 结构。
    private struct Payload: Decodable {
        struct Question: Decodable {
            var subject: String
            var section: Int
            var number: Int
            var stem: String
            var options: [String]
            var answer: Int?
        }
        var level: String
        var session: String
        var hasAudio: Bool?
        var questions: [Question]
    }

    public struct Report: Equatable {
        public var level = ""
        public var session = ""
        public var imported = 0
        public var skipped = 0
        public var replaced = false
    }

    /// 导入一份题库文件。
    ///
    /// 同一场考试重复导入时**整套替换**，而不是合并 —— 题库文件是重新解析生成的，
    /// 合并只会留下新旧两版混在一起的题。作答记录跟着一起清掉：
    /// 题目都换了，旧的对错没有意义。
    @discardableResult
    public static func `import`(
        data: Data, into context: ModelContext, now: Date = Date()
    ) throws -> Report {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        var report = Report(level: payload.level, session: payload.session)

        let id = "\(payload.level)-\(payload.session)"
        let existing = try context.fetch(
            FetchDescriptor<ExamEntity>(predicate: #Predicate { $0.id == id })
        )
        for old in existing {
            context.delete(old)
            report.replaced = true
        }

        let exam = ExamEntity(
            level: payload.level, session: payload.session,
            hasAudio: payload.hasAudio ?? false, importedAt: now
        )
        context.insert(exam)

        for q in payload.questions {
            // 没有答案、或者选项不足四个的题一律不收 ——
            // 一道答案错了的练习题比没有这道题有害：你做对了却被判错。
            guard let answer = q.answer, (1...4).contains(answer),
                  q.options.count == 4, q.options.allSatisfy({ !$0.isEmpty })
            else {
                report.skipped += 1
                continue
            }
            let entity = ExamQuestionEntity(
                subject: q.subject, section: q.section, number: q.number,
                stem: q.stem, options: q.options, answer: answer
            )
            entity.exam = exam
            context.insert(entity)
            report.imported += 1
        }

        guard report.imported > 0 else {
            context.delete(exam)
            throw ExamImportError.noUsableQuestions
        }

        try context.save()
        return report
    }
}

public enum ExamImportError: LocalizedError {
    case noUsableQuestions

    public var errorDescription: String? {
        switch self {
        case .noUsableQuestions:
            "这个文件里没有可用的题目。每道题需要四个完整选项和一个答案。"
        }
    }
}
