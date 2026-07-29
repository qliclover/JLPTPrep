import Foundation
import SwiftData
import JLPTCore

/// 学习进度的导出与恢复。
///
/// 存在的理由很朴素：从现在到考试是几个月的投入，而这些数据**只在一台手机上**。
/// 手机丢了、误删了 App、系统还原选错了备份 —— 全部归零，没有第二份。
///
/// 三条设计原则：
///
/// - **只备份「攒出来的」，不备份「装得回的」**。SRS 状态、复习日志、笔记、
///   阅读进度是你花时间攒的；词库和随包书籍重装就有，没必要塞进文件。
///   用户自己导入的书**要备份**（含正文）—— 原文件可能早就删了。
/// - **恢复是合并，不是覆盖**。导入一份旧备份不该抹掉这之后学的东西。
///   同一张卡两边都有时，取**最近复习过**的那一份。
/// - **格式是可读的 JSON**。出问题时你能自己打开看，也能自己改。
///   二进制归档在这种场景下只是把故障变得不可调查。
public enum ProgressArchive {

    /// 当前格式版本。恢复时拒绝比自己新的版本 —— 那意味着字段可能不认识，
    /// 硬吃下去会静默丢数据。
    public static let currentVersion = 1

    // MARK: - 文件结构

    public struct Archive: Codable {
        public var version: Int
        public var exportedAt: Date
        public var items: [Item]
        public var logs: [Log]
        public var notes: [Note]
        public var books: [Book]
    }

    public struct Item: Codable {
        public var uuid: UUID
        public var kind: String
        public var slug: String
        public var level: String
        public var packID: String
        public var easeFactor: Double
        public var intervalDays: Int
        public var repetitions: Int
        public var lapses: Int
        public var dueDate: Date?
        public var stage: String
        public var stepIndex: Int
        public var correctStreak: Int
        public var lastReviewedAt: Date?
        public var introducedAt: Date?
        public var isSuspended: Bool
        public var isStarred: Bool
        public var createdAt: Date
    }

    public struct Log: Codable {
        public var id: UUID
        public var itemUUID: UUID
        public var rating: Int
        public var reviewedAt: Date
        public var stageBefore: String
        public var stageAfter: String
        public var intervalBeforeDays: Int
        public var intervalAfterDays: Int
        public var easeBefore: Double
        public var easeAfter: Double
    }

    public struct Note: Codable {
        public var uuid: UUID
        public var bookUUID: UUID
        public var paragraphIndex: Int
        public var quotedText: String
        public var body: String
        public var createdAt: Date
    }

    public struct Book: Codable {
        public var uuid: UUID
        public var title: String
        public var author: String?
        public var sourceFilename: String
        public var encodingName: String
        public var paragraphIndex: Int
        public var lastOpenedAt: Date?
        public var importedAt: Date
        public var hasEmbeddedRuby: Bool
        /// 正文。随包书籍留空 —— 重装就有，塞进去只是让文件白白大几 MB。
        public var text: String?
    }

    // MARK: - 导出

    /// 随包书籍的文件名。它们的正文不进备份。
    static let bundledFilenames: Set<String> = [
        "kumo_no_ito.txt", "rashomon.txt", "toshishun.txt", "hashire_melos.txt",
        "chumon_no_oi_ryoriten.txt", "cello_hiki_no_goshu.txt",
        "gon_gitsune.txt", "tebukuro_wo_kai_ni.txt", "sample_reading.txt",
    ]

    public static func export(from context: ModelContext, now: Date = Date()) throws -> Archive {
        let items = try context.fetch(FetchDescriptor<ReviewItemEntity>()).map {
            Item(
                uuid: $0.uuid, kind: $0.kindRaw, slug: $0.contentSlug, level: $0.levelRaw,
                packID: $0.packID, easeFactor: $0.easeFactor, intervalDays: $0.intervalDays,
                repetitions: $0.repetitions, lapses: $0.lapses, dueDate: $0.dueDate,
                stage: $0.stageRaw, stepIndex: $0.stepIndex, correctStreak: $0.correctStreak,
                lastReviewedAt: $0.lastReviewedAt, introducedAt: $0.introducedAt,
                isSuspended: $0.isSuspended, isStarred: $0.isStarred, createdAt: $0.createdAt
            )
        }
        let logs = try context.fetch(FetchDescriptor<ReviewLogEntity>()).map {
            Log(
                id: $0.id, itemUUID: $0.itemUUID, rating: $0.ratingRaw, reviewedAt: $0.reviewedAt,
                stageBefore: $0.stageBeforeRaw, stageAfter: $0.stageAfterRaw,
                intervalBeforeDays: $0.intervalBeforeDays, intervalAfterDays: $0.intervalAfterDays,
                easeBefore: $0.easeBefore, easeAfter: $0.easeAfter
            )
        }
        let notes = try context.fetch(FetchDescriptor<NoteEntity>()).map {
            Note(
                uuid: $0.uuid, bookUUID: $0.bookUUID, paragraphIndex: $0.paragraphIndex,
                quotedText: $0.quotedText, body: $0.body, createdAt: $0.createdAt
            )
        }
        let books = try context.fetch(FetchDescriptor<BookEntity>()).map { book in
            Book(
                uuid: book.uuid, title: book.title, author: book.author,
                sourceFilename: book.sourceFilename, encodingName: book.encodingName,
                paragraphIndex: book.paragraphIndex, lastOpenedAt: book.lastOpenedAt,
                importedAt: book.importedAt, hasEmbeddedRuby: book.hasEmbeddedRuby,
                text: bundledFilenames.contains(book.sourceFilename) ? nil : book.text
            )
        }
        return Archive(
            version: currentVersion, exportedAt: now,
            items: items, logs: logs, notes: notes, books: books
        )
    }

    public static func encode(_ archive: Archive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(archive)
    }

    public static func decode(_ data: Data) throws -> Archive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Archive.self, from: data)
        guard archive.version <= currentVersion else {
            throw ArchiveError.unsupportedVersion(archive.version)
        }
        return archive
    }

    // MARK: - 恢复

    public struct RestoreReport: Equatable {
        public var itemsUpdated = 0
        public var itemsSkipped = 0
        public var logsInserted = 0
        public var notesInserted = 0
        public var booksInserted = 0
    }

    /// 把备份合并回当前库。
    ///
    /// 合并规则：
    ///
    /// - **卡片**按 `key`（种类+slug）匹配。两边都有时比 `lastReviewedAt`，
    ///   取更近的那一份 —— 你不会希望导入一份上周的备份，把这周学的全推回去。
    ///   库里没有这张卡（词包没启用、或备份来自更高等级）就跳过，不凭空造卡。
    /// - **日志 / 笔记 / 书**按 UUID 去重，只补不改。
    ///   日志是只增不改的事实记录，笔记和书改动了以现有的为准。
    /// 备份里的这张卡和库里的完全一致吗。
    private static func isIdentical(_ item: ReviewItemEntity, _ backup: Item) -> Bool {
        item.easeFactor == backup.easeFactor
            && item.intervalDays == backup.intervalDays
            && item.repetitions == backup.repetitions
            && item.lapses == backup.lapses
            && item.dueDate == backup.dueDate
            && item.stageRaw == backup.stage
            && item.stepIndex == backup.stepIndex
            && item.correctStreak == backup.correctStreak
            && item.lastReviewedAt == backup.lastReviewedAt
            && item.introducedAt == backup.introducedAt
            && item.isSuspended == backup.isSuspended
            && item.isStarred == backup.isStarred
    }

    @discardableResult
    public static func restore(_ archive: Archive, into context: ModelContext) throws -> RestoreReport {
        var report = RestoreReport()

        // MARK: 卡片
        let existingItems = try context.fetch(FetchDescriptor<ReviewItemEntity>())
        var itemsByKey = Dictionary(
            existingItems.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for backup in archive.items {
            let kind = ReviewItemKind(rawValue: backup.kind) ?? .vocab
            let key = ReviewItemEntity.key(kind: kind, slug: backup.slug)
            guard let item = itemsByKey[key] else {
                report.itemsSkipped += 1
                continue
            }
            // 一模一样就别动它。把 1382 张卡全标脏再写回同样的值，
            // 只是白白落一次盘 —— 而且会让「更新了 1382 个词」这种报告失去意义。
            if isIdentical(item, backup) {
                report.itemsSkipped += 1
                continue
            }
            // 本地更新就别退回去。没复习过按「无穷早」算，
            // 这样从没学过的卡总是接受备份里的进度。
            let mine = item.lastReviewedAt ?? .distantPast
            let theirs = backup.lastReviewedAt ?? .distantPast
            if mine > theirs {
                report.itemsSkipped += 1
                continue
            }
            item.easeFactor = backup.easeFactor
            item.intervalDays = backup.intervalDays
            item.repetitions = backup.repetitions
            item.lapses = backup.lapses
            item.dueDate = backup.dueDate
            item.stageRaw = backup.stage
            item.stepIndex = backup.stepIndex
            item.correctStreak = backup.correctStreak
            item.lastReviewedAt = backup.lastReviewedAt
            item.introducedAt = backup.introducedAt
            item.isSuspended = backup.isSuspended
            item.isStarred = backup.isStarred
            report.itemsUpdated += 1
        }
        itemsByKey.removeAll()

        // MARK: 日志
        let existingLogIDs = Set(try context.fetch(FetchDescriptor<ReviewLogEntity>()).map(\.id))
        for backup in archive.logs where !existingLogIDs.contains(backup.id) {
            context.insert(ReviewLogEntity(log: ReviewLog(
                id: backup.id, itemID: backup.itemUUID,
                rating: Rating(rawValue: backup.rating) ?? .good,
                reviewedAt: backup.reviewedAt,
                stageBefore: LearningStage(rawValue: backup.stageBefore) ?? .review,
                stageAfter: LearningStage(rawValue: backup.stageAfter) ?? .review,
                intervalBeforeDays: backup.intervalBeforeDays,
                intervalAfterDays: backup.intervalAfterDays,
                easeBefore: backup.easeBefore, easeAfter: backup.easeAfter
            )))
            report.logsInserted += 1
        }

        // MARK: 书（先于笔记 —— 笔记要挂在书上）
        let existingBookIDs = Set(try context.fetch(FetchDescriptor<BookEntity>()).map(\.uuid))
        for backup in archive.books where !existingBookIDs.contains(backup.uuid) {
            // 随包书籍不带正文；库里又没有，说明这份备份来自装了别的书的设备，
            // 或者随包内容变了。没有正文就还原不出可读的书，跳过。
            guard let text = backup.text, !text.isEmpty else { continue }
            let book = BookEntity(
                uuid: backup.uuid, title: backup.title, author: backup.author,
                sourceFilename: backup.sourceFilename, text: text,
                encodingName: backup.encodingName,
                // 段落数从正文重新数，不从备份里读 —— 分段规则改过的话，
                // 存下来的旧计数会和实际段落对不上，笔记跳转就会越界。
                paragraphCount: text.components(separatedBy: "\n").count,
                hasEmbeddedRuby: backup.hasEmbeddedRuby,
                importedAt: backup.importedAt
            )
            book.paragraphIndex = backup.paragraphIndex
            book.lastOpenedAt = backup.lastOpenedAt
            context.insert(book)
            report.booksInserted += 1
        }

        // MARK: 笔记
        let existingNoteIDs = Set(try context.fetch(FetchDescriptor<NoteEntity>()).map(\.uuid))
        for backup in archive.notes where !existingNoteIDs.contains(backup.uuid) {
            context.insert(NoteEntity(
                uuid: backup.uuid, bookUUID: backup.bookUUID,
                paragraphIndex: backup.paragraphIndex, quotedText: backup.quotedText,
                body: backup.body, createdAt: backup.createdAt
            ))
            report.notesInserted += 1
        }

        try context.save()
        return report
    }
}

public enum ArchiveError: LocalizedError {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "备份文件的格式版本是 \(version)，这个版本的 App 只认到 \(ProgressArchive.currentVersion)。请先把 App 更新到最新版。"
        }
    }
}
