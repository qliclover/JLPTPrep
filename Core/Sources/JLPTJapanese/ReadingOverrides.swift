import Foundation

/// 读音覆盖表：系统分词器读错时的兜底。
///
/// 需要它的原因是实测出来的：`CFStringTokenizer` 的错误几乎全是
/// **多音词挑了非常用读法**（日本→にっぽん、私→わたくし、明日→あす）
/// 和**切分把复合词拆散导致连浊丢失**（土曜日 → 土曜 + 日 → ようひ）。
/// 这两类都是封闭的小集合，一张表就能覆盖绝大部分。
///
/// 覆盖表支持跨 token 匹配：表里的 `土曜日` 会把分词器切出来的
/// `土曜` + `日` 合并回一个词再注音。
public struct ReadingOverrides: Sendable, Equatable {
    private var table: [String: String]

    /// 表中最长词条的字符数，决定合并 token 时最多往后看几个。
    private let maxKeyLength: Int

    public init(_ table: [String: String] = [:]) {
        self.table = table
        self.maxKeyLength = table.keys.map(\.count).max() ?? 0
    }

    public var isEmpty: Bool { table.isEmpty }
    public var count: Int { table.count }

    public func reading(for surface: String) -> String? {
        table[surface]
    }

    public func merging(_ other: ReadingOverrides) -> ReadingOverrides {
        ReadingOverrides(table.merging(other.table) { _, new in new })
    }

    /// 从若干 token 开始，找出能被覆盖表匹配的最长连续片段。
    /// 返回消耗的 token 数和对应读音；匹配不上返回 nil。
    func longestMatch(in tokens: [JapaneseToken], at index: Int) -> (length: Int, reading: String)? {
        guard maxKeyLength > 0, index < tokens.count else { return nil }

        var surface = ""
        var best: (Int, String)?
        for offset in 0..<(tokens.count - index) {
            surface += tokens[index + offset].surface
            if surface.count > maxKeyLength { break }
            if let reading = table[surface] {
                best = (offset + 1, reading)  // 继续往后找，取最长匹配
            }
        }
        return best
    }

    /// 内置的高频多音词表。
    ///
    /// **这张表的选词参考了 N5 样本例句上的实测错误**，所以用同一批句子
    /// 再测出来的准确率是偏乐观的（in-sample）。真实泛化能力要等有了
    /// 独立的验证语料才能定论 —— 别拿这个数字当承诺。
    ///
    /// 收录原则：日语里读法固定、但分词器容易挑错的常用词。
    /// 不收上下文相关的（如「一日」可读 ついたち 也可读 いちにち），
    /// 那种靠静态表修不了，只会引入新错。
    public static let common = ReadingOverrides([
        // 人称
        "私": "わたし",
        "僕": "ぼく",
        "貴方": "あなた",

        // 日本系：分词器强烈偏好 にっぽん
        "日本": "にほん",
        "日本語": "にほんご",
        "日本人": "にほんじん",

        // 星期：拆开后「日」会丢连浊读成 ひ
        "曜日": "ようび",
        "月曜日": "げつようび",
        "火曜日": "かようび",
        "水曜日": "すいようび",
        "木曜日": "もくようび",
        "金曜日": "きんようび",
        "土曜日": "どようび",
        "日曜日": "にちようび",

        // 日期相对词
        "今日": "きょう",
        "昨日": "きのう",
        "明日": "あした",
        "明後日": "あさって",
        "一昨日": "おととい",
        "今朝": "けさ",
        "今晩": "こんばん",
        "毎日": "まいにち",
        "毎朝": "まいあさ",
        "毎晩": "まいばん",

        // 时刻：四 / 七 / 九 的读法是固定的
        "四時": "よじ",
        "七時": "しちじ",
        "九時": "くじ",

        // 人数：一 / 二 / 四 的读法是固定的
        "一人": "ひとり",
        "二人": "ふたり",
        "四人": "よにん",

        // 月份
        "四月": "しがつ",
        "七月": "しちがつ",
        "九月": "くがつ",

        // 日数里的不规则读法。
        // 注意「一日」不在表里：ついたち（一号）和 いちにち（一天）都对，
        // 靠上下文才能分，静态表选哪个都会在另一半场合读错。
        "四日": "よっか",
        "八日": "ようか",
        "二十日": "はつか",

        // 其他高频不规则
        "大人": "おとな",
        "上手": "じょうず",
        "下手": "へた",
        "眼鏡": "めがね",
        "果物": "くだもの",
        "田舎": "いなか",
    ])
}
