import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// 从 PDF 里抽出可读文本。
///
/// 用系统的 PDFKit，零依赖。但要清楚它的边界：**PDF 是版式格式，不是文本格式**。
/// 抽出来的东西质量完全取决于原文件——
/// - 文字型 PDF（从 Word/TeX 导出）：能拿到准确文本
/// - 扫描件：一个字也拿不到，PDFKit 不做 OCR
/// - 竖排日文、分栏排版：文本顺序可能错乱
///
/// 所以这里的策略是**抽出来 + 老实报告拿到了多少**，让上层能判断是否值得导入，
/// 而不是假装每个 PDF 都能变成一本书。
public enum PDFTextExtractor {

    public struct Result: Equatable, Sendable {
        public var text: String
        public var pageCount: Int
        /// 抽出了文本的页数。远小于 `pageCount` 通常意味着这是扫描件。
        public var pagesWithText: Int

        public var isLikelyScanned: Bool {
            pageCount > 0 && Double(pagesWithText) / Double(pageCount) < 0.3
        }
    }

    public static var isSupported: Bool {
        #if canImport(PDFKit)
        return true
        #else
        return false
        #endif
    }

    /// `nil` 表示这份数据根本不是 PDF（或平台不支持）。
    public static func extract(from data: Data) -> Result? {
        #if canImport(PDFKit)
        guard let document = PDFDocument(data: data) else { return nil }

        var pieces: [String] = []
        var pagesWithText = 0

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index),
                  let raw = page.string
            else { continue }

            let cleaned = clean(raw)
            if !cleaned.isEmpty {
                pagesWithText += 1
                pieces.append(cleaned)
            }
        }

        return Result(
            text: pieces.joined(separator: "\n"),
            pageCount: document.pageCount,
            pagesWithText: pagesWithText
        )
        #else
        return nil
        #endif
    }

    /// PDF 抽出来的文本有两个通病要处理。
    static func clean(_ raw: String) -> String {
        var lines: [String] = []

        for line in raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        {
            var text = line
            // 1. 软连字符和零宽字符：PDF 排版留下的，肉眼看不见但会污染分词
            text = text.replacingOccurrences(of: "\u{00AD}", with: "")
            text = text.replacingOccurrences(of: "\u{200B}", with: "")
            text = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " \u{3000}\t"))
            if !text.isEmpty { lines.append(text) }
        }

        // 2. 日文 PDF 常常每显示一行就断一次行，把一个句子劈成好几段。
        //    按标点重新缝合：上一行不以句末标点结尾、且下一行不是新段落开头时，接上去。
        var merged: [String] = []
        for line in lines {
            if let last = merged.last, !endsSentence(last), !startsNewBlock(line) {
                merged[merged.count - 1] = last + line
            } else {
                merged.append(line)
            }
        }
        return merged.joined(separator: "\n")
    }

    private static func endsSentence(_ line: String) -> Bool {
        guard let last = line.last else { return true }
        return "。．.！!？?」』）)：:；;…".contains(last)
    }

    /// 行首是这些符号时多半是新的一段（对话、引用、列表），不该被缝到上一行。
    private static func startsNewBlock(_ line: String) -> Bool {
        guard let first = line.first else { return true }
        return "「『（(・■□◆◇＊*－-—".contains(first)
    }
}
