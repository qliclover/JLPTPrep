#if DEBUG
import Foundation
import SwiftData
import JLPTCore
import JLPTContent

/// 给 App Store 截图铺一层演示数据。
///
/// 刚装好的 App 是空的：没有复习历史，活跃格子全灰，笔记页是空态。
/// 这些屏截出来只能证明「功能存在」，证明不了「用起来是什么样」。
///
/// 播下去的都是这个 App 自己能产出的东西 —— 笔记是针对随包那几篇原文写的真话，
/// 复习记录用的是真实的 SM-2 字段。不伪造任何 App 做不到的效果。
///
/// 整个文件在 `#if DEBUG` 内，只有带 `-screenshot` 启动时才跑。
enum ScreenshotSeed {

    /// 演示笔记 —— 针对《蜘蛛の糸》和《羅生門》正文里真实出现的表达。
    private struct DemoNote {
        let bookTitleContains: String
        let paragraph: Int
        let quoted: String
        let body: String
        /// 距今多少小时前记的
        let hoursAgo: Int
    }

    private static let notes: [DemoNote] = [
        DemoNote(
            bookTitleContains: "蜘蛛",
            paragraph: 1,
            quoted: "ある日の事でございます。",
            body: "「〜でございます」是「です」的郑重体。芥川用它做叙述者的口吻，\n整篇像是有人在念给你听。N3 语法，会话里几乎只在服务业听到。",
            hoursAgo: 3
        ),
        DemoNote(
            bookTitleContains: "蜘蛛",
            paragraph: 2,
            quoted: "極楽は丁度朝なのでございましょう。",
            body: "丁度（ちょうど）＝正好。这里不是「大约」，是「时间恰好是」。\n和「ちょうどいい」的用法要分开记。",
            hoursAgo: 5
        ),
        DemoNote(
            bookTitleContains: "羅生門",
            paragraph: 1,
            quoted: "ある日の暮方の事である。",
            body: "同样是「ある日」开头，但结尾是「である」——书面断定体，\n比《蜘蛛の糸》的「でございます」冷得多。开篇一句就定了调子。",
            hoursAgo: 26
        ),
    ]

    /// 只跑一次的入口。非截图模式下直接返回。
    static func apply(in context: ModelContext, now: Date = Date()) {
        guard ScreenshotMode.current != nil else { return }
        seedNotes(in: context, now: now)
        seedHistory(in: context, now: now)
        seedReadingProgress(in: context, now: now)
        try? context.save()
    }

    /// 让《蜘蛛の糸》处在「读到一半」的状态，首页才有续读卡。
    ///
    /// 全新安装的首页中段是空的 —— 而「读到哪儿了」正是这个 App 想让人一眼看到的。
    private static func seedReadingProgress(in context: ModelContext, now: Date) {
        guard let books = try? context.fetch(FetchDescriptor<BookEntity>()),
              let book = books.first(where: { $0.title.contains("蜘蛛") }),
              book.lastOpenedAt == nil
        else { return }
        book.paragraphIndex = max(1, book.paragraphCount * 2 / 5)
        book.lastOpenedAt = now.addingTimeInterval(-3 * 3600)
    }

    private static func seedNotes(in context: ModelContext, now: Date) {
        guard (try? context.fetch(FetchDescriptor<NoteEntity>()))?.isEmpty ?? false else { return }
        guard let books = try? context.fetch(FetchDescriptor<BookEntity>()) else { return }

        for note in notes {
            guard let book = books.first(where: { $0.title.contains(note.bookTitleContains) }) else { continue }
            context.insert(NoteEntity(
                bookUUID: book.uuid,
                paragraphIndex: note.paragraph,
                quotedText: note.quoted,
                body: note.body,
                createdAt: now.addingTimeInterval(-Double(note.hoursAgo) * 3600)
            ))
        }
    }

    /// 造最近六天的复习记录，让首页的连续天数和活跃格子有内容。
    ///
    /// 只写日志，不动 `ReviewItemEntity` 的调度状态 —— 否则今日队列会被清空，
    /// 首页那个「15 张待办」就没了，而那才是首页最该展示的东西。
    private static func seedHistory(in context: ModelContext, now: Date) {
        guard (try? context.fetch(FetchDescriptor<ReviewLogEntity>()))?.isEmpty ?? false else { return }
        guard let items = try? context.fetch(FetchDescriptor<ReviewItemEntity>()), !items.isEmpty else { return }

        let calendar = Calendar.current
        // 今天之前连续 6 天，每天 12–28 条。数字用下标推出来，不用随机数 ——
        // 截图要可复现，每次跑出来必须一模一样。
        for dayOffset in 1...6 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let count = 12 + (dayOffset * 7) % 17
            for index in 0..<count {
                let item = items[(dayOffset * 31 + index) % items.count]
                let reviewedAt = calendar.date(
                    bySettingHour: 21, minute: (index * 3) % 60, second: 0, of: day
                ) ?? day
                // 每 7 条掺一次「忘了」，让错题本有内容。
                // 用下标决定而不是随机数 —— 截图必须可复现。
                let rating: Rating = switch index % 7 {
                case 0: .again
                case 3: .hard
                default: .good
                }
                context.insert(ReviewLogEntity(log: ReviewLog(
                    itemID: item.uuid,
                    rating: rating,
                    reviewedAt: reviewedAt,
                    stageBefore: .review,
                    stageAfter: .review,
                    intervalBeforeDays: 1 + index % 4,
                    intervalAfterDays: 3 + index % 9,
                    easeBefore: 2.5,
                    easeAfter: 2.5
                )))
            }
        }
    }
}
#endif
