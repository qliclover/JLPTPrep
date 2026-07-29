import XCTest
import SwiftData
@testable import JLPTContent
import JLPTCore
import JLPTJapanese

@MainActor
final class StudyFlowTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let now = Date(timeIntervalSince1970: 1_774_000_000)

    override func setUpWithError() throws {
        container = try JLPTStore.container(inMemory: true)
        context = ModelContext(container)
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json")
        )
        try ContentImporter().importVocabPack(data: Data(contentsOf: url), into: context, now: now)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func item(_ slug: String) throws -> ReviewItemEntity {
        let key = ReviewItemEntity.key(kind: .vocab, slug: slug)
        return try XCTUnwrap(
            context.fetch(FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.key == key })).first
        )
    }

    // MARK: - 答对次数要真的落库

    /// 这条差点漏掉：`correctStreak` 在 Core 里算得好好的，
    /// 但实体的桥接方法没带上它，三次门槛在 App 里等于失效。
    func testCorrectStreakSurvivesAWriteReadRoundTrip() throws {
        let session = ReviewSession()
        let card = try item("n5-taberu")

        try session.answer(card, rating: .good, now: now, in: context)
        XCTAssertEqual(card.correctStreak, 1)
        XCTAssertEqual(card.srs.correctStreak, 1)

        // 换一个 context 重新读，确认是真的写进去了
        let fresh = ModelContext(container)
        let uuid = card.uuid
        let reloaded = try XCTUnwrap(
            fresh.fetch(FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.uuid == uuid })).first
        )
        XCTAssertEqual(reloaded.srs.correctStreak, 1, "答对次数没落库，三次门槛会形同虚设")
    }

    func testCardNeedsThreeCorrectAnswersInTheRealPipeline() throws {
        let session = ReviewSession()
        let card = try item("n5-taberu")

        try session.answer(card, rating: .good, now: now, in: context)
        try session.answer(card, rating: .good, now: now.addingTimeInterval(600), in: context)
        XCTAssertEqual(card.srs.stage, .learning)

        try session.answer(card, rating: .good, now: now.addingTimeInterval(600 + secondsPerDay), in: context)
        XCTAssertEqual(card.srs.stage, .review, "第三次答对才毕业")
    }

    // MARK: - 撤销

    func testUndoRestoresEverything() throws {
        let session = ReviewSession()
        let card = try item("n5-taberu")

        // 先把它背到 review 阶段
        card.srs = SRSState(
            easeFactor: 2.5, intervalDays: 60, repetitions: 6,
            dueDate: now, stage: .review, correctStreak: 5
        )
        try context.save()

        // 手滑按了「忘了」
        let undoable = try session.answerUndoably(card, rating: .again, now: now, in: context)
        XCTAssertEqual(card.srs.intervalDays, 1, "60 天的卡被打回 1 天")
        XCTAssertEqual(card.srs.easeFactor, 2.3, accuracy: 1e-9)
        XCTAssertEqual(card.srs.lapses, 1)
        XCTAssertEqual(card.srs.correctStreak, 0)

        try session.undo(undoable, in: context)
        XCTAssertEqual(card.srs.intervalDays, 60, "撤销后要原样回去")
        XCTAssertEqual(card.srs.easeFactor, 2.5, accuracy: 1e-9)
        XCTAssertEqual(card.srs.lapses, 0)
        XCTAssertEqual(card.srs.correctStreak, 5)
        XCTAssertEqual(card.srs.stage, .review)
    }

    /// 日志也要撤掉，否则统计和将来的 FSRS 训练数据里会留下一次没发生过的复习。
    func testUndoAlsoRemovesTheLog() throws {
        let session = ReviewSession()
        let card = try item("n5-taberu")

        let undoable = try session.answerUndoably(card, rating: .good, now: now, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewLogEntity>()), 1)

        try session.undo(undoable, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewLogEntity>()), 0)
    }

    func testUndoRestoresNewCardQuota() throws {
        let session = ReviewSession(queueConfig: DailyQueueConfig(newCardsPerDay: 5))
        let card = try item("n5-taberu")

        let undoable = try session.answerUndoably(card, rating: .good, now: now, in: context)
        XCTAssertEqual(try session.newCardsIntroduced(in: context, now: now), 1)

        try session.undo(undoable, in: context)
        XCTAssertEqual(
            try session.newCardsIntroduced(in: context, now: now), 0,
            "撤销一张新卡，今天的新卡额度也该还回来"
        )
    }

    // MARK: - 暂停

    func testSuspendedCardLeavesTheQueueButKeepsProgress() throws {
        let session = ReviewSession()
        let card = try item("n5-taberu")
        card.srs = SRSState(intervalDays: 10, repetitions: 3, dueDate: now, stage: .review)
        try context.save()

        XCTAssertTrue(try session.todayQueue(in: context, now: now).review.contains { $0.uuid == card.uuid })

        try session.setSuspended(card, true, in: context)
        XCTAssertFalse(try session.todayQueue(in: context, now: now).ordered.contains { $0.uuid == card.uuid })
        XCTAssertEqual(card.srs.intervalDays, 10, "暂停不该丢进度")

        try session.setSuspended(card, false, in: context)
        XCTAssertTrue(try session.todayQueue(in: context, now: now).review.contains { $0.uuid == card.uuid })
    }

    // MARK: - 出题

    func testQuestionsAreGeneratedForRealVocabulary() throws {
        let service = QuizService()
        let pool = try service.pool(in: context)
        XCTAssertEqual(pool.count, 56)

        var rng = SystemRandomNumberGenerator()
        var generated = 0
        for word in pool {
            let card = try item(word.slug)
            if service.question(for: card, pool: pool, using: &rng) != nil { generated += 1 }
        }
        XCTAssertEqual(generated, pool.count, "56 词的词库该能给每个词都出出题来")
    }

    /// 毕业需要的三次答对该考三个不同角度，而不是同一道题做三遍。
    func testQuestionTypeRotatesWithProgress() throws {
        let service = QuizService()
        let pool = try service.pool(in: context)
        let card = try item("n5-taberu")

        var types: [QuestionType] = []
        for streak in 0..<3 {
            card.srs.correctStreak = streak
            var rng = SystemRandomNumberGenerator()
            if let question = service.question(for: card, pool: pool, using: &rng) {
                types.append(question.type)
            }
        }
        XCTAssertEqual(Set(types).count, 3, "三次答对考了同样的题型：\(types)")
    }

    func testTinyPoolFallsBackGracefully() throws {
        // 空词库时出不了题，该返回 nil 让 UI 退回翻卡模式，而不是崩
        let service = QuizService()
        let card = try item("n5-taberu")
        var rng = SystemRandomNumberGenerator()
        XCTAssertNil(service.question(for: card, pool: [], using: &rng))
    }

    // MARK: - 生词回收

    func testCollectingAWordFromReadingCreatesAReviewCard() throws {
        let collector = VocabCollector()
        let before = try context.fetchCount(FetchDescriptor<ReviewItemEntity>())

        // 内容包是安装时导的，收词是之后读书时发生的
        let later = now.addingTimeInterval(3600)
        let entity = try collector.collect(
            expression: "蜘蛛", reading: "くも", meaningZh: "蜘蛛",
            partOfSpeech: "名词", into: context, now: later
        )
        XCTAssertEqual(entity.packID, VocabCollector.packID)
        XCTAssertTrue(entity.tags.contains("生词本"))

        let after = try context.fetchCount(FetchDescriptor<ReviewItemEntity>())
        XCTAssertEqual(after, before + 1, "收词要连带建一张复习卡")

        // 而且要排在词库里那 56 个词前面 —— 每日新卡额度只有 15，
        // 不优先的话刚收的词好几天都轮不到。
        let queue = try ReviewSession().todayQueue(in: context, now: later)
        XCTAssertEqual(
            queue.new.first?.contentSlug, VocabCollector.slug(for: "蜘蛛"),
            "刚收的生词该排在新卡队列最前面"
        )
    }

    func testCollectingIsIdempotent() throws {
        let collector = VocabCollector()
        try collector.collect(expression: "蜘蛛", reading: "くも", meaningZh: "蜘蛛",
                              partOfSpeech: "名词", into: context, now: now)
        let count = try context.fetchCount(FetchDescriptor<ReviewItemEntity>())

        try collector.collect(expression: "蜘蛛", reading: "くも", meaningZh: "改了",
                              partOfSpeech: "名词", into: context, now: now)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewItemEntity>()), count, "重复收词不该建第二张卡")
    }

    /// 词库里本来就有的词（内容包带的），不该被复制成一条「生词本」的重复词条。
    func testCollectingAWordAlreadyInThePackReusesIt() throws {
        let collector = VocabCollector()
        let entity = try collector.collect(
            expression: "食べる", reading: "たべる", meaningZh: "吃",
            partOfSpeech: "动词·二类", into: context, now: now
        )
        XCTAssertEqual(entity.slug, "n5-taberu", "该复用内容包里的那一条")
        XCTAssertEqual(entity.packID, "vocab-n5-sample")
        XCTAssertEqual(try collector.collectedCount(in: context), 0)
    }

    /// 收进来的词不该被内容包的导入流程当成「消失了」而退役。
    func testContentPackReimportDoesNotRetireCollectedWords() throws {
        let collector = VocabCollector()
        try collector.collect(expression: "蜘蛛", reading: "くも", meaningZh: "蜘蛛",
                              partOfSpeech: "名词", into: context, now: now)

        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json")
        )
        var pack = try ContentPackSchema.decoder().decode(VocabPack.self, from: Data(contentsOf: url))
        pack.vocab[0].meaningZh = "改一下触发重新导入"
        let report = try ContentImporter().importVocabPack(pack, into: context, now: now)

        XCTAssertEqual(report.retired, 0, "内容包的导入不该碰用户自己收的词")
        let collected = try collector.find(expression: "蜘蛛", in: context)
        XCTAssertEqual(collected?.isRetired, false)
    }
}
