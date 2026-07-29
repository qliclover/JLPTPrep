import XCTest
import SwiftData
@testable import JLPTContent
import JLPTCore

@MainActor
final class PackLibraryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let library = PackLibrary()
    let now = Date(timeIntervalSince1970: 1_774_000_000)

    override func setUpWithError() throws {
        container = try JLPTStore.container(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func seedPack(_ id: String, level: JLPTLevel, slugs: [String]) throws {
        let pack = VocabPack(packID: id, level: level, vocab: slugs.map {
            VocabSeed(slug: $0, expression: $0, reading: "よみ", meaningZh: "含义", partOfSpeech: "名词")
        })
        try ContentImporter().importVocabPack(pack, into: context, now: now)
    }

    // MARK: - 包的登记

    func testEveryLevelGetsARow() throws {
        let packs = try library.packs(in: context)
        XCTAssertEqual(packs.count, JLPTLevel.allCases.count)
        XCTAssertEqual(packs.map(\.level.rawValue), ["N5", "N4", "N3", "N2", "N1"], "按由易到难排")
        XCTAssertTrue(packs.allSatisfy { !$0.imported && !$0.enabled }, "初始都是未导入未启用")
    }

    func testPacksAreNotDuplicatedOnRepeatedCalls() throws {
        _ = try library.packs(in: context)
        _ = try library.packs(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VocabPackEntity>()), 5)
    }

    // MARK: - 队列按启用状态过滤

    func testDisabledPackLeavesTheQueue() throws {
        try seedPack("jlpt-n5", level: .n5, slugs: ["a", "b"])
        try seedPack("jlpt-n4", level: .n4, slugs: ["c", "d"])

        let packs = try library.packs(in: context)
        for pack in packs where pack.packID == "jlpt-n5" || pack.packID == "jlpt-n4" {
            pack.imported = true
            pack.enabled = true
        }
        try context.save()

        let session = ReviewSession()
        var enabled = try library.enabledPackIDs(in: context)
        XCTAssertEqual(try session.todayQueue(in: context, now: now, packIDs: enabled).new.count, 4)

        // 停用 N4
        let n4 = try XCTUnwrap(packs.first { $0.packID == "jlpt-n4" })
        try library.setEnabled(false, for: n4, in: context)
        enabled = try library.enabledPackIDs(in: context)

        let queue = try session.todayQueue(in: context, now: now, packIDs: enabled)
        XCTAssertEqual(queue.new.count, 2, "停用的包该从队列里摘掉")
        XCTAssertTrue(queue.new.allSatisfy { $0.packID == "jlpt-n5" })
    }

    /// 停用**不是**删除：进度必须原样留着，重新启用时接着背。
    func testDisablingKeepsProgress() throws {
        try seedPack("jlpt-n4", level: .n4, slugs: ["c"])
        let packs = try library.packs(in: context)
        let n4 = try XCTUnwrap(packs.first { $0.packID == "jlpt-n4" })
        n4.imported = true
        n4.enabled = true
        try context.save()

        let key = ReviewItemEntity.key(kind: .vocab, slug: "c")
        let item = try XCTUnwrap(
            context.fetch(FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.key == key })).first
        )
        item.srs = SRSState(intervalDays: 21, repetitions: 5, dueDate: now, stage: .review)
        try context.save()

        try library.setEnabled(false, for: n4, in: context)
        try library.setEnabled(true, for: n4, in: context)

        XCTAssertEqual(item.srs.intervalDays, 21, "停用再启用不该丢进度")
        XCTAssertEqual(item.srs.repetitions, 5)
    }

    /// 用户从书里收的生词不属于任何词库包，不该被「停用某个包」连累。
    func testCollectedWordsSurviveEveryPackBeingDisabled() throws {
        try seedPack("jlpt-n5", level: .n5, slugs: ["a"])
        try VocabCollector().collect(
            expression: "蜘蛛", reading: "くも", meaningZh: "蜘蛛",
            partOfSpeech: "名词", into: context, now: now
        )

        let queue = try ReviewSession().todayQueue(in: context, now: now, packIDs: [])
        XCTAssertEqual(queue.new.count, 1, "所有包都停用后，自己收的词还得在")
        XCTAssertEqual(queue.new.first?.contentSlug, VocabCollector.slug(for: "蜘蛛"))
    }

    // MARK: - packID 冗余

    func testReviewItemsCarryTheirPackID() throws {
        try seedPack("jlpt-n5", level: .n5, slugs: ["a"])
        let key = ReviewItemEntity.key(kind: .vocab, slug: "a")
        let item = try XCTUnwrap(
            context.fetch(FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.key == key })).first
        )
        XCTAssertEqual(item.packID, "jlpt-n5", "packID 要冗余到进度表，过滤才不用 join")
    }

    // MARK: - 导入进度

    func testImportReportsProgressMonotonically() throws {
        // 回调声明成 @Sendable，测试里得用个能安全跨隔离域写入的盒子
        final class Box: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var values: [Double] = []
            func append(_ value: Double) { lock.lock(); values.append(value); lock.unlock() }
        }
        let box = Box()
        let pack = VocabPack(packID: "big", level: .n5, vocab: (0..<500).map {
            VocabSeed(slug: "w\($0)", expression: "w\($0)", reading: "よみ",
                      meaningZh: "含义", partOfSpeech: "名词")
        })
        try ContentImporter().importVocabPack(pack, into: context, now: now) { box.append($0) }

        let samples = box.values
        XCTAssertFalse(samples.isEmpty, "该有进度回报")
        XCTAssertEqual(samples.last, 1, "结束时要走到 100%")
        XCTAssertEqual(samples, samples.sorted(), "进度不能倒退")
    }
}
