import Foundation
import SwiftData
import JLPTCore

/// 一个词库包的安装状态。
///
/// 和 `ImportRecordEntity` 分开：那张表记的是「上次导入的内容指纹」，用于判重；
/// 这张记的是「用户想不想用它」。两件事的生命周期不同 ——
/// 停用一个包不该让它下次启动被当成没导入过。
@Model
public final class VocabPackEntity {
    @Attribute(.unique) public var packID: String
    public var levelRaw: String
    public var imported: Bool
    /// 停用只是把包从队列里摘掉，**进度全部留着**。
    public var enabled: Bool
    public var itemCount: Int
    public var importedAt: Date?

    public var level: JLPTLevel {
        get { JLPTLevel(rawValue: levelRaw) ?? .n5 }
        set { levelRaw = newValue.rawValue }
    }

    public init(
        packID: String,
        level: JLPTLevel,
        imported: Bool = false,
        enabled: Bool = false,
        itemCount: Int = 0,
        importedAt: Date? = nil
    ) {
        self.packID = packID
        self.levelRaw = level.rawValue
        self.imported = imported
        self.enabled = enabled
        self.itemCount = itemCount
        self.importedAt = importedAt
    }
}

/// 等级词库的读写。
public struct PackLibrary {
    public init() {}

    /// 内容包的命名约定：等级 → packID / 资源名。
    public static func packID(for level: JLPTLevel) -> String {
        "jlpt-\(level.rawValue.lowercased())"
    }

    public static func resourceName(for level: JLPTLevel) -> String {
        "vocab_\(level.rawValue.lowercased())"
    }

    /// 每个等级一行，由易到难。缺的行会被建出来（未导入状态）。
    @discardableResult
    public func packs(in context: ModelContext) throws -> [VocabPackEntity] {
        let existing = try context.fetch(FetchDescriptor<VocabPackEntity>())
        var byID = Dictionary(existing.map { ($0.packID, $0) }, uniquingKeysWith: { a, _ in a })

        var result: [VocabPackEntity] = []
        for level in JLPTLevel.allCases.sorted(by: { $0.difficulty < $1.difficulty }) {
            let id = Self.packID(for: level)
            if let entity = byID[id] {
                result.append(entity)
            } else {
                let entity = VocabPackEntity(packID: id, level: level)
                context.insert(entity)
                byID[id] = entity
                result.append(entity)
            }
        }
        if context.hasChanges { try context.save() }
        return result
    }

    /// 已启用的包 ID。队列过滤用它。
    public func enabledPackIDs(in context: ModelContext) throws -> Set<String> {
        Set(
            try context.fetch(
                FetchDescriptor<VocabPackEntity>(predicate: #Predicate { $0.enabled == true })
            ).map(\.packID)
        )
    }

    /// 导入某个等级的包。
    ///
    /// - Parameter progress: 0...1，按词条批次回报。设计里那条进度线要走真实进度，
    ///   而不是假装动一动 —— 导入 N1 的 2,699 词是真的要花点时间。
    @discardableResult
    public func `import`(
        level: JLPTLevel,
        from bundle: Bundle,
        into context: ModelContext,
        now: Date = Date(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ImportReport {
        let report = try ContentImporter().importVocabPack(
            resource: Self.resourceName(for: level),
            in: bundle,
            into: context,
            now: now,
            progress: progress
        )

        let id = Self.packID(for: level)
        var descriptor = FetchDescriptor<VocabPackEntity>(predicate: #Predicate { $0.packID == id })
        descriptor.fetchLimit = 1
        let entity = try context.fetch(descriptor).first ?? {
            let new = VocabPackEntity(packID: id, level: level)
            context.insert(new)
            return new
        }()

        entity.imported = true
        entity.importedAt = now
        entity.itemCount = try context.fetchCount(
            FetchDescriptor<VocabEntity>(predicate: #Predicate { $0.packID == id && $0.isRetired == false })
        )
        // 刚导进来的包默认启用 —— 用户点「导入」就是想用它。
        entity.enabled = true
        try context.save()
        return report
    }

    public func setEnabled(_ enabled: Bool, for pack: VocabPackEntity, in context: ModelContext) throws {
        pack.enabled = enabled
        try context.save()
    }

    /// 已启用的包一共多少词。首页的「词库进度」分母用它。
    public func enabledItemCount(in context: ModelContext) throws -> Int {
        try context.fetch(
            FetchDescriptor<VocabPackEntity>(predicate: #Predicate { $0.enabled == true })
        ).reduce(0) { $0 + $1.itemCount }
    }
}
