import Foundation

/// 青空文庫 TXT 格式的解析。
///
/// 值得专门支持的原因：青空文庫的注音是**人工标注**的，比我们运行时分词生成的准得多。
/// 只要原文带 `漢字《かんじ》`，就该用它，不该再去猜。
///
/// 处理三样东西：
/// - 注音 `｜漢字《かんじ》` / `漢字《かんじ》` → `{漢字|かんじ}`
/// - 注记 `［＃「〜」に傍点］` → 删除（排版指令，对阅读没用）
/// - 文件头的凡例块和文末的底本信息 → 删除
public enum AozoraMarkup {

    private static let rubyOpen: Character = "《"
    private static let rubyClose: Character = "》"
    private static let rubyBase: Character = "｜"     // U+FF5C 全角竖线
    private static let noteOpen = "［＃"
    private static let noteClose: Character = "］"

    /// 注音、注音对象、注记各自的长度上界。
    ///
    /// 这三个常量不是为了省事，是**复杂度的保险丝**。用户可以导入任何文件，
    /// 包括一整本没有换行、或者散落着几万个孤立「《」的文本。
    /// 没有上界的话，每个孤立开括号都要扫到文末去找不存在的闭括号，
    /// 整体退化成 O(n²) —— 实测 6 万个孤立「《」能让解析跑上几分钟。
    ///
    /// 取值依据是这些标记的语义：注音是词级的，注记是排版指令，都不可能很长。
    private static let maxRubyReadingLength = 32
    private static let maxRubyBaseLength = 64
    private static let maxNoteLength = 256

    /// 这份文本看起来像不像青空文庫格式。
    public static func looksLikeAozora(_ text: String) -> Bool {
        let head = text.prefix(4000)
        return head.contains(rubyOpen) || head.contains(noteOpen) || head.contains("底本：")
    }

    /// 全套清洗：去头尾 → 去注记 → 注音转成我们的 `{漢字|かんじ}` 格式。
    public static func normalize(_ text: String) -> String {
        convertRuby(stripNotes(stripBoilerplate(text)))
    }

    // MARK: - 注音

    /// `｜漢字《かんじ》` 和 `漢字《かんじ》` 都转成 `{漢字|かんじ}`。
    ///
    /// 省略 `｜` 时，注音默认落在紧邻的那串汉字上 —— 这是青空文庫的约定，
    /// 也正是为什么「｜」存在：`大人《おとな》` 不用写竖线，
    /// 但 `やって来《き》た` 里如果不写竖线，注音会错误地只盖住「来」以外什么都没有。
    public static func convertRuby(_ text: String) -> String {
        var out: [Character] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            guard character == rubyOpen,
                  let close = closingBracket(in: text, after: index)
            else {
                out.append(character)
                index = text.index(after: index)
                continue
            }

            let reading = String(text[text.index(after: index)..<close])
            if let base = takeBase(from: &out), !reading.isEmpty {
                out.append(contentsOf: "{\(base)|\(reading)}")
            } else {
                // 找不到注音对象（比如行首就是《》），原样保留，别把字吃了。
                out.append(character)
                out.append(contentsOf: reading)
                out.append(rubyClose)
            }
            index = text.index(after: close)
        }
        return String(out)
    }

    /// 在 `《` 之后有限范围内找配对的 `》`。
    ///
    /// 中途遇到换行或另一个 `《` 就判定为没配对 —— 注音不会跨行，
    /// 也不会套着另一个注音开头。
    private static func closingBracket(in text: String, after open: String.Index) -> String.Index? {
        var index = text.index(after: open)
        var steps = 0
        while index < text.endIndex, steps < maxRubyReadingLength {
            switch text[index] {
            case rubyClose: return index
            case "\n", rubyOpen: return nil
            default: break
            }
            index = text.index(after: index)
            steps += 1
        }
        return nil
    }

    /// 从已输出的字符里取走注音对象，返回它。回溯范围同样有上界。
    private static func takeBase(from out: inout [Character]) -> String? {
        let floor = max(0, out.count - maxRubyBaseLength)

        // 优先找显式的 ｜ 标记，遇到换行就停（注音对象不跨行）
        var cursor = out.count - 1
        while cursor >= floor {
            if out[cursor] == "\n" { break }
            if out[cursor] == rubyBase {
                let base = String(out[(cursor + 1)...])
                out.removeSubrange(cursor...)
                return base.isEmpty ? nil : base
            }
            cursor -= 1
        }

        // 否则取结尾那串连续汉字
        var count = 0
        var index = out.count - 1
        while index >= floor, out[index].unicodeScalars.contains(where: Kana.isKanji) {
            count += 1
            index -= 1
        }
        guard count > 0 else { return nil }
        let base = String(out.suffix(count))
        out.removeLast(count)
        return base
    }

    // MARK: - 注记

    /// 删掉 `［＃...］` 排版指令。它们描述的是纸书版式（改行、字号、傍点），阅读器用不上。
    public static func stripNotes(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)

        while let start = rest.range(of: noteOpen) {
            out += rest[rest.startIndex..<start.lowerBound]

            // 同样限长：孤立的「［＃」不该触发一次全文扫描。
            let window = rest[start.upperBound...].prefix(maxNoteLength)
            guard let end = window.firstIndex(of: noteClose) else {
                // 没闭合就当普通文本，把这个标记原样输出，继续处理后面的内容。
                // 直接 return 会让后面真正的注记漏掉。
                out += rest[start.lowerBound..<start.upperBound]
                rest = rest[start.upperBound...]
                continue
            }
            rest = rest[rest.index(after: end)...]
        }
        return out + rest
    }

    // MARK: - 页眉页脚

    /// 删掉文件头的凡例块（两条长横线之间）和文末的底本信息。
    public static func stripBoilerplate(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)

        // 凡例块：只在文件前部找，正文里出现的长横线是分隔符，不能动。
        let searchLimit = min(lines.count, 60)
        let fences = (0..<searchLimit).filter { isFence(lines[$0]) }
        if fences.count >= 2 {
            lines.removeSubrange(fences[0]...fences[1])
        }

        // 底本信息：从「底本：」那一行到文末。
        if let colophon = lines.firstIndex(where: { $0.hasPrefix("底本：") }) {
            lines.removeSubrange(colophon...)
        }

        return lines.joined(separator: "\n")
    }

    private static func isFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 20 else { return false }
        return trimmed.allSatisfy { $0 == "-" || $0 == "－" || $0 == "―" || $0 == "ー" }
    }
}
