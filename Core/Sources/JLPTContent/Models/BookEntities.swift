import Foundation
import SwiftData

/// 一本导入的书。
///
/// 全文存在一个字段里，段落在读取时切分，而不是每段一行数据库记录。
/// 一部长篇小说有几千个段落，做成几千行 SwiftData 记录会让导入和查询都变慢，
/// 而按 `\n` 切几万字的字符串是毫秒级的事。
@Model
public final class BookEntity {
    @Attribute(.unique) public var uuid: UUID
    public var title: String
    public var author: String?
    public var sourceFilename: String
    /// 正文。段落之间用单个 `\n` 分隔，导入时已经归一化。
    public var text: String
    public var encodingName: String
    public var charCount: Int
    public var paragraphCount: Int
    public var importedAt: Date
    public var lastOpenedAt: Date?
    /// 阅读位置（段落下标）。
    public var paragraphIndex: Int
    /// 原文自带注音（青空文庫）。为真时阅读器直接用原文标注，
    /// 不跑运行时分词 —— 人工标的比猜的准。
    public var hasEmbeddedRuby: Bool

    /// 切出全部段落。
    ///
    /// **这是个 O(全文) 的操作**，300 万字的书要 ~50ms。故意写成方法而不是属性 ——
    /// 属性看着像随手可取，放进视图 body 或循环里就会卡死。
    /// 调用方应该调一次、存下来。
    public func splitParagraphs() -> [String] {
        text.components(separatedBy: "\n")
    }

    /// 读到哪儿了，0...1。
    public var progress: Double {
        guard paragraphCount > 1 else { return paragraphIndex > 0 ? 1 : 0 }
        return min(1, Double(paragraphIndex) / Double(paragraphCount - 1))
    }

    public init(
        uuid: UUID = UUID(),
        title: String,
        author: String? = nil,
        sourceFilename: String,
        text: String,
        encodingName: String,
        paragraphCount: Int,
        hasEmbeddedRuby: Bool,
        importedAt: Date = Date()
    ) {
        self.uuid = uuid
        self.title = title
        self.author = author
        self.sourceFilename = sourceFilename
        self.text = text
        self.encodingName = encodingName
        self.charCount = text.count
        self.paragraphCount = paragraphCount
        self.importedAt = importedAt
        self.lastOpenedAt = nil
        self.paragraphIndex = 0
        self.hasEmbeddedRuby = hasEmbeddedRuby
    }
}

/// 读书笔记。挂在段落上而不是字符偏移上 —— 段落下标在正文不变时是稳定的，
/// 而字符偏移一旦重新导入（换了个编码、修了个清洗规则）就会全部错位。
@Model
public final class NoteEntity {
    public var uuid: UUID
    public var bookUUID: UUID
    public var paragraphIndex: Int
    /// 划选的原文片段。冗余存一份，这样笔记列表不用回去翻正文。
    public var quotedText: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        uuid: UUID = UUID(),
        bookUUID: UUID,
        paragraphIndex: Int,
        quotedText: String,
        body: String,
        createdAt: Date = Date()
    ) {
        self.uuid = uuid
        self.bookUUID = bookUUID
        self.paragraphIndex = paragraphIndex
        self.quotedText = quotedText
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
