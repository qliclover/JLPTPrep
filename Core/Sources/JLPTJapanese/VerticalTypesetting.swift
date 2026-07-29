import Foundation

/// 竖排里连续的拉丁字母 / 数字怎么摆。
///
/// 日文竖排不会把 `2026` 拆成四个直立的字往下排 —— 那读起来像密码。
/// 规矩是：
/// - **两位以内**（`12`、`AB`）用**縦中横**：横着写，塞进一个字格，保持直立
/// - **更长**的整组旋转 90°，读的时候侧头
public enum TateChuYoko {

    /// 縦中横的长度上限。超过这个长度就整组旋转。
    /// 两位是日本印刷业界最常见的取值（年号、页码、两位数）。
    public static let maxUprightLength = 2

    public enum Mode: Equatable, Sendable {
        /// 普通日文字符，逐字直立。
        case japanese
        /// 縦中横：横排、直立、占一个字格。
        case upright
        /// 整组旋转 90°。
        case rotated
    }

    public struct Run: Equatable, Sendable {
        public var text: String
        public var mode: Mode
    }

    /// 判断一个字符是否属于「该横向成组」的那类（半角字母、数字）。
    public static func isHorizontalCandidate(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1
        else { return false }
        let value = Int(scalar.value)
        return (0x30...0x39).contains(value)   // 0-9
            || (0x41...0x5A).contains(value)   // A-Z
            || (0x61...0x7A).contains(value)   // a-z
    }

    /// 把一段文本切成竖排的排布单位。
    public static func runs(in text: String) -> [Run] {
        var result: [Run] = []
        var buffer = ""

        func flushLatin() {
            guard !buffer.isEmpty else { return }
            result.append(Run(
                text: buffer,
                mode: buffer.count <= maxUprightLength ? .upright : .rotated
            ))
            buffer = ""
        }

        for character in text {
            if isHorizontalCandidate(character) {
                buffer.append(character)
            } else {
                flushLatin()
                result.append(Run(text: String(character), mode: .japanese))
            }
        }
        flushLatin()
        return result
    }
}

/// 禁则处理：哪些字符不能出现在列首或列尾。
///
/// 没有这一步，`、` `。` `」` 会掉到下一列的开头 —— 中文和日文排版里这都是硬伤，
/// 一眼就看得出来是机器排的。
public enum LineBreakRules {

    /// 不能出现在**列首**的字符：句读点、收尾括号、小书き假名、长音符。
    private static let cannotStart: Set<Character> = [
        "、", "。", "，", "．", "・", "：", "；", "？", "！", "?", "!", ",", ".",
        "」", "』", "）", ")", "］", "]", "｝", "}", "〉", "》", "】", "〕",
        "ー", "ゝ", "ゞ", "々", "‥", "…",
        "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ", "ゎ",
        "ァ", "ィ", "ゥ", "ェ", "ォ", "ッ", "ャ", "ュ", "ョ", "ヮ", "ヵ", "ヶ",
    ]

    /// 不能出现在**列尾**的字符：开头括号。
    private static let cannotEnd: Set<Character> = [
        "「", "『", "（", "(", "［", "[", "｛", "{", "〈", "《", "【", "〔",
    ]

    public static func canStartColumn(_ character: Character) -> Bool {
        !cannotStart.contains(character)
    }

    public static func canEndColumn(_ character: Character) -> Bool {
        !cannotEnd.contains(character)
    }

    /// 调整一个候选断点，让它不违反禁则。
    ///
    /// - Parameters:
    ///   - firstCharacters: 每个排布单位的首字符（按顺序）。
    ///   - proposed: 想在哪个下标之前断开。
    /// - Returns: 调整后的断点。可能往前挪几位 —— 把该跟着上一列的字符留在上一列。
    ///
    /// 最多往前退 `maxShift` 位。退太多会让某一列明显短一截，比违反禁则更难看；
    /// 真正的排版引擎这时会改用压缩字距，那超出这里的范围。
    public static func adjustedBreak(
        firstCharacters: [Character],
        proposed: Int,
        maxShift: Int = 2
    ) -> Int {
        guard proposed > 0, proposed < firstCharacters.count else { return proposed }

        var index = proposed
        var shifted = 0
        while shifted < maxShift, index > 1 {
            let startsNext = firstCharacters[index]
            let endsCurrent = firstCharacters[index - 1]
            if canStartColumn(startsNext), canEndColumn(endsCurrent) { break }
            index -= 1
            shifted += 1
        }
        return index
    }
}
