import Foundation
import SwiftData
import JLPTCore

/// 把读书时遇到的生词收进词库。
///
/// 这是「阅读 → 背词」闭环缺的那一环：以前只有随包内容包里的词能进 SRS，
/// 读小说碰到的词一个都加不进来，闭环等于没接上。
///
/// 收进来的词用独立的 `packID`，内容包更新时不会碰它们。
public struct VocabCollector {
    public static let packID = "user-collected"

    public init() {}

    /// slug 由表记推出，保证同一个词反复收也只有一条。
    public static func slug(for expression: String) -> String {
        "user-\(expression)"
    }

    /// 收词。已经收过（或本来就在词库里）就原样返回，不重复建卡。
    @discardableResult
    public func collect(
        expression: String,
        reading: String,
        meaningZh: String,
        partOfSpeech: String,
        level: JLPTLevel = .n5,
        examples: [Example] = [],
        into context: ModelContext,
        now: Date = Date()
    ) throws -> VocabEntity {
        // 词库里本来就有（内容包带的）就直接用那一条，别造重复词。
        if let existing = try find(expression: expression, in: context) {
            return existing
        }

        let slug = Self.slug(for: expression)
        let entity = VocabEntity(
            slug: slug,
            expression: expression,
            reading: reading,
            furigana: nil,
            meaningZh: meaningZh,
            partOfSpeech: partOfSpeech,
            level: level,
            tags: ["生词本"],
            examples: examples,
            packID: Self.packID
        )
        context.insert(entity)

        let key = ReviewItemEntity.key(kind: .vocab, slug: slug)
        var descriptor = FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if try context.fetch(descriptor).first == nil {
            context.insert(ReviewItemEntity(kind: .vocab, contentSlug: slug, level: level, createdAt: now))
        }

        try context.save()
        return entity
    }

    /// 这个词已经在词库里了吗（不分来源）。
    public func find(expression: String, in context: ModelContext) throws -> VocabEntity? {
        var descriptor = FetchDescriptor<VocabEntity>(
            predicate: #Predicate { $0.expression == expression && $0.isRetired == false }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// 用户自己收的词数。
    public func collectedCount(in context: ModelContext) throws -> Int {
        let pack = Self.packID
        return try context.fetchCount(
            FetchDescriptor<VocabEntity>(predicate: #Predicate { $0.packID == pack })
        )
    }
}
