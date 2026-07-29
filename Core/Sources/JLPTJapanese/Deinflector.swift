import Foundation

/// 词类。分析结果里用来告诉用户「这是个二类动词」。
public enum WordClass: String, Codable, Sendable, CaseIterable {
    case godan          // 一类动词（五段）
    case ichidan        // 二类动词（一段）
    case suru           // 三类动词 する
    case kuru           // 三类动词 来る
    case iAdjective
    case naAdjective
    case unknown

    public var labelZh: String {
        switch self {
        case .godan: "动词·一类"
        case .ichidan: "动词·二类"
        case .suru: "动词·三类（する）"
        case .kuru: "动词·三类（来る）"
        case .iAdjective: "い形容词"
        case .naAdjective: "な形容词"
        case .unknown: "—"
        }
    }
}

/// 一个还原结果：这个表面形是由哪个原形、经过哪些变形来的。
public struct Deinflection: Equatable, Sendable {
    /// 还原出的原形（辞書形）。
    public var dictionaryForm: String
    /// 变形说明，按「离原形由近到远」排列。
    /// `食べました` 得到 `["ます形", "过去"]`。
    public var steps: [String]
    public var wordClass: WordClass

    /// 表面形本身就是原形，没有发生变形。
    public var isBaseForm: Bool { steps.isEmpty }

    public var stepsLabel: String {
        steps.isEmpty ? "原形" : steps.joined(separator: " · ")
    }
}

/// 日语活用还原。
///
/// 规则驱动，不依赖词典 —— 这是刻意的：词库覆盖不到的词（人名以外的绝大多数生词），
/// 光知道「这是 `食べる` 的ます形过去」就已经解决了阅读中最大的障碍。
/// 释义可以没有，活用不能不认。
///
/// 因为不查词典，某些变形天然有歧义：`買った` 可以还原成 `買う`、`勝つ`、`借る`。
/// 所以返回的是**候选列表**，并允许调用方传入「这个词在词库里吗」来排序。
public enum Deinflector {

    // 五段动词的词尾在五十音图上按行变化，规则表按这些对应关系生成。
    private static let uRow = ["う", "く", "ぐ", "す", "つ", "ぬ", "ぶ", "む", "る"]
    private static let iRow = ["い", "き", "ぎ", "し", "ち", "に", "び", "み", "り"]
    private static let aRow = ["わ", "か", "が", "さ", "た", "な", "ば", "ま", "ら"]
    private static let eRow = ["え", "け", "げ", "せ", "て", "ね", "べ", "め", "れ"]
    private static let oRow = ["お", "こ", "ご", "そ", "と", "の", "ぼ", "も", "ろ"]

    struct Rule {
        let suffix: String
        let replacement: String
        let label: String
        let wordClass: WordClass
        /// 后缀里已经包含了词根（`します → する`、`行った → 行く`）。
        /// 这类规则允许词干为空 —— 整个词就是后缀本身。
        /// 普通规则必须有非空词干，否则孤零零一个「ます」会被还原成「る」。
        var containsRoot: Bool = false
    }

    // MARK: - 规则表

    static let rules: [Rule] = {
        var rules: [Rule] = []

        // ── 五段：ます形系列（い段接续）
        for (i, u) in zip(iRow, uRow) {
            rules += [
                Rule(suffix: i + "ませんでした", replacement: u, label: "ます形 · 过去否定", wordClass: .godan),
                Rule(suffix: i + "ません", replacement: u, label: "ます形 · 否定", wordClass: .godan),
                Rule(suffix: i + "ました", replacement: u, label: "ます形 · 过去", wordClass: .godan),
                Rule(suffix: i + "ましょう", replacement: u, label: "ましょう（劝诱）", wordClass: .godan),
                Rule(suffix: i + "ます", replacement: u, label: "ます形", wordClass: .godan),
                Rule(suffix: i + "たかった", replacement: u, label: "たい形 · 过去", wordClass: .godan),
                Rule(suffix: i + "たい", replacement: u, label: "たい形（想做）", wordClass: .godan),
                Rule(suffix: i + "ながら", replacement: u, label: "ながら（一边…）", wordClass: .godan),
            ]
        }

        // ── 五段：否定・被动・使役（あ段接续）
        for (a, u) in zip(aRow, uRow) {
            rules += [
                Rule(suffix: a + "なかった", replacement: u, label: "否定 · 过去", wordClass: .godan),
                Rule(suffix: a + "ない", replacement: u, label: "否定形", wordClass: .godan),
                Rule(suffix: a + "せる", replacement: u, label: "使役形", wordClass: .godan),
                Rule(suffix: a + "れる", replacement: u, label: "被动形", wordClass: .godan),
                Rule(suffix: a + "ず", replacement: u, label: "ず（否定）", wordClass: .godan),
            ]
        }

        // ── 五段：可能・条件（え段接续）
        for (e, u) in zip(eRow, uRow) {
            rules += [
                Rule(suffix: e + "ば", replacement: u, label: "ば形（条件）", wordClass: .godan),
                Rule(suffix: e + "る", replacement: u, label: "可能形", wordClass: .godan),
            ]
        }

        // ── 五段：意志形（お段接续）
        for (o, u) in zip(oRow, uRow) {
            rules.append(Rule(suffix: o + "う", replacement: u, label: "意志形", wordClass: .godan))
        }

        // ── 五段：て形 / た形。词尾按音便分组，「った」「んだ」天然有歧义，全部列为候选。
        let teTa: [(String, [String])] = [
            ("いて", ["く"]), ("いた", ["く"]),
            ("いで", ["ぐ"]), ("いだ", ["ぐ"]),
            ("して", ["す"]), ("した", ["す"]),
            ("って", ["つ", "う", "る"]), ("った", ["つ", "う", "る"]),
            ("んで", ["ぬ", "ぶ", "む"]), ("んだ", ["ぬ", "ぶ", "む"]),
        ]
        for (suffix, candidates) in teTa {
            let label = suffix.hasSuffix("て") || suffix.hasSuffix("で") ? "て形" : "过去形"
            for candidate in candidates {
                rules.append(Rule(suffix: suffix, replacement: candidate, label: label, wordClass: .godan))
            }
        }
        // 行く 是唯一的促音便例外（本该是「行いて」）
        rules += [
            Rule(suffix: "行って", replacement: "行く", label: "て形", wordClass: .godan, containsRoot: true),
            Rule(suffix: "行った", replacement: "行く", label: "过去形", wordClass: .godan, containsRoot: true),
            Rule(suffix: "いって", replacement: "いく", label: "て形", wordClass: .godan, containsRoot: true),
            Rule(suffix: "いった", replacement: "いく", label: "过去形", wordClass: .godan, containsRoot: true),
        ]

        // ── 一段动词：直接去掉 る 接续
        let ichidan: [(String, String)] = [
            ("ませんでした", "ます形 · 过去否定"), ("ません", "ます形 · 否定"),
            ("ました", "ます形 · 过去"), ("ましょう", "ましょう（劝诱）"), ("ます", "ます形"),
            ("たかった", "たい形 · 过去"), ("たい", "たい形（想做）"), ("ながら", "ながら（一边…）"),
            ("なかった", "否定 · 过去"), ("ない", "否定形"),
            ("させる", "使役形"), ("られる", "被动 / 可能形"),
            ("れば", "ば形（条件）"), ("よう", "意志形"),
            ("て", "て形"), ("た", "过去形"),
        ]
        for (suffix, label) in ichidan {
            rules.append(Rule(suffix: suffix, replacement: "る", label: label, wordClass: .ichidan))
        }

        // ── ている 系列：先归约到て形，再由上面的规则继续还原
        for (te, de) in [("て", "で")] {
            for (suffix, label) in [
                ("いました", "ている · ます过去"), ("います", "ている · ます形"),
                ("いた", "ている · 过去"), ("いる", "ている（进行 / 状态）"),
                ("る", "てる（口语进行）"),
            ] {
                rules.append(Rule(suffix: te + suffix, replacement: te, label: label, wordClass: .unknown))
                rules.append(Rule(suffix: de + suffix, replacement: de, label: label, wordClass: .unknown))
            }
        }

        // ── い形容词
        rules += [
            Rule(suffix: "くなかった", replacement: "い", label: "否定 · 过去", wordClass: .iAdjective),
            Rule(suffix: "くありません", replacement: "い", label: "否定（礼貌）", wordClass: .iAdjective),
            Rule(suffix: "くない", replacement: "い", label: "否定形", wordClass: .iAdjective),
            Rule(suffix: "かった", replacement: "い", label: "过去形", wordClass: .iAdjective),
            Rule(suffix: "くて", replacement: "い", label: "て形", wordClass: .iAdjective),
            Rule(suffix: "ければ", replacement: "い", label: "ば形（条件）", wordClass: .iAdjective),
            Rule(suffix: "く", replacement: "い", label: "副词形", wordClass: .iAdjective),
        ]

        // ── な形容词 / 名词 + です
        rules += [
            Rule(suffix: "ではありませんでした", replacement: "", label: "否定 · 过去（礼貌）", wordClass: .naAdjective),
            Rule(suffix: "ではありません", replacement: "", label: "否定（礼貌）", wordClass: .naAdjective),
            Rule(suffix: "じゃなかった", replacement: "", label: "否定 · 过去", wordClass: .naAdjective),
            Rule(suffix: "ではなかった", replacement: "", label: "否定 · 过去", wordClass: .naAdjective),
            Rule(suffix: "じゃない", replacement: "", label: "否定形", wordClass: .naAdjective),
            Rule(suffix: "ではない", replacement: "", label: "否定形", wordClass: .naAdjective),
            Rule(suffix: "でした", replacement: "", label: "过去（礼貌）", wordClass: .naAdjective),
            Rule(suffix: "だった", replacement: "", label: "过去形", wordClass: .naAdjective),
            Rule(suffix: "です", replacement: "", label: "礼貌形", wordClass: .naAdjective),
            Rule(suffix: "な", replacement: "", label: "连体形", wordClass: .naAdjective),
        ]

        // ── 三类动词。サ変复合词（勉強する）靠「します → する」自然覆盖。
        for (suffix, label) in [
            ("しませんでした", "ます形 · 过去否定"), ("しません", "ます形 · 否定"),
            ("しました", "ます形 · 过去"), ("します", "ます形"),
            ("しなかった", "否定 · 过去"), ("しない", "否定形"),
            ("して", "て形"), ("した", "过去形"), ("できる", "可能形"),
        ] {
            rules.append(Rule(suffix: suffix, replacement: "する", label: label, wordClass: .suru, containsRoot: true))
        }
        for (surface, dictionary) in [("来", "来"), ("き", "く"), ("こ", "く")] {
            for (suffix, label) in [
                ("ました", "ます形 · 过去"), ("ます", "ます形"),
                ("ない", "否定形"), ("なかった", "否定 · 过去"),
                ("て", "て形"), ("た", "过去形"),
            ] {
                rules.append(Rule(
                    suffix: surface + suffix,
                    replacement: dictionary + "る",
                    label: label,
                    wordClass: .kuru,
                    containsRoot: true
                ))
            }
        }

        // 长后缀优先匹配，避免「ました」被「た」抢先切掉。
        return rules.sorted { $0.suffix.count > $1.suffix.count }
    }()

    // MARK: - 还原

    /// 最多连续还原几层。`食べていました` 需要 2 层（ている → て形 → 原形）。
    private static let maxDepth = 3

    /// 还原 `surface`，返回候选原形。
    ///
    /// - Parameter isDictionaryWord: 用来消歧。`買った` 会给出 `買う` / `勝つ` / `借る` 三个候选，
    ///   词库里查得到的排前面。不传就按变形层数和规则特异性排序。
    public static func deinflect(
        _ surface: String,
        isDictionaryWord: (String) -> Bool = { _ in false }
    ) -> [Deinflection] {
        var results: [Deinflection] = []
        var seen = Set<String>()

        // 表面形本身可能就是原形
        if isDictionaryWord(surface) || looksLikeBaseForm(surface) {
            results.append(Deinflection(dictionaryForm: surface, steps: [], wordClass: inferClass(surface)))
            seen.insert(surface)
        }

        var frontier = [(form: surface, steps: [String](), wordClass: WordClass.unknown)]

        for _ in 0..<maxDepth {
            var next: [(form: String, steps: [String], wordClass: WordClass)] = []

            for state in frontier {
                for rule in rules where state.form.hasSuffix(rule.suffix) {
                    let stem = String(state.form.dropLast(rule.suffix.count))
                    // 词干不能为空，否则孤零零一个「ます」会被还原成「る」。
                    // 三类动词例外：它们的规则把词根写进了后缀里（します → する），
                    // 空词干正是合法情形。
                    guard !stem.isEmpty || rule.containsRoot else { continue }
                    let candidate = stem + rule.replacement
                    guard !candidate.isEmpty, candidate != state.form else { continue }

                    let steps = state.steps + [rule.label]
                    next.append((candidate, steps, rule.wordClass))

                    if seen.contains(candidate) { continue }
                    if isDictionaryWord(candidate) || looksLikeBaseForm(candidate) {
                        seen.insert(candidate)
                        results.append(Deinflection(
                            dictionaryForm: candidate,
                            steps: steps,
                            wordClass: rule.wordClass == .unknown ? inferClass(candidate) : rule.wordClass
                        ))
                    }
                }
            }
            if next.isEmpty { break }
            frontier = next
        }

        // 词库里查得到的最可信；其次是变形层数少的。
        return results.sorted { lhs, rhs in
            let lhsKnown = isDictionaryWord(lhs.dictionaryForm)
            let rhsKnown = isDictionaryWord(rhs.dictionaryForm)
            if lhsKnown != rhsKnown { return lhsKnown }
            return lhs.steps.count < rhs.steps.count
        }
    }

    /// 最可信的那个还原结果。
    public static func best(
        _ surface: String,
        isDictionaryWord: (String) -> Bool = { _ in false }
    ) -> Deinflection? {
        deinflect(surface, isDictionaryWord: isDictionaryWord).first
    }

    // MARK: - 形态判断

    /// 「看起来像个原形吗」。用于在没有词典时筛掉明显不成立的还原结果。
    static func looksLikeBaseForm(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        // 动词原形以う段结尾，い形容词以い结尾
        return uRow.contains(String(last)) || last == "い"
    }

    static func inferClass(_ word: String) -> WordClass {
        if word.hasSuffix("する") { return .suru }
        if word.hasSuffix("来る") || word.hasSuffix("くる") { return .kuru }
        guard let last = word.last else { return .unknown }
        if last == "い" { return .iAdjective }
        if last == "る" { return .unknown }   // る 结尾无法区分一类/二类，交给词库
        if uRow.contains(String(last)) { return .godan }
        return .unknown
    }
}
