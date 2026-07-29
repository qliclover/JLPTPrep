import Foundation
import SwiftData
import JLPTCore
import JLPTJapanese

/// 从数据库出选择题。
public struct QuizService {
    public init() {}

    /// 出题库。一场复习取一次，别每道题都查一遍库。
    ///
    /// - Parameter levels: 限定等级范围。干扰项该来自同一考纲范围 ——
    ///   给 N5 的词配 N1 的干扰项，学习者靠「这词我压根没见过」就能排除，题就白出了。
    public func pool(in context: ModelContext, levels: Set<JLPTLevel>? = nil) throws -> [QuizWord] {
        let all = try context.fetch(
            FetchDescriptor<VocabEntity>(predicate: #Predicate { $0.isRetired == false })
        )
        let scoped = levels.map { set in all.filter { set.contains($0.level) } } ?? all
        return scoped.map(Self.quizWord)
    }

    static func quizWord(_ entity: VocabEntity) -> QuizWord {
        QuizWord(
            slug: entity.slug,
            expression: entity.expression,
            reading: entity.reading,
            meaningZh: entity.displayMeaning,
            partOfSpeech: entity.partOfSpeech,
            exampleJa: entity.examples.first?.ja,
            exampleFurigana: entity.examples.first?.furigana
        )
    }

    /// 给一张卡出题。出不了（词库太小、这个词没有可用题型）就返回 nil，
    /// 调用方应该退回翻卡自评模式，而不是硬凑一道烂题。
    public func question<G: RandomNumberGenerator>(
        for item: ReviewItemEntity,
        pool: [QuizWord],
        using generator: inout G
    ) -> QuizQuestion? {
        guard let word = pool.first(where: { $0.slug == item.contentSlug }) else { return nil }

        let types = QuizGenerator.availableTypes(for: word, pool: pool)
        guard !types.isEmpty else { return nil }

        // 按已答对的次数轮换题型：毕业需要的三次答对会考到三个不同的角度
        // （读音 → 表记 → 词义），而不是同一道题做三遍。
        let ordered = rotate(types, by: item.srs.correctStreak)
        for type in ordered {
            if let question = QuizGenerator.question(for: word, type: type, pool: pool, using: &generator) {
                return question
            }
        }
        return nil
    }

    private func rotate(_ types: [QuestionType], by offset: Int) -> [QuestionType] {
        guard !types.isEmpty else { return [] }
        let index = ((offset % types.count) + types.count) % types.count
        return Array(types[index...] + types[..<index])
    }
}
