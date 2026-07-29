import Foundation

/// 一段振假名文本切出来的片段。
public enum FuriganaSegment: Equatable, Sendable {
    /// 不带注音的普通文本。
    case plain(String)
    /// 带注音：`base` 是汉字，`reading` 是假名。
    case ruby(base: String, reading: String)

    /// 去掉注音后的原文。
    public var base: String {
        switch self {
        case .plain(let text): text
        case .ruby(let base, _): base
        }
    }

    /// 全假名化之后的读法。
    public var reading: String {
        switch self {
        case .plain(let text): text
        case .ruby(_, let reading): reading
        }
    }
}

/// 解析 `{漢字|かんじ}` 格式的振假名标注。
///
/// 容错原则：**标注写坏了就当普通文本原样显示，绝不崩、绝不吞字**。
/// 内容是手工维护的，一个漏掉的 `}` 不该让整张卡片白屏；
/// 显示成 `{食|た` 反而能让人一眼看出哪条数据要修。
public enum FuriganaParser {
    public static func parse(_ text: String) -> [FuriganaSegment] {
        var segments: [FuriganaSegment] = []
        var plain = ""
        var index = text.startIndex

        func flushPlain() {
            if !plain.isEmpty {
                segments.append(.plain(plain))
                plain = ""
            }
        }

        while index < text.endIndex {
            guard text[index] == "{" else {
                plain.append(text[index])
                index = text.index(after: index)
                continue
            }

            // 尝试匹配 {base|reading}，任何一步不成立就把 "{" 当普通字符。
            guard let (base, reading, next) = matchGroup(in: text, from: index) else {
                plain.append(text[index])
                index = text.index(after: index)
                continue
            }

            flushPlain()
            segments.append(.ruby(base: base, reading: reading))
            index = next
        }

        flushPlain()
        return segments
    }

    /// 从 `{` 开始尝试读一组标注，成功则返回内容和下一个位置。
    private static func matchGroup(
        in text: String,
        from open: String.Index
    ) -> (base: String, reading: String, next: String.Index)? {
        var base = ""
        var reading = ""
        var seenPipe = false
        var index = text.index(after: open)

        while index < text.endIndex {
            let ch = text[index]
            switch ch {
            case "}":
                // 两边都得有内容，`{|か}` 或 `{漢|}` 视为写坏了。
                guard seenPipe, !base.isEmpty, !reading.isEmpty else { return nil }
                return (base, reading, text.index(after: index))
            case "|":
                guard !seenPipe else { return nil }  // 一组里只能有一个分隔符
                seenPipe = true
            case "{":
                return nil  // 不支持嵌套
            default:
                if seenPipe { reading.append(ch) } else { base.append(ch) }
            }
            index = text.index(after: index)
        }
        return nil  // 没闭合
    }

    /// 去掉全部注音：`{食|た}べる` → `食べる`
    public static func plainText(_ text: String) -> String {
        parse(text).map(\.base).joined()
    }

    /// 全部读作假名：`{食|た}べる` → `たべる`
    public static func readingText(_ text: String) -> String {
        parse(text).map(\.reading).joined()
    }
}
