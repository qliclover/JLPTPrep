import XCTest
@testable import JLPTJapanese

final class DeinflectorTests: XCTestCase {

    /// 模拟一个小词库，用来消歧。真实调用时由 App 传入 SwiftData 查询。
    private let known: Set<String> = [
        "食べる", "飲む", "見る", "聞く", "行く", "来る", "帰る", "話す", "読む", "書く",
        "買う", "起きる", "寝る", "働く", "待つ", "分かる", "教える", "使う", "勉強する",
        "大きい", "小さい", "新しい", "高い", "安い", "忙しい", "楽しい", "難しい",
        "元気", "静か", "便利", "有名",
    ]

    private func lookup(_ word: String) -> Bool { known.contains(word) }

    private func best(_ surface: String) -> Deinflection? {
        Deinflector.best(surface, isDictionaryWord: lookup)
    }

    private func assertBase(
        _ surface: String,
        _ expected: String,
        steps: [String]? = nil,
        line: UInt = #line
    ) {
        guard let result = best(surface) else {
            return XCTFail("「\(surface)」还原失败", line: line)
        }
        XCTAssertEqual(result.dictionaryForm, expected, "「\(surface)」", line: line)
        if let steps {
            XCTAssertEqual(result.steps, steps, "「\(surface)」的变形说明", line: line)
        }
    }

    // MARK: - 一类动词（五段）

    func testGodanPoliteForms() {
        assertBase("飲みます", "飲む", steps: ["ます形"])
        assertBase("飲みました", "飲む", steps: ["ます形 · 过去"])
        assertBase("飲みません", "飲む", steps: ["ます形 · 否定"])
        assertBase("飲みませんでした", "飲む", steps: ["ます形 · 过去否定"])
    }

    func testGodanTeAndPastForms() {
        assertBase("書いた", "書く", steps: ["过去形"])
        assertBase("書いて", "書く", steps: ["て形"])
        assertBase("話した", "話す", steps: ["过去形"])
        assertBase("待った", "待つ", steps: ["过去形"])
        assertBase("読んだ", "読む", steps: ["过去形"])
        assertBase("働いて", "働く", steps: ["て形"])
    }

    func testGodanNegative() {
        assertBase("読まない", "読む", steps: ["否定形"])
        assertBase("読まなかった", "読む", steps: ["否定 · 过去"])
        assertBase("買わない", "買う", steps: ["否定形"])
    }

    func testGodanPotentialAndVolitional() {
        assertBase("読める", "読む", steps: ["可能形"])
        assertBase("読もう", "読む", steps: ["意志形"])
        assertBase("読めば", "読む", steps: ["ば形（条件）"])
    }

    func testIkuIsHandledAsTheIrregularItIs() {
        // 行く 的て形是「行って」而不是规则推出的「行いて」
        assertBase("行った", "行く", steps: ["过去形"])
        assertBase("行って", "行く", steps: ["て形"])
        assertBase("行きました", "行く", steps: ["ます形 · 过去"])
    }

    // MARK: - 二类动词（一段）

    func testIchidanForms() {
        assertBase("食べます", "食べる", steps: ["ます形"])
        assertBase("食べました", "食べる", steps: ["ます形 · 过去"])
        assertBase("食べた", "食べる", steps: ["过去形"])
        assertBase("食べて", "食べる", steps: ["て形"])
        assertBase("食べない", "食べる", steps: ["否定形"])
        assertBase("起きました", "起きる", steps: ["ます形 · 过去"])
        assertBase("寝ない", "寝る", steps: ["否定形"])
    }

    /// 帰る 长得像二类动词，其实是一类。词库能定这个案，规则不能。
    func testKaeruResolvesViaDictionary() {
        assertBase("帰ります", "帰る", steps: ["ます形"])
        assertBase("帰った", "帰る", steps: ["过去形"])
    }

    // MARK: - 三类动词

    func testSuruCompounds() {
        assertBase("勉強します", "勉強する", steps: ["ます形"])
        assertBase("勉強しました", "勉強する", steps: ["ます形 · 过去"])
        assertBase("勉強して", "勉強する", steps: ["て形"])
    }

    func testKuru() {
        assertBase("来ます", "来る", steps: ["ます形"])
        assertBase("来ました", "来る", steps: ["ます形 · 过去"])
        assertBase("来た", "来る", steps: ["过去形"])
    }

    // MARK: - 形容词

    func testIAdjective() {
        assertBase("高かった", "高い", steps: ["过去形"])
        assertBase("高くない", "高い", steps: ["否定形"])
        assertBase("高くなかった", "高い", steps: ["否定 · 过去"])
        assertBase("忙しかった", "忙しい", steps: ["过去形"])
        assertBase("安くて", "安い", steps: ["て形"])
    }

    func testNaAdjective() {
        assertBase("静かでした", "静か", steps: ["过去（礼貌）"])
        assertBase("静かだった", "静か", steps: ["过去形"])
        assertBase("有名な", "有名", steps: ["连体形"])
        assertBase("便利じゃない", "便利", steps: ["否定形"])
    }

    // MARK: - 复合变形（需要多层还原）

    func testProgressiveChainsThroughTeForm() {
        assertBase("食べている", "食べる", steps: ["ている（进行 / 状态）", "て形"])
        assertBase("働いています", "働く", steps: ["ている · ます形", "て形"])
        // 「読んで」是て形（で 是浊化的 て），不是过去形
        assertBase("読んでいました", "読む", steps: ["ている · ます过去", "て形"])
    }

    func testDesiderative() {
        assertBase("食べたい", "食べる", steps: ["たい形（想做）"])
        assertBase("飲みたかった", "飲む", steps: ["たい形 · 过去"])
    }

    // MARK: - 歧义

    /// 「った」既可能来自 つ / う / る。没有词库时三个都是合法候选，
    /// 有词库时正确的那个必须排第一。
    func testAmbiguousPastFormIsResolvedByDictionary() {
        let candidates = Deinflector.deinflect("買った", isDictionaryWord: lookup)
        XCTAssertEqual(candidates.first?.dictionaryForm, "買う", "词库里有 買う，该排第一")
        XCTAssertGreaterThan(candidates.count, 1, "没被词库确认的候选也该保留")

        let blind = Deinflector.deinflect("買った")
        XCTAssertTrue(blind.contains { $0.dictionaryForm == "買う" })
        XCTAssertTrue(blind.contains { $0.dictionaryForm == "買つ" }, "没词库时形态上成立的候选都要给出")
    }

    // MARK: - 不该乱还原

    func testBaseFormIsRecognizedAsIs() {
        guard let result = best("食べる") else { return XCTFail("原形该被识别") }
        XCTAssertEqual(result.dictionaryForm, "食べる")
        XCTAssertTrue(result.isBaseForm)
        XCTAssertEqual(result.stepsLabel, "原形")
    }

    func testNounsAndParticlesProduceNothingBogus() {
        // 助词、名词不该被硬套成动词原形
        for word in ["を", "は", "、", "学校"] {
            let results = Deinflector.deinflect(word, isDictionaryWord: lookup)
            XCTAssertTrue(
                results.allSatisfy { $0.dictionaryForm != word || $0.isBaseForm },
                "「\(word)」被错误地还原了：\(results.map(\.dictionaryForm))"
            )
        }
    }

    func testEmptyInput() {
        XCTAssertTrue(Deinflector.deinflect("").isEmpty)
    }

    func testSuffixOnlyInputDoesNotCrash() {
        // 「ます」单独出现时不能被还原成「る」
        let results = Deinflector.deinflect("ます", isDictionaryWord: lookup)
        XCTAssertFalse(results.contains { $0.dictionaryForm == "る" })
    }

    // MARK: - 词类推断

    func testWordClassInference() {
        XCTAssertEqual(best("飲みます")?.wordClass, .godan)
        XCTAssertEqual(best("食べます")?.wordClass, .ichidan)
        XCTAssertEqual(best("勉強します")?.wordClass, .suru)
        XCTAssertEqual(best("来ました")?.wordClass, .kuru)
        XCTAssertEqual(best("高かった")?.wordClass, .iAdjective)
        XCTAssertEqual(best("静かでした")?.wordClass, .naAdjective)
        XCTAssertEqual(WordClass.ichidan.labelZh, "动词·二类")
    }
}
