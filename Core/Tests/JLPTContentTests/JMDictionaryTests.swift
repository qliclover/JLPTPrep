import XCTest
@testable import JLPTContent
import JLPTJapanese

final class JMDictionaryTests: XCTestCase {

    /// 测试用的小词典（31 条），随仓库走。
    /// 完整的 41MB 词典是构建期生成、不进版本库的，所以测试不能依赖它。
    private func dictionary() throws -> JMDictionary {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "jmdict-test", withExtension: "sqlite", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "jmdict-test", withExtension: "sqlite"),
            "缺少测试词典夹具"
        )
        return try XCTUnwrap(JMDictionary(url: url))
    }

    // MARK: - 基本查询

    func testLookupByKanjiForm() throws {
        let entries = try dictionary().lookup("食べる")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.kanji, "食べる")
        XCTAssertEqual(entry.reading, "たべる")
        XCTAssertTrue(entry.glossesEn.contains("eat"))
        XCTAssertTrue(entry.isCommon)
    }

    func testLookupByReadingFindsTheSameEntry() throws {
        let dict = try dictionary()
        let byKanji = dict.lookup("食べる").first
        let byReading = dict.lookup("たべる").first
        XCTAssertEqual(byKanji?.id, byReading?.id, "表记和读音该指向同一条")
    }

    func testUnknownWordReturnsNothing() throws {
        XCTAssertTrue(try dictionary().lookup("ぜんぜんないことば").isEmpty)
        XCTAssertTrue(try dictionary().lookup("").isEmpty)
    }

    func testCommonEntriesRankFirst() throws {
        let entries = try dictionary().lookup("行く")
        guard entries.count > 1 else { return }  // 夹具里可能只有一条
        XCTAssertTrue(entries[0].isCommon || !entries.contains { $0.isCommon })
    }

    // MARK: - 词性

    func testPartOfSpeechIsTranslated() throws {
        let entry = try XCTUnwrap(try dictionary().lookup("食べる").first)
        XCTAssertTrue(entry.partsOfSpeech.contains("v1"))
        XCTAssertTrue(entry.partOfSpeechLabelsZh.contains("动词·二类"))
    }

    func testUnknownPosCodeIsShownRatherThanDropped() {
        let entry = DictionaryEntry(
            id: 1, kanji: "x", reading: "x",
            partsOfSpeech: ["v1", "zzz-unknown"], glossesEn: "", isCommon: false
        )
        XCTAssertEqual(entry.partOfSpeechLabelsZh, ["动词·二类", "zzz-unknown"])
    }

    func testWordClassInferredFromPosCodes() throws {
        let dict = try dictionary()
        XCTAssertEqual(dict.lookup("食べる").first?.wordClass, .ichidan)
        XCTAssertEqual(dict.lookup("飲む").first?.wordClass, .godan)
        XCTAssertEqual(dict.lookup("高い").first?.wordClass, .iAdjective)
    }

    // MARK: - 缺文件时优雅退化

    func testMissingFileYieldsNilRatherThanCrashing() {
        let missing = URL(fileURLWithPath: "/tmp/definitely-not-a-dictionary-\(UUID().uuidString).sqlite")
        XCTAssertNil(JMDictionary(url: missing), "词典是可选的，拿不到该返回 nil 而不是崩")
    }

    // MARK: - 给活用还原消歧

    /// 这是接入词典最大的收益。
    ///
    /// 「った」可以来自 つ / う / る 三种词尾，所以 `買った` 形态上能还原成
    /// 買う（真词）、買つ、買る（都不是词）。光看形态无法排除后两个，
    /// 之前只能靠 56 词的自有词库判断，现在有 20 万词条兜底。
    func testDictionaryDisambiguatesDeinflection() throws {
        let dict = try dictionary()
        let candidates = Deinflector.deinflect("買った") { dict.contains($0) }

        XCTAssertEqual(candidates.first?.dictionaryForm, "買う", "词典认得 買う，它该排第一")
        XCTAssertTrue(
            candidates.contains { $0.dictionaryForm == "買つ" },
            "形态上成立的候选仍然保留，只是排在后面"
        )
        XCTAssertFalse(dict.contains("買つ"), "而 買つ 确实不是个词")
    }

    /// 没有词典时，同一个词只能给出形态候选，排序也就无从谈起。
    func testWithoutDictionaryTheOrderIsMerelyMorphological() {
        let blind = Deinflector.deinflect("買った")
        XCTAssertTrue(blind.contains { $0.dictionaryForm == "買う" })
        XCTAssertTrue(blind.contains { $0.dictionaryForm == "買つ" })
    }

    func testContainsIsConsistentWithLookup() throws {
        let dict = try dictionary()
        for word in ["食べる", "たべる", "高い", "蜘蛛"] {
            XCTAssertTrue(dict.contains(word), "「\(word)」该在词典里")
            XCTAssertFalse(dict.lookup(word).isEmpty)
        }
        XCTAssertFalse(dict.contains("ないはずのことば"))
    }

    func testEntryCount() throws {
        XCTAssertGreaterThan(try dictionary().entryCount, 10)
    }

    // MARK: - 并发

    /// SQLite 句柄不是线程安全的，阅读器会从多个段落的后台任务并发查词。
    func testConcurrentLookupsAreSafe() throws {
        let dict = try dictionary()
        let words = ["食べる", "飲む", "高い", "蜘蛛", "行く", "たべる"]
        let expectation = expectation(description: "并发查询")
        expectation.expectedFulfillmentCount = 60

        for index in 0..<60 {
            DispatchQueue.global().async {
                _ = dict.lookup(words[index % words.count])
                _ = dict.contains(words[index % words.count])
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 20)
    }
}
