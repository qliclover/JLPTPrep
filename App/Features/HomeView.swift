import SwiftUI
import SwiftData
import JLPTCore
import JLPTContent

struct HomeView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(SettingKey.newCardsPerDay) private var newCardsPerDay = 15
    @AppStorage(SettingKey.maxReviewsPerDay) private var maxReviewsPerDay = 200
    @AppStorage(SettingKey.targetLevel) private var targetLevelRaw = "N4"
    @AppStorage(SettingKey.remindersOn) private var remindersOn = false
    @AppStorage(SettingKey.reminderHour) private var reminderHour = 20
    @AppStorage(SettingKey.reminderMinute) private var reminderMinute = 0

    @Query(sort: \BookEntity.lastOpenedAt, order: .reverse) private var books: [BookEntity]

    @State private var snapshot = QueueSnapshot()
    @State private var totals = ReviewSession.Counts()
    @State private var bootstrapError: String?
    @State private var showingStudy = false
    @State private var appeared = false
    @State private var activity: [Bool] = []
    @State private var streak = 0
    @State private var enabledPacks: Set<String> = []
    @State private var openedBook: BookEntity?

    private var goal: JLPTLevel { JLPTLevel(rawValue: targetLevelRaw) ?? .n4 }
    /// 备考范围是累积的：考 N4 要连 N5 一起背。
    private var scope: Set<JLPTLevel> { goal.cumulativeScope }

    private var scopeLabel: String {
        JLPTLevel.allCases
            .filter { scope.contains($0) }
            .sorted { $0.difficulty < $1.difficulty }
            .map(\.rawValue)
            .joined(separator: " · ")
    }

    private var session: ReviewSession {
        ReviewSession(queueConfig: DailyQueueConfig(
            newCardsPerDay: newCardsPerDay,
            maxReviewsPerDay: maxReviewsPerDay
        ))
    }

    /// 读到一半的书：最近打开过、且还没读完。
    private var readingBook: BookEntity? {
        books.first { $0.lastOpenedAt != nil && $0.progress < 1 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                header
                todayCard.rise(appeared, delay: 0)
                if let book = readingBook {
                    continueReading(book).rise(appeared, delay: 0.06)
                }
                libraryProgress.rise(appeared, delay: 0.12)
                streakRow.rise(appeared, delay: 0.18)
                if let bootstrapError {
                    errorCard(bootstrapError)
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, Theme.Space.s8)
        }
        .background(Theme.Palette.bg)
        .fullScreenCover(item: $openedBook) { book in
            ReaderView(book: book)
        }
        .fullScreenCover(isPresented: $showingStudy, onDismiss: refresh) {
            StudyView(newCardsPerDay: newCardsPerDay, maxReviewsPerDay: maxReviewsPerDay, scope: scope, packIDs: enabledPacks)
        }
        .task {
            await bootstrap()
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            #if DEBUG
            // 自动化验证钩子：`-autoStudy` 直接进复习流。Release 构建里不存在。
            if CommandLine.arguments.contains("-autoStudy"), snapshot.total > 0 {
                showingStudy = true
            }
            if ScreenshotMode.current == .study, snapshot.total > 0 {
                showingStudy = true
            }
            #endif
        }
        .onChange(of: newCardsPerDay) { refresh() }
        .onChange(of: maxReviewsPerDay) { refresh() }
        .onChange(of: targetLevelRaw) { refresh() }
    }

    // MARK: - 顶栏

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("日本語 · \(goal.rawValue)")
                    .font(.classicalHeading(26))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Kicker(text: "含 \(scopeLabel)", size: 11)
            }
            .padding(.top, Theme.Space.s4)
            .padding(.bottom, Theme.Space.s3)
            Hairline()
        }
    }

    // MARK: - 今日待办

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Kicker(text: "今日待办")

            HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s3) {
                Text("\(snapshot.total)")
                    .font(.classicalHeading(58, weight: .regular, liningFigures: true))
                    .foregroundStyle(Theme.Palette.text)
                Text("约 \(estimatedMinutes) 分钟")
                    .font(.classicalBody(12))
                    .foregroundStyle(Theme.Palette.neutral600)
                Spacer()
            }

            statRow

            Button {
                if snapshot.total > 0 { showingStudy = true }
            } label: {
                Text(snapshot.total > 0 ? "开始 · \(snapshot.total) 张" : "没有可学的卡 —— 去词库启用一个包")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ClassicalButtonStyle())
            .opacity(snapshot.total > 0 ? 1 : 0.45)
            .padding(.top, Theme.Space.s1)
        }
        .classicalCard()
    }

    private var statRow: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                stat("生词", snapshot.new, tint: Theme.Palette.accent700)
                Rectangle().fill(Theme.divider).frame(width: Theme.hairline)
                stat("巩固", snapshot.learning)
                Rectangle().fill(Theme.divider).frame(width: Theme.hairline)
                stat("复习", snapshot.review)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stat(_ label: String, _ value: Int, tint: Color = Theme.Palette.text) -> some View {
        VStack(spacing: Theme.Space.s1) {
            Text("\(value)")
                .font(.classicalHeading(22, liningFigures: true))
                .foregroundStyle(tint)
            Text(label)
                .font(.classicalBody(11))
                .foregroundStyle(Theme.Palette.neutral600)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.s2)
    }

    /// 粗估：一张卡约 8 秒。
    private var estimatedMinutes: Int {
        max(1, Int((Double(snapshot.total) * 8 / 60).rounded()))
    }

    // MARK: - 读到一半

    private func continueReading(_ book: BookEntity) -> some View {
        // 不能用 NavigationLink —— RootView 是自绘底栏，没有 NavigationStack，
        // 栈外的 NavigationLink 会被渲染成禁用态（整卡发灰）而且点了没反应。
        Button { openedBook = book } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                HStack {
                    Kicker(text: "读到一半")
                    Spacer()
                    Text("\(Int(book.progress * 100))%")
                        .font(.classicalHeading(16, liningFigures: true))
                        .foregroundStyle(Theme.Palette.accent700)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.japanese(22, weight: .medium))
                            .foregroundStyle(Theme.Palette.text)
                            .lineLimit(1)
                        Text("\(book.author ?? "—") · 第 \(book.paragraphIndex) 段")
                            .font(.classicalBody(12))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.neutral600)
                    }
                    Spacer()
                    Text("续读")
                        .font(.classicalBody(13))
                        .padding(.horizontal, Theme.Space.s3)
                        .padding(.vertical, Theme.Space.s1)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .strokeBorder(Theme.divider, lineWidth: Theme.hairline)
                        )
                        .foregroundStyle(Theme.Palette.text)
                }
                ClassicalProgress(value: book.progress)
                    .padding(.top, Theme.Space.s1)
            }
            .classicalCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - 词库进度

    private var libraryProgress: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack {
                Kicker(text: "词库")
                Spacer()
                Text("已接触 \(totals.learning + totals.review) / \(totals.total) · 未学 \(totals.new)")
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral600)
            }
            ClassicalProgress(
                value: totals.total > 0
                    ? Double(totals.learning + totals.review) / Double(totals.total)
                    : 0,
                tint: Theme.Palette.neutral800
            )
        }
    }

    // MARK: - 连续天数

    private var streakRow: some View {
        HStack(spacing: Theme.Space.s3) {
            Text(streak > 0 ? "连续 \(streak) 天" : "今天还没开始")
                .font(.classicalBody(12))
                .foregroundStyle(Theme.Palette.neutral600)
            Spacer()
            HStack(spacing: 5) {
                ForEach(Array(activity.enumerated()), id: \.offset) { index, done in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(done ? Theme.Palette.accent200 : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1)
                                .strokeBorder(
                                    done ? Theme.Palette.accent : Theme.divider,
                                    lineWidth: Theme.hairline
                                )
                        )
                        .frame(width: 10, height: 10)
                        // 逐个入场，间隔 50ms
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.4)
                        .animation(
                            .easeOut(duration: 0.28).delay(0.2 + Double(index) * 0.05),
                            value: appeared
                        )
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text(message)
                .font(.classicalBody(13))
                .foregroundStyle(Theme.Palette.text)
            Text("已保留上一次的词库，可以照常学习。")
                .font(.classicalBody(12))
                .foregroundStyle(Theme.Palette.neutral600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.s4)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                // 这套系统里没有语义红，错误态也用金描边
                .strokeBorder(Theme.Palette.accent, lineWidth: Theme.hairline)
        )
    }

    // MARK: - 数据

    /// 首次启动只导入**备考范围内**的包，其余留给用户在「等级词库」里按需导入。
    /// 一上来把 8,029 词全灌进去，队列和统计对备考 N5 的人就没有意义了。
    private func bootstrap() async {
        do {
            let library = PackLibrary()
            let packs = try library.packs(in: context)
            for pack in packs where scope.contains(pack.level) && !pack.imported {
                try library.import(level: pack.level, from: .main, into: context)
            }
        } catch {
            bootstrapError = "内容导入失败：\(error.localizedDescription)"
        }
        #if DEBUG
        // 截图模式下铺一层演示数据。Release 构建里这段不存在。
        ScreenshotSeed.apply(in: context)
        #endif
        refresh()
    }

    private func refresh() {
        do {
            let enabled = try PackLibrary().enabledPackIDs(in: context)
            enabledPacks = enabled
            let queue = try session.todayQueue(in: context, levels: scope, packIDs: enabled)
            snapshot = QueueSnapshot(
                new: queue.new.count,
                learning: queue.learning.count,
                review: queue.review.count
            )
            totals = try session.counts(in: context, levels: scope, packIDs: enabled)
            activity = try session.activity(days: 7, in: context)
            streak = try session.streak(in: context)
        } catch {
            bootstrapError = "读取队列失败：\(error.localizedDescription)"
        }
        // 每次首页刷新（进入、学完一场回来）都重排提醒 ——
        // 刚做完 15 张，今晚的通知就不该再说「15 张待办」。
        Task { await rescheduleReminders() }
        #if DEBUG
        ReminderScheduler.runProbeIfRequested(in: context)
        #endif
    }

    private func rescheduleReminders() async {
        guard remindersOn else { return }
        await ReminderScheduler.reschedule(
            enabled: true,
            hour: reminderHour,
            minute: reminderMinute,
            in: context,
            session: session,
            levels: scope,
            packIDs: enabledPacks
        )
    }
}

private struct QueueSnapshot {
    var new = 0
    var learning = 0
    var review = 0
    var total: Int { new + learning + review }
}

private extension View {
    /// 入场动画：opacity 0→1 + translateY 10→0，300ms ease。
    /// 设计里所有卡片都用它，只有延迟不同。
    func rise(_ appeared: Bool, delay: Double) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.easeOut(duration: 0.3).delay(delay), value: appeared)
    }
}
