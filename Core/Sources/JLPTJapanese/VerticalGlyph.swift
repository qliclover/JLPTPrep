import Foundation

/// 竖排时单个字符要怎么摆。
///
/// 日文竖排不是把横排文字换个方向堆一堆就完事：
/// - `ー～…（「【` 这类**延伸和括号类**字符要旋转 90°，否则长音符会横躺在字中间
/// - `、。` 这类**标点**要挪到字格的右上角，不能留在中间
/// - 小书きの假名（`ゃゅょっ`）同样偏右上
///
/// 汉字和普通假名本来就是直立的，什么都不用做 —— 这也是为什么设计交接里特别写了
/// 「不要加 text-orientation: upright」。
public enum VerticalGlyph {

    public struct Placement: Equatable, Sendable {
        /// 旋转角度（度）。0 表示直立。
        public var rotation: Double
        /// 在字格里的偏移，单位是字号的倍数。正值向右 / 向下。
        public var offsetX: Double
        public var offsetY: Double

        public static let upright = Placement(rotation: 0, offsetX: 0, offsetY: 0)
    }

    /// 需要旋转 90° 的字符：延伸记号、破折号、各类括号。
    private static let rotated: Set<Character> = [
        "ー", "〜", "～", "―", "─", "－", "‐", "—", "…", "‥", "⋯",
        "（", "）", "(", ")", "「", "」", "『", "』", "【", "】",
        "〔", "〕", "［", "］", "｛", "｝", "〈", "〉", "《", "》",
        "〖", "〗", "｟", "｠",
    ]

    /// 挪到右上角的字符：句读点。
    private static let cornered: Set<Character> = ["、", "。", "，", "．", ",", "."]

    /// 小书き假名。竖排里同样偏右上，但幅度比句读点小。
    private static let smallKana: Set<Character> = [
        "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ", "ゎ",
        "ァ", "ィ", "ゥ", "ェ", "ォ", "ッ", "ャ", "ュ", "ョ", "ヮ", "ヵ", "ヶ",
    ]

    public static func placement(for character: Character) -> Placement {
        if rotated.contains(character) {
            return Placement(rotation: 90, offsetX: 0, offsetY: 0)
        }
        if cornered.contains(character) {
            // 句读点在竖排里贴字格右上
            return Placement(rotation: 0, offsetX: 0.32, offsetY: -0.36)
        }
        if smallKana.contains(character) {
            return Placement(rotation: 0, offsetX: 0.1, offsetY: -0.08)
        }
        return .upright
    }

    public static func needsRotation(_ character: Character) -> Bool {
        rotated.contains(character)
    }
}
