import Foundation
import SwiftData
import JLPTCore

/// 把语法内容包灌进数据库。
///
/// 和词库导入同一套约束：**只碰内容表，绝不动进度表的既有行**。
/// 全程 upsert + 退役标记，没有一处 delete —— 内容包更新了，
/// 你在那条语法上攒的复习进度还在。
///
/// 语法条目也会建 `ReviewItemEntity`（kind: .grammar），所以它们
/// 和单词一起进每日队列。`todayQueue` 本来就按 kind 过滤，这一步是免费的。
public struct GrammarImporter {
    public init() {}

    public struct Pack: Decodable {
        public struct Entry: Decodable {
            var slug: String
            var pattern: String
            var connectionRule: String
            var meaningZh: String
            var noteZh: String?
            var level: String
            var tags: [String]?
            var contrastSlugs: [String]?
            var examples: [Example]
        }
        var schemaVersion: Int
        var packID: String
        var level: String
        var grammar: [Entry]
    }

    @discardableResult
    public func `import`(
        data: Data, into context: ModelContext, now: Date = Date()
    ) throws -> ImportReport {
        let pack = try JSONDecoder().decode(Pack.self, from: data)
        guard !pack.grammar.isEmpty else { throw GrammarImportError.emptyPack }

        // slug 重复会让「哪一条是权威」变得不确定，直接拒绝整包
        var seen = Set<String>()
        for entry in pack.grammar where !seen.insert(entry.slug).inserted {
            throw GrammarImportError.duplicateSlug(entry.slug)
        }

        var report = ImportReport()
        let packID = pack.packID

        let existing = try context.fetch(
            FetchDescriptor<GrammarEntity>(predicate: #Predicate { $0.packID == packID })
        )
        var bySlug = Dictionary(existing.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })

        // 已有的复习记录，用来判断哪些条目要新建 SRS 行
        let items = try context.fetch(FetchDescriptor<ReviewItemEntity>())
        var reviewKeys = Set(items.map(\.key))

        for entry in pack.grammar {
            let level = JLPTLevel(rawValue: entry.level) ?? .n5

            if let found = bySlug.removeValue(forKey: entry.slug) {
                let changed = found.pattern != entry.pattern
                    || found.connectionRule != entry.connectionRule
                    || found.meaningZh != entry.meaningZh
                    || found.noteZh != entry.noteZh
                    || found.examples != entry.examples
                if changed {
                    found.pattern = entry.pattern
                    found.connectionRule = entry.connectionRule
                    found.meaningZh = entry.meaningZh
                    found.noteZh = entry.noteZh
                    found.examples = entry.examples
                    found.tags = entry.tags ?? []
                    found.contrastSlugs = entry.contrastSlugs ?? []
                    found.level = level
                    report.updated += 1
                } else {
                    report.unchanged += 1
                }
                found.isRetired = false
            } else {
                context.insert(GrammarEntity(
                    slug: entry.slug, pattern: entry.pattern,
                    connectionRule: entry.connectionRule, meaningZh: entry.meaningZh,
                    noteZh: entry.noteZh, level: level,
                    tags: entry.tags ?? [], examples: entry.examples,
                    contrastSlugs: entry.contrastSlugs ?? [], packID: packID
                ))
                report.inserted += 1
            }

            // 建 SRS 行。已经有的绝不重建 —— 那会把进度清零。
            let key = ReviewItemEntity.key(kind: .grammar, slug: entry.slug)
            if reviewKeys.insert(key).inserted {
                context.insert(ReviewItemEntity(
                    kind: .grammar, contentSlug: entry.slug, level: level,
                    packID: packID, createdAt: now
                ))
                report.reviewItemsCreated += 1
            }
        }

        // 包里没有了的条目标记退役，不删 —— 删了它的复习进度就成了孤儿
        for (_, orphan) in bySlug where !orphan.isRetired {
            orphan.isRetired = true
            report.retired += 1
        }

        try context.save()
        return report
    }
}

public enum GrammarImportError: LocalizedError {
    case emptyPack
    case duplicateSlug(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPack:
            "语法包里没有条目。"
        case .duplicateSlug(let slug):
            "语法包里有重复的 slug「\(slug)」，无法确定哪一条是权威版本。"
        }
    }
}
