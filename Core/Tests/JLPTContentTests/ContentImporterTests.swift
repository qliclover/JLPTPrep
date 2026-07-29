import XCTest
import SwiftData
@testable import JLPTContent
import JLPTCore

@MainActor
final class ContentImporterTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let importer = ContentImporter()
    let now = Date(timeIntervalSince1970: 1_774_000_000)

    override func setUpWithError() throws {
        container = try JLPTStore.container(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    // MARK: - fixtures

    private func seed(_ slug: String, meaning: String = "含义", expression: String? = nil) -> VocabSeed {
        VocabSeed(
            slug: slug,
            expression: expression ?? slug,
            reading: "よみ",
            meaningZh: meaning,
            partOfSpeech: "名词",
            examples: [Example(ja: "例文。", zh: "例句。")]
        )
    }

    private func pack(_ slugs: [String], id: String = "test-pack", level: JLPTLevel = .n5) -> VocabPack {
        VocabPack(packID: id, level: level, vocab: slugs.map { seed($0) })
    }

    private func vocab(_ slug: String) throws -> VocabEntity? {
        try context.fetch(FetchDescriptor<VocabEntity>(predicate: #Predicate { $0.slug == slug })).first
    }

    private func reviewItem(_ slug: String) throws -> ReviewItemEntity? {
        let key = ReviewItemEntity.key(kind: .vocab, slug: slug)
        return try context.fetch(FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.key == key })).first
    }

    private func allVocab() throws -> [VocabEntity] {
        try context.fetch(FetchDescriptor<VocabEntity>())
    }

    // MARK: - 首次导入

    func testFirstImportCreatesContentAndReviewItems() throws {
        let report = try importer.importVocabPack(pack(["a", "b", "c"]), into: context, now: now)

        XCTAssertEqual(report.inserted, 3)
        XCTAssertEqual(report.updated, 0)
        XCTAssertEqual(report.reviewItemsCreated, 3)
        XCTAssertFalse(report.skipped)

        XCTAssertEqual(try allVocab().count, 3)
        let item = try XCTUnwrap(reviewItem("a"))
        XCTAssertEqual(item.srs.stage, .new)
        XCTAssertNil(item.srs.dueDate)
        XCTAssertEqual(item.kind, .vocab)
        XCTAssertEqual(item.level, .n5)
    }

    func testSeedLevelOverridesPackLevel() throws {
        var p = pack(["a"], level: .n5)
        p.vocab[0].level = .n4
        try importer.importVocabPack(p, into: context, now: now)

        XCTAssertEqual(try vocab("a")?.level, .n4)
        XCTAssertEqual(try reviewItem("a")?.level, .n4, "等级要冗余到进度表，筛选才不用 join")
    }

    // MARK: - 幂等与指纹

    func testReimportingIdenticalPackIsSkipped() throws {
        let p = pack(["a", "b"])
        try importer.importVocabPack(p, into: context, now: now)

        let second = try importer.importVocabPack(p, into: context, now: now)
        XCTAssertTrue(second.skipped)
        XCTAssertEqual(second.inserted, 0)
        XCTAssertEqual(try allVocab().count, 2)
    }

    func testForceReimportRunsButChangesNothing() throws {
        let p = pack(["a", "b"])
        try importer.importVocabPack(p, into: context, now: now)

        let forced = try importer.importVocabPack(p, into: context, now: now, force: true)
        XCTAssertFalse(forced.skipped)
        XCTAssertEqual(forced.unchanged, 2)
        XCTAssertEqual(forced.updated, 0)
        XCTAssertEqual(forced.inserted, 0)
        XCTAssertEqual(forced.reviewItemsCreated, 0)
    }

    func testFingerprintIsStableAcrossEncodings() throws {
        let p = pack(["a", "b"])
        XCTAssertEqual(try importer.fingerprint(of: p), try importer.fingerprint(of: p))

        var changed = p
        changed.vocab[0].meaningZh = "改了"
        XCTAssertNotEqual(try importer.fingerprint(of: p), try importer.fingerprint(of: changed))
    }

    // MARK: - 内容更新不碰进度（这一步最关键的保证）

    func testContentUpdateKeepsSRSProgressIntact() throws {
        try importer.importVocabPack(pack(["a", "b"]), into: context, now: now)

        // 模拟已经背了一阵：a 进了 review 阶段，还被收藏了
        let item = try XCTUnwrap(reviewItem("a"))
        let originalUUID = item.uuid
        item.srs = SRSState(
            easeFactor: 2.15,
            intervalDays: 21,
            repetitions: 5,
            lapses: 2,
            dueDate: now.addingTimeInterval(21 * secondsPerDay),
            stage: .review,
            lastReviewedAt: now
        )
        item.isStarred = true
        item.introducedAt = now
        try context.save()

        // 内容作者修了释义，重新导入
        var updated = pack(["a", "b"])
        updated.vocab[0].meaningZh = "修正后的释义"
        updated.vocab[0].expression = "新表记"
        let report = try importer.importVocabPack(updated, into: context, now: now)

        XCTAssertEqual(report.updated, 1)
        XCTAssertEqual(report.unchanged, 1)
        XCTAssertEqual(report.inserted, 0)
        XCTAssertEqual(report.reviewItemsCreated, 0, "老词不该再建 SRS 记录")

        XCTAssertEqual(try vocab("a")?.meaningZh, "修正后的释义")
        XCTAssertEqual(try vocab("a")?.expression, "新表记")

        let after = try XCTUnwrap(reviewItem("a"))
        XCTAssertEqual(after.uuid, originalUUID, "进度记录的身份不能变，否则复习历史全断了")
        XCTAssertEqual(after.srs.intervalDays, 21)
        XCTAssertEqual(after.srs.repetitions, 5)
        XCTAssertEqual(after.srs.lapses, 2)
        XCTAssertEqual(after.srs.easeFactor, 2.15, accuracy: 1e-9)
        XCTAssertEqual(after.srs.stage, .review)
        XCTAssertTrue(after.isStarred)
        XCTAssertEqual(after.introducedAt, now)
    }

    func testAddingWordsInLaterVersionOnlyCreatesTheNewOnes() throws {
        try importer.importVocabPack(pack(["a", "b"]), into: context, now: now)
        let report = try importer.importVocabPack(pack(["a", "b", "c", "d"]), into: context, now: now)

        XCTAssertEqual(report.inserted, 2)
        XCTAssertEqual(report.unchanged, 2)
        XCTAssertEqual(report.reviewItemsCreated, 2)
        XCTAssertEqual(try allVocab().count, 4)
    }

    // MARK: - 退役

    func testRemovedWordsAreRetiredNotDeleted() throws {
        try importer.importVocabPack(pack(["a", "b", "c"]), into: context, now: now)
        let item = try XCTUnwrap(reviewItem("c"))
        item.srs = SRSState(intervalDays: 10, repetitions: 3, dueDate: now, stage: .review)
        try context.save()

        let report = try importer.importVocabPack(pack(["a", "b"]), into: context, now: now)
        XCTAssertEqual(report.retired, 1)

        XCTAssertEqual(try allVocab().count, 3, "内容不物理删除")
        XCTAssertEqual(try vocab("c")?.isRetired, true)
        XCTAssertEqual(try reviewItem("c")?.srs.intervalDays, 10, "复习历史必须留着")
    }

    func testRetiredWordComesBackWhenReintroduced() throws {
        try importer.importVocabPack(pack(["a", "b"]), into: context, now: now)
        try importer.importVocabPack(pack(["a"]), into: context, now: now)
        XCTAssertEqual(try vocab("b")?.isRetired, true)

        let report = try importer.importVocabPack(pack(["a", "b"]), into: context, now: now)
        XCTAssertEqual(try vocab("b")?.isRetired, false)
        XCTAssertEqual(report.reviewItemsCreated, 0, "复活不该新建进度记录")
    }

    func testPacksDoNotRetireEachOthersWords() throws {
        try importer.importVocabPack(pack(["a", "b"], id: "pack-1"), into: context, now: now)
        try importer.importVocabPack(pack(["x", "y"], id: "pack-2"), into: context, now: now)

        let report = try importer.importVocabPack(pack(["a"], id: "pack-1"), into: context, now: now)
        XCTAssertEqual(report.retired, 1)
        XCTAssertEqual(try vocab("b")?.isRetired, true)
        XCTAssertEqual(try vocab("x")?.isRetired, false, "另一个包的词不该被牵连")
        XCTAssertEqual(try vocab("y")?.isRetired, false)
    }

    // MARK: - 校验

    func testDuplicateSlugsAreRejectedBeforeTouchingTheDatabase() throws {
        let bad = VocabPack(packID: "dup", level: .n5, vocab: [seed("a"), seed("b"), seed("a")])
        XCTAssertThrowsError(try importer.importVocabPack(bad, into: context, now: now)) { error in
            XCTAssertEqual(error as? ContentPackError, .duplicateSlugs(["a"]))
        }
        XCTAssertEqual(try allVocab().count, 0, "校验失败不能留下半截数据")
    }

    func testUnsupportedSchemaVersionIsRejected() throws {
        var p = pack(["a"])
        p.schemaVersion = 99
        XCTAssertThrowsError(try importer.importVocabPack(p, into: context, now: now)) { error in
            XCTAssertEqual(error as? ContentPackError, .unsupportedSchemaVersion(found: 99, supported: 2))
        }
    }

    func testEmptyPackIsRejected() throws {
        let p = VocabPack(packID: "empty", level: .n5, vocab: [])
        XCTAssertThrowsError(try importer.importVocabPack(p, into: context, now: now)) { error in
            XCTAssertEqual(error as? ContentPackError, .emptyPack(packID: "empty"))
        }
    }

    // MARK: - 真实种子文件

    func testRealN5SamplePackImports() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json")
        )
        let report = try importer.importVocabPack(data: Data(contentsOf: url), into: context, now: now)

        XCTAssertEqual(report.inserted, 56)
        XCTAssertEqual(report.reviewItemsCreated, 56)

        let taberu = try XCTUnwrap(vocab("n5-taberu"))
        XCTAssertEqual(taberu.expression, "食べる")
        XCTAssertEqual(taberu.reading, "たべる")
        XCTAssertEqual(taberu.furigana, "{食|た}べる")
        XCTAssertEqual(taberu.partOfSpeech, "动词·二类")
        XCTAssertEqual(taberu.level, .n5)
        XCTAssertEqual(taberu.examples.count, 1)
        XCTAssertEqual(taberu.examples.first?.zh, "早饭吃面包。")

        // 假名词没有振假名标注，这是合法的
        let chotto = try XCTUnwrap(vocab("n5-chotto"))
        XCTAssertNil(chotto.furigana)
        XCTAssertNil(chotto.examples.first?.furigana)

        // 每个词都得有释义和例句，缺了就是内容漏洞
        for entity in try allVocab() {
            XCTAssertFalse(entity.meaningZh.isEmpty, "\(entity.slug) 缺中文释义")
            XCTAssertFalse(entity.reading.isEmpty, "\(entity.slug) 缺读音")
            XCTAssertFalse(entity.examples.isEmpty, "\(entity.slug) 缺例句")
        }

        // 二次导入必须是空操作
        let second = try importer.importVocabPack(data: Data(contentsOf: url), into: context, now: now)
        XCTAssertTrue(second.skipped)
    }

    func testFuriganaAnnotationsAreWellFormed() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json")
        )
        try importer.importVocabPack(data: Data(contentsOf: url), into: context, now: now)

        func check(_ text: String?, _ label: String) {
            guard let text else { return }
            var depth = 0
            var pipesInCurrentGroup = 0
            for ch in text {
                switch ch {
                case "{":
                    XCTAssertEqual(depth, 0, "\(label) 振假名不能嵌套")
                    depth += 1
                    pipesInCurrentGroup = 0
                case "}":
                    XCTAssertEqual(depth, 1, "\(label) 括号不配对")
                    XCTAssertEqual(pipesInCurrentGroup, 1, "\(label) 每组必须恰好一个分隔符")
                    depth -= 1
                case "|":
                    if depth == 1 { pipesInCurrentGroup += 1 }
                default:
                    break
                }
            }
            XCTAssertEqual(depth, 0, "\(label) 有未闭合的括号")
        }

        for entity in try allVocab() {
            check(entity.furigana, entity.slug)
            for example in entity.examples { check(example.furigana, "\(entity.slug) 例句") }
        }
    }
}
