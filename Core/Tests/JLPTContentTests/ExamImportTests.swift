import XCTest
import SwiftData
@testable import JLPTContent
import JLPTCore

/// 真题导入。
///
/// 重点是**把不可信的题挡在门外**：一道答案错了的练习题比没有这道题有害 ——
/// 你做对了却被判错，学到的是错的东西。
@MainActor
final class ExamImportTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let now = Date(timeIntervalSince1970: 1_785_000_000)

    override func setUpWithError() throws {
        container = try JLPTStore.container(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func payload(
        level: String = "N4", session: String = "2013年12月",
        hasAudio: Bool = true, questions: [[String: Any]]
    ) -> Data {
        let dict: [String: Any] = [
            "level": level, "session": session, "hasAudio": hasAudio, "questions": questions,
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    private func question(
        _ number: Int, subject: String = "文字・語彙",
        stem: String = "指にけがをしました。",
        options: [String] = ["はな", "あたま", "ゆび", "うで"],
        answer: Int? = 3
    ) -> [String: Any] {
        var q: [String: Any] = [
            "subject": subject, "section": 1, "number": number,
            "stem": stem, "options": options,
        ]
        if let answer { q["answer"] = answer }
        return q
    }

    // MARK: - 基本导入

    func testImportsQuestions() throws {
        let report = try ExamImporter.import(
            data: payload(questions: [question(1), question(2), question(3)]),
            into: context, now: now
        )
        XCTAssertEqual(report.imported, 3)
        XCTAssertEqual(report.level, "N4")
        XCTAssertEqual(report.session, "2013年12月")

        let exam = try XCTUnwrap(try context.fetch(FetchDescriptor<ExamEntity>()).first)
        XCTAssertEqual(exam.questions.count, 3)
        XCTAssertTrue(exam.hasAudio)
        XCTAssertEqual(exam.questions.first?.options.count, 4)
    }

    // MARK: - 挡住不可信的

    func testRejectsQuestionsWithoutAnswer() throws {
        let report = try ExamImporter.import(
            data: payload(questions: [question(1), question(2, answer: nil)]),
            into: context, now: now
        )
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.skipped, 1, "没有答案的题不能收 —— 做完不知道对错")
    }

    func testRejectsQuestionsWithIncompleteOptions() throws {
        let report = try ExamImporter.import(
            data: payload(questions: [
                question(1),
                question(2, options: ["はな", "あたま"]),          // 只有两个
                question(3, options: ["はな", "", "ゆび", "うで"]),  // 有一个是空的
            ]),
            into: context, now: now
        )
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.skipped, 2)
    }

    /// 答案不在 1...4 范围内的题一律不收。
    ///
    /// 这里全部题目都会被拒，所以导入本身应该抛错 —— 见
    /// `testThrowsWhenNothingUsable`：不留空试卷。掺一道好的进去才验得出计数。
    func testRejectsOutOfRangeAnswer() throws {
        let report = try ExamImporter.import(
            data: payload(questions: [question(1), question(2, answer: 7), question(3, answer: 0)]),
            into: context, now: now
        )
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.skipped, 2)
    }

    /// 一道能用的题都没有时应该报错，而不是留下一套空试卷。
    func testThrowsWhenNothingUsable() throws {
        XCTAssertThrowsError(
            try ExamImporter.import(
                data: payload(questions: [question(1, answer: nil)]), into: context, now: now
            )
        ) { error in
            XCTAssertTrue(
                (error as? LocalizedError)?.errorDescription?.contains("没有可用的题目") == true,
                "错误信息要说人话：\(error)"
            )
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExamEntity>()).isEmpty,
                      "不该留下一套空试卷")
    }

    // MARK: - 重复导入

    /// 同一场考试重新导入时整套替换，不合并 —— 题库文件是重新解析生成的，
    /// 合并只会留下新旧两版混在一起的题。
    func testReimportReplacesInsteadOfMerging() throws {
        try ExamImporter.import(
            data: payload(questions: [question(1), question(2)]), into: context, now: now
        )
        let report = try ExamImporter.import(
            data: payload(questions: [question(1), question(2), question(3)]),
            into: context, now: now
        )
        XCTAssertTrue(report.replaced)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExamEntity>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExamQuestionEntity>()).count, 3,
                       "旧的两道该被删掉，而不是和新的三道并存")
    }

    func testDifferentSessionsCoexist() throws {
        try ExamImporter.import(
            data: payload(session: "2013年12月", questions: [question(1)]), into: context, now: now
        )
        try ExamImporter.import(
            data: payload(session: "2014年07月", questions: [question(1)]), into: context, now: now
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExamEntity>()).count, 2)
    }

    // MARK: - 作答统计

    func testAccuracyIsNilBeforeAnswering() throws {
        try ExamImporter.import(
            data: payload(questions: [question(1), question(2)]), into: context, now: now
        )
        let exam = try XCTUnwrap(try context.fetch(FetchDescriptor<ExamEntity>()).first)
        XCTAssertNil(exam.accuracy, "还没开始和 0% 是两回事")
    }

    func testAccuracyCountsOnlyAnswered() throws {
        try ExamImporter.import(
            data: payload(questions: [question(1), question(2), question(3), question(4)]),
            into: context, now: now
        )
        let exam = try XCTUnwrap(try context.fetch(FetchDescriptor<ExamEntity>()).first)
        let sorted = exam.questions.sorted { $0.number < $1.number }
        sorted[0].picked = 3   // 对
        sorted[1].picked = 1   // 错
        try context.save()

        XCTAssertEqual(exam.answeredCount, 2)
        XCTAssertEqual(exam.correctCount, 1)
        XCTAssertEqual(try XCTUnwrap(exam.accuracy), 0.5, accuracy: 0.001)
    }

    func testIsCorrectReflectsPick() throws {
        try ExamImporter.import(data: payload(questions: [question(1)]), into: context, now: now)
        let q = try XCTUnwrap(try context.fetch(FetchDescriptor<ExamQuestionEntity>()).first)
        XCTAssertNil(q.isCorrect, "没做过时不该有对错")
        q.picked = 3
        XCTAssertEqual(q.isCorrect, true)
        q.picked = 1
        XCTAssertEqual(q.isCorrect, false)
    }

    func testListeningQuestionsAreFlagged() throws {
        try ExamImporter.import(
            data: payload(questions: [
                question(1, subject: "聴解", stem: ""),
                question(2, subject: "文字・語彙"),
            ]),
            into: context, now: now
        )
        let qs = try context.fetch(FetchDescriptor<ExamQuestionEntity>())
        XCTAssertEqual(qs.count { $0.isListening }, 1)
        XCTAssertEqual(qs.first { $0.isListening }?.stem, "",
                       "听力题的题干在音频里，纸面上本来就是空的")
    }

    // MARK: - 真实文件

    /// 拿 ParseExam 真实输出的结构跑一遍，确认字段名对得上。
    func testAcceptsRealParserOutputShape() throws {
        let real = """
        {
          "level": "N4",
          "session": "2014年07月N4",
          "sourceFiles": ["2014年7月真题+答案+解析+原文.pdf"],
          "hasAudio": true,
          "issues": [],
          "rejected": [],
          "questions": [
            {"subject": "文字・語彙", "section": 1, "number": 1,
             "stem": "指にけがをしました。",
             "options": ["はな", "あたま", "ゆび", "うで"],
             "answer": 3, "warnings": []}
          ]
        }
        """
        let report = try ExamImporter.import(data: Data(real.utf8), into: context, now: now)
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.session, "2014年07月N4")
    }
}
