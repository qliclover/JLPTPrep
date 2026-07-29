import Foundation
import CryptoKit
import SwiftData
import JLPTCore

public struct ImportReport: Equatable, Sendable {
    public var inserted = 0
    public var updated = 0
    public var unchanged = 0
    public var retired = 0
    /// 新建的 SRS 记录数。老词重新导入时应该是 0。
    public var reviewItemsCreated = 0
    /// 指纹没变，整包跳过。
    public var skipped = false

    public var touched: Int { inserted + updated + retired }
}

/// 把 JSON 内容包灌进数据库。
///
/// 核心约束：**导入只能碰内容表，绝不能碰进度表的既有行**。
/// 所以这里全程是 upsert + 退役标记，没有一处 delete。
public struct ContentImporter {
    public init() {}

    // MARK: - 入口

    /// 从原始 JSON 导入。
    @discardableResult
    public func importVocabPack(
        data: Data,
        into context: ModelContext,
        now: Date = Date(),
        force: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ImportReport {
        let pack = try ContentPackSchema.decoder().decode(VocabPack.self, from: data)
        return try importVocabPack(pack, into: context, now: now, force: force, progress: progress)
    }

    /// 从 bundle 里的资源导入（App 启动时走这条）。
    @discardableResult
    public func importVocabPack(
        resource: String,
        withExtension ext: String = "json",
        in bundle: Bundle,
        into context: ModelContext,
        now: Date = Date(),
        force: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ImportReport {
        guard let url = bundle.url(forResource: resource, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try importVocabPack(
            data: Data(contentsOf: url), into: context, now: now, force: force, progress: progress
        )
    }

    @discardableResult
    public func importVocabPack(
        _ pack: VocabPack,
        into context: ModelContext,
        now: Date = Date(),
        force: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ImportReport {
        try validate(pack)

        let hash = try fingerprint(of: pack)
        let record = try existingRecord(packID: pack.packID, in: context)

        if !force, let record, record.contentHash == hash {
            var report = ImportReport()
            report.skipped = true
            report.unchanged = pack.vocab.count
            return report
        }

        var report = ImportReport()

        // 一次性把这个包已有的行取出来做成字典，避免每个词一次 fetch。
        let packID = pack.packID
        let existing = try context.fetch(
            FetchDescriptor<VocabEntity>(predicate: #Predicate { $0.packID == packID })
        )
        var byslug = Dictionary(existing.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })

        // 一次性把已有的进度记录键取出来。逐词 fetch 在 8000 词的包上会慢到没法用。
        let allItems = try context.fetch(FetchDescriptor<ReviewItemEntity>())
        let existingItems = Dictionary(allItems.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var existingKeys = Set(allItems.map(\.key))

        var seenSlugs = Set<String>()

        for (offset, seed) in pack.vocab.enumerated() {
            // 每 200 条回报一次进度，太频繁反而拖慢导入
            if offset % 200 == 0 {
                progress?(Double(offset) / Double(pack.vocab.count))
            }
            seenSlugs.insert(seed.slug)
            let level = seed.level ?? pack.level

            if let entity = byslug[seed.slug] {
                if apply(seed, level: level, packID: pack.packID, to: entity) {
                    report.updated += 1
                } else {
                    report.unchanged += 1
                }
            } else {
                let entity = VocabEntity(
                    slug: seed.slug,
                    expression: seed.expression,
                    reading: seed.reading,
                    furigana: seed.furigana,
                    meaningZh: seed.meaningZh,
                    meaningEn: seed.meaningEn,
                    partOfSpeech: seed.partOfSpeech,
                    level: level,
                    audioFile: seed.audioFile,
                    tags: seed.tags ?? [],
                    examples: seed.examples ?? [],
                    packID: pack.packID
                )
                context.insert(entity)
                byslug[seed.slug] = entity
                report.inserted += 1
            }

            let key = ReviewItemEntity.key(kind: .vocab, slug: seed.slug)
            if let existing = existingItems[key] {
                if existing.packID != pack.packID { existing.packID = pack.packID }
                if existing.levelRaw != level.rawValue { existing.levelRaw = level.rawValue }
            } else if existingKeys.insert(key).inserted {
                context.insert(ReviewItemEntity(
                    kind: .vocab, contentSlug: seed.slug, level: level,
                    packID: pack.packID, createdAt: now
                ))
                report.reviewItemsCreated += 1
            }
        }

        // 新版包里消失的词：标记退役，不删除。用户可能已经背了三个月，
        // 删掉会连带丢掉复习历史，而内容作者的一次手滑不该有这种后果。
        for (slug, entity) in byslug where !seenSlugs.contains(slug) {
            if !entity.isRetired {
                entity.isRetired = true
                report.retired += 1
            }
        }
        // 反过来，重新出现的词要复活。
        for slug in seenSlugs {
            if let entity = byslug[slug], entity.isRetired { entity.isRetired = false }
        }

        if let record {
            record.contentHash = hash
            record.schemaVersion = pack.schemaVersion
            record.importedAt = now
            record.itemCount = pack.vocab.count
        } else {
            context.insert(ImportRecordEntity(
                packID: pack.packID,
                contentHash: hash,
                schemaVersion: pack.schemaVersion,
                importedAt: now,
                itemCount: pack.vocab.count
            ))
        }

        try context.save()
        progress?(1)
        return report
    }

    // MARK: - 内部

    private func validate(_ pack: VocabPack) throws {
        guard pack.schemaVersion == ContentPackSchema.current else {
            throw ContentPackError.unsupportedSchemaVersion(
                found: pack.schemaVersion,
                supported: ContentPackSchema.current
            )
        }
        guard !pack.vocab.isEmpty else {
            throw ContentPackError.emptyPack(packID: pack.packID)
        }
        // slug 重复会让 upsert 静默丢词，而且 @Attribute(.unique) 触发的是
        // 覆盖而非报错，出问题时极难排查 —— 所以在进库前就拦下来。
        var seen = Set<String>()
        var dupes = Set<String>()
        for seed in pack.vocab where !seen.insert(seed.slug).inserted {
            dupes.insert(seed.slug)
        }
        guard dupes.isEmpty else {
            throw ContentPackError.duplicateSlugs(dupes.sorted())
        }
    }

    func fingerprint(of pack: VocabPack) throws -> String {
        let data = try ContentPackSchema.canonicalEncoder().encode(pack)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func existingRecord(packID: String, in context: ModelContext) throws -> ImportRecordEntity? {
        var descriptor = FetchDescriptor<ImportRecordEntity>(predicate: #Predicate { $0.packID == packID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// 把种子写进实体。返回 true 表示确实有字段变了。
    private func apply(_ seed: VocabSeed, level: JLPTLevel, packID: String, to entity: VocabEntity) -> Bool {
        var changed = false
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<VocabEntity, T>, _ value: T) {
            if entity[keyPath: keyPath] != value {
                entity[keyPath: keyPath] = value
                changed = true
            }
        }
        set(\.expression, seed.expression)
        set(\.reading, seed.reading)
        set(\.furigana, seed.furigana)
        set(\.meaningZh, seed.meaningZh)
        set(\.meaningEn, seed.meaningEn)
        set(\.partOfSpeech, seed.partOfSpeech)
        set(\.levelRaw, level.rawValue)
        set(\.audioFile, seed.audioFile)
        set(\.tags, seed.tags ?? [])
        set(\.examples, seed.examples ?? [])
        set(\.packID, packID)
        return changed
    }

}
