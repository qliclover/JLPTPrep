import Foundation
import SwiftData
import JLPTJapanese

public enum BookImportError: Error, Equatable, LocalizedError {
    /// 所有候选编码都试过了，解不出可读文本。
    case undecodable(filename: String)
    /// 解出来是空的，或者全是空白。
    case emptyDocument(filename: String)
    /// PDF 打得开，但里面没有文字层 —— 多半是扫描件。
    case scannedPDF(filename: String, pageCount: Int)

    public var errorDescription: String? {
        switch self {
        case .undecodable(let name):
            "\(name) 的编码无法识别"
        case .emptyDocument(let name):
            "\(name) 里没有可读的文本"
        case .scannedPDF(let name, let pages):
            "\(name)（\(pages) 页）没有文字层，多半是扫描件"
        }
    }
}

public struct BookImportReport: Equatable, Sendable {
    public var title: String
    public var encodingName: String
    public var charCount: Int
    public var paragraphCount: Int
    public var hasEmbeddedRuby: Bool
    public var wasAozora: Bool
    public var wasPDF: Bool = false
    /// PDF 的页数，非 PDF 为 0。
    public var pageCount: Int = 0
}

/// 把用户选的文件变成一本可读的书。
public struct BookImporter {
    public init() {}

    @discardableResult
    public func importBook(
        data: Data,
        filename: String,
        into context: ModelContext,
        now: Date = Date()
    ) throws -> BookEntity {
        let (entity, _) = try makeBook(data: data, filename: filename, now: now)
        context.insert(entity)
        try context.save()
        return entity
    }

    /// 纯粹的「字节 → 书」转换，不碰数据库，方便单测。
    public func makeBook(
        data: Data,
        filename: String,
        now: Date = Date()
    ) throws -> (BookEntity, BookImportReport) {
        // PDF 先走 PDFKit 抽文本，之后和 txt 汇入同一条管线。
        // 判据是内容而不是扩展名 —— 用户改过扩展名的文件照样能认出来。
        if let pdf = PDFTextExtractor.extract(from: data) {
            guard !pdf.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !pdf.isLikelyScanned
            else {
                throw BookImportError.scannedPDF(filename: filename, pageCount: pdf.pageCount)
            }
            return try makeBook(
                fromText: pdf.text,
                filename: filename,
                encodingName: "PDF",
                now: now,
                pdfPageCount: pdf.pageCount
            )
        }

        guard let decoded = TextDecoder.decode(data) else {
            throw BookImportError.undecodable(filename: filename)
        }
        return try makeBook(
            fromText: decoded.text,
            filename: filename,
            encodingName: decoded.encodingName,
            now: now,
            pdfPageCount: 0
        )
    }

    private func makeBook(
        fromText source: String,
        filename: String,
        encodingName: String,
        now: Date,
        pdfPageCount: Int
    ) throws -> (BookEntity, BookImportReport) {
        let decoded = (text: source, encodingName: encodingName)

        // 先把行尾统一成 \n，之后所有环节都只需处理一种情况。
        //
        // 这一步是被真实文件逼出来的：青空文庫的 txt 是 CRLF，而
        // `components(separatedBy: .newlines)` 会把 `\r` 和 `\n` 当成两个分隔符，
        // 在中间切出一个空串。结果是作者行被空串顶掉，作者名混进了正文第一段。
        let normalized = decoded.text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let isAozora = AozoraMarkup.looksLikeAozora(normalized)
        let (title, author, body) = Self.splitFrontMatter(normalized, filename: filename, isAozora: isAozora)

        let cleaned = isAozora ? AozoraMarkup.normalize(body) : body
        let paragraphs = Self.paragraphs(of: cleaned)

        guard !paragraphs.isEmpty else {
            throw BookImportError.emptyDocument(filename: filename)
        }

        let text = paragraphs.joined(separator: "\n")
        // 清洗完还留着 `{...|...}` 就说明原文自带注音，阅读器可以省掉运行时分词。
        let hasEmbeddedRuby = text.contains("{") && text.contains("|")

        let entity = BookEntity(
            title: title,
            author: author,
            sourceFilename: filename,
            text: text,
            encodingName: decoded.encodingName,
            paragraphCount: paragraphs.count,
            hasEmbeddedRuby: hasEmbeddedRuby,
            importedAt: now
        )

        let report = BookImportReport(
            title: title,
            encodingName: decoded.encodingName,
            charCount: entity.charCount,
            paragraphCount: paragraphs.count,
            hasEmbeddedRuby: hasEmbeddedRuby,
            wasAozora: isAozora,
            wasPDF: pdfPageCount > 0,
            pageCount: pdfPageCount
        )
        return (entity, report)
    }

    // MARK: - 段落切分

    /// 按行切，丢掉空行，顺手把全角空格开头的缩进去掉。
    ///
    /// 日文原文常常整段不换行（一段就是一个超长的行），也常常每行都换行。
    /// 这里不去猜哪种，原样按行走 —— 猜错了重排会毁掉作者的分段。
    static func paragraphs(of text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \u{3000}\t")) }
            .filter { !$0.isEmpty }
    }

    // MARK: - 书名作者

    /// 青空文庫的头两行是书名和作者。别的格式就用文件名当书名。
    static func splitFrontMatter(
        _ text: String,
        filename: String,
        isAozora: Bool
    ) -> (title: String, author: String?, body: String) {
        let fallbackTitle = (filename as NSString).deletingPathExtension
        guard isAozora else {
            return (fallbackTitle.isEmpty ? filename : fallbackTitle, nil, text)
        }

        var lines = text.components(separatedBy: .newlines)
        // 跳过开头的空行
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        guard let titleLine = lines.first?.trimmingCharacters(in: .whitespaces), !titleLine.isEmpty else {
            return (fallbackTitle.isEmpty ? filename : fallbackTitle, nil, text)
        }

        // 书名行不该太长，也不该以句号结尾 —— 那多半已经是正文了。
        guard titleLine.count <= 40, !titleLine.hasSuffix("。") else {
            return (fallbackTitle.isEmpty ? filename : fallbackTitle, nil, text)
        }

        var author: String?
        var bodyStart = 1
        if lines.count > 1 {
            let second = lines[1].trimmingCharacters(in: .whitespaces)
            if !second.isEmpty, second.count <= 30, !second.hasSuffix("。") {
                author = second
                bodyStart = 2
            }
        }

        return (titleLine, author, lines.dropFirst(bodyStart).joined(separator: "\n"))
    }
}
