import SwiftUI
import SwiftData
import JLPTCore
import JLPTContent

/// 复习流：出卡 → 翻面 → 四键评分 → 完成页。
/// 版式、字号、动效时长按 design_handoff_jlpt_classical 的「2. 复习卡片」「3. 复习完成」。
struct StudyView: View {
    let newCardsPerDay: Int
    let maxReviewsPerDay: Int
    let scope: Set<JLPTLevel>
    let packIDs: Set<String>
    /// 非 nil 时进入「专项复习」：只刷这几张，按给定顺序。错题本用它。
    var drillUUIDs: [UUID]?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.showFurigana) private var showFurigana = true
    @AppStorage(SettingKey.reviewMode) private var reviewMode = "flip"

    @State private var queue: [ReviewItemEntity] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var answered = 0
    @State private var ratings: [Rating: Int] = [:]
    @State private var pendingLearning: Date?
    @State private var errorText: String?
    /// 评分推进时当前卡淡出上移（200ms），换卡后反向淡入。
    @State private var cardOpacity: Double = 1
    @State private var cardOffset: CGFloat = 0
    /// 选择题模式用到的状态。
    @State private var quizPool: [QuizWord] = []
    @State private var question: QuizQuestion?
    @State private var picked: Int?

    private var isQuiz: Bool { reviewMode == "quiz" }

    private let scheduler = SM2Scheduler()

    private var session: ReviewSession {
        ReviewSession(
            scheduler: scheduler,
            queueConfig: DailyQueueConfig(newCardsPerDay: newCardsPerDay, maxReviewsPerDay: maxReviewsPerDay)
        )
    }

    private var current: ReviewItemEntity? {
        index < queue.count ? queue[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let item = current {
                topBar
                card(for: item)
                    .opacity(cardOpacity)
                    .offset(y: cardOffset)
            } else {
                DoneView(
                    answered: answered,
                    ratings: ratings,
                    pendingLearning: pendingLearning,
                    onHome: { dismiss() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.bg.ignoresSafeArea())
        .task {
            reload()
            #if DEBUG
            if CommandLine.arguments.contains("-autoReveal") { revealed = true }
            #endif
        }
        // 收工离开时别让声音跟出去
        .onDisappear { Speaker.shared.stop() }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s3) {
                Button("收工") { dismiss() }
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)

                ClassicalProgress(
                    value: queue.isEmpty ? 0 : Double(index) / Double(queue.count)
                )
                .frame(maxWidth: .infinity)

                Text("\(String(format: "%02d", index + 1)) / \(queue.count)")
                    .font(.classicalBody(12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral600)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
            Hairline()
        }
    }

    // MARK: - 卡片

    @ViewBuilder
    private func card(for item: ReviewItemEntity) -> some View {
        let vocab = vocab(for: item)

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    HStack(spacing: Theme.Space.s2) {
                        ClassicalTag(text: stageLabel(item), style: .outline)
                        ClassicalTag(text: item.level.rawValue, style: .accent)
                        Spacer()
                        // 只在答案揭晓后出现。正面放朗读等于直接把读音送出去 ——
                        // 而「想不想得起读音」正是这张卡在考的事。
                        if let vocab, answerVisible, Speaker.shared.isAvailable {
                            Button(isSpeaking(vocab) ? "朗读中" : "朗读") {
                                Speaker.shared.speak(vocab.reading)
                            }
                            .buttonStyle(ClassicalButtonStyle(
                                kind: isSpeaking(vocab) ? .primary : .secondary,
                                size: 12,
                                verticalPadding: 5
                            ))
                        }
                    }

                    if let vocab {
                        if isQuiz, let question {
                            QuizCard(
                                question: question,
                                showFurigana: showFurigana,
                                selected: picked,
                                onSelect: { pick($0, item: item) }
                            )
                            if revealed {
                                back(vocab, item: item)
                            }
                        } else {
                            Text(vocab.expression)
                                .font(.japanese(62, weight: .medium))
                                .tracking(62 * 0.06)
                                .foregroundStyle(Theme.Palette.text)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // 读音位：正面不可见但占位保留，避免翻面时跳版。
                            // 不能用半透明 —— 那等于把答案漏出去。
                            Text(vocab.reading)
                                .font(.japanese(19))
                                .foregroundStyle(Theme.Palette.neutral600)
                                .opacity(revealed ? 1 : 0)
                                .animation(.easeOut(duration: 0.25), value: revealed)

                            if revealed {
                                back(vocab, item: item)
                            }
                        }
                    } else {
                        Text("内容缺失：\(item.contentSlug)")
                            .font(.classicalBody(13))
                            .foregroundStyle(Theme.Palette.neutral600)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.classicalBody(12))
                            .foregroundStyle(Theme.Palette.accent700)
                    }
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, Theme.Space.s6)
                .padding(.bottom, Theme.Space.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isQuiz && question != nil {
                // 选择题的评分是从对错推出来的，不需要四键。
                // 答完给一个「下一张」，并标出这张卡的掌握进度。
                if picked != nil {
                    quizFooter(for: item)
                }
            } else if revealed {
                ratingBar(for: item)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.28)) { revealed = true }
                } label: {
                    // 通栏按钮：宽度要撑在 label 上，加在 Button 外面 ButtonStyle 收不到
                    Text("显示答案").frame(maxWidth: .infinity)
                }
                .buttonStyle(ClassicalButtonStyle())
                .padding(.horizontal, Theme.Space.screen)
                .padding(.bottom, Theme.Space.s4)
            }
        }
    }

    // MARK: - 朗读

    /// 答案是否已经露出来了。
    ///
    /// 翻卡模式看 `revealed`；选择题模式选完就算 —— 选项本身已经把读音摆出来了，
    /// 再藏着没有意义。
    private var answerVisible: Bool {
        isQuiz ? picked != nil : revealed
    }

    private func isSpeaking(_ vocab: VocabEntity) -> Bool {
        Speaker.shared.speaking == vocab.reading
    }

    @ViewBuilder

    private func back(_ vocab: VocabEntity, item: ReviewItemEntity) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            // 48pt 宽金色短横线
            Rectangle()
                .fill(Theme.Palette.accent)
                .frame(width: 48, height: Theme.hairline)
                .padding(.top, Theme.Space.s2)

            Text(vocab.displayMeaning)
                .font(.classicalHeading(28))
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Space.s2) {
                ClassicalTag(text: vocab.partOfSpeech, style: .neutral)
                if let tag = vocab.tags.first {
                    ClassicalTag(text: tag, style: .accent)
                }
                Spacer()
            }

            if let example = vocab.examples.first {
                HStack(alignment: .top, spacing: 0) {
                    // 例句块左侧一条金色竖线
                    Rectangle()
                        .fill(Theme.Palette.accent)
                        .frame(width: Theme.hairline)
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        RubyText(
                            annotated: example.furigana ?? example.ja,
                            showFurigana: showFurigana,
                            baseSize: 20,
                            color: Theme.Palette.text
                        )
                        Text(example.zh)
                            .font(.classicalBody(14))
                            .foregroundStyle(Theme.Palette.neutral700)
                    }
                    .padding(.leading, Theme.Space.s4)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Text("EF \(String(format: "%.2f", item.srs.easeFactor)) · 第 \(item.srs.repetitions) 次　\(vocab.slug)")
                .font(.classicalBody(11))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.neutral500)
        }
        .transition(.opacity)
    }

    private func stageLabel(_ item: ReviewItemEntity) -> String {
        switch item.srs.stage {
        case .new: "初见"
        case .learning: "巩固中"
        case .relearning: "重学"
        case .review: "复习 · 第 \(item.srs.repetitions) 次"
        }
    }

    // MARK: - 评分区

    private func ratingBar(for item: ReviewItemEntity) -> some View {
        // 每个按钮标上它会把卡片推到多远。调度器是纯函数，随便预演不产生副作用。
        let preview = scheduler.preview(state: item.srs, now: Date())
        return VStack(spacing: Theme.Space.s2) {
            Hairline()
            HStack {
                Kicker(text: "下次到期", color: Theme.Palette.neutral600, size: 11)
                Spacer()
                Kicker(text: "共 \(queue.count) 张", color: Theme.Palette.neutral600, size: 11)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.top, Theme.Space.s2)

            // 「记得」占 1.3 份，其余各 1 份。
            // 不能用 layoutPriority —— 那不是 flex，高优先级的会把空间全吃掉，
            // 其余三个会被挤到零宽，文字直接消失。宽度得自己算。
            GeometryReader { geometry in
                let gap = Theme.Space.s2
                let unit = (geometry.size.width - gap * 3) / 4.3
                HStack(alignment: .top, spacing: gap) {
                    ratingButton(.again, "忘了", preview[.again], item, width: unit)
                    ratingButton(.hard, "困难", preview[.hard], item, width: unit)
                    ratingButton(.good, "记得", preview[.good], item, width: unit * 1.3, emphasis: true)
                    ratingButton(.easy, "简单", preview[.easy], item, width: unit)
                }
            }
            .frame(height: 66)
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, Theme.Space.s4)
        }
    }

    private func ratingButton(
        _ rating: Rating,
        _ label: String,
        _ interval: String?,
        _ item: ReviewItemEntity,
        width: CGFloat,
        emphasis: Bool = false
    ) -> some View {
        VStack(spacing: Theme.Space.s1) {
            Button { answer(item, rating: rating) } label: {
                Text(label).frame(maxWidth: .infinity)
            }
            .buttonStyle(ClassicalButtonStyle(
                kind: emphasis ? .emphasis : .secondary,
                size: 14,
                verticalPadding: 11
            ))
            Text(interval ?? "—")
                .font(.classicalBody(11))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.neutral600)
        }
        .frame(width: width)
    }

    // MARK: - 选择题

    private func quizFooter(for item: ReviewItemEntity) -> some View {
        let required = SRSConfig().requiredCorrectToGraduate
        let streak = item.srs.correctStreak
        return VStack(spacing: Theme.Space.s2) {
            Hairline()
            HStack {
                Kicker(
                    text: item.srs.stage == .review ? "已毕业" : "连对 \(streak) / \(required)",
                    color: Theme.Palette.neutral600,
                    size: 11
                )
                Spacer()
                // 三格进度点：答对三次才算过，一次蒙对不作数
                HStack(spacing: 5) {
                    ForEach(0..<required, id: \.self) { index in
                        Circle()
                            .fill(index < streak ? Theme.Palette.accent : Color.clear)
                            .overlay(
                                Circle().strokeBorder(
                                    index < streak ? Theme.Palette.accent : Theme.divider,
                                    lineWidth: Theme.hairline
                                )
                            )
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.top, Theme.Space.s2)

            Button { advance() } label: {
                Text("下一张").frame(maxWidth: .infinity)
            }
            .buttonStyle(ClassicalButtonStyle())
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, Theme.Space.s4)
        }
    }

    /// 选中一个选项 —— 立即判分。对 = 记得，错 = 忘了。
    /// 选择题里没有「困难 / 简单」这两档：那是自我感觉，而这里只有客观对错。
    private func pick(_ index: Int, item: ReviewItemEntity) {
        guard picked == nil, let question else { return }
        picked = index
        let rating: Rating = question.isCorrect(index) ? .good : .again
        do {
            try session.answer(item, rating: rating, in: context)
            answered += 1
            ratings[rating, default: 0] += 1
            withAnimation(.easeOut(duration: 0.28)) { revealed = true }
        } catch {
            errorText = "保存失败：\(error.localizedDescription)"
        }
    }

    /// 给当前卡出题。出不了就退回翻卡模式 —— 宁可换形式，也不出一道烂题。
    private func makeQuestion(for item: ReviewItemEntity) {
        picked = nil
        guard isQuiz else { question = nil; return }
        var generator = SystemRandomNumberGenerator()
        question = QuizService().question(for: item, pool: quizPool, using: &generator)
    }

    // MARK: - 数据

    private func vocab(for item: ReviewItemEntity) -> VocabEntity? {
        guard item.kind == .vocab else { return nil }
        let slug = item.contentSlug
        var descriptor = FetchDescriptor<VocabEntity>(predicate: #Predicate { $0.slug == slug })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func answer(_ item: ReviewItemEntity, rating: Rating) {
        do {
            try session.answer(item, rating: rating, in: context)
            answered += 1
            ratings[rating, default: 0] += 1
            advance()
        } catch {
            errorText = "保存失败：\(error.localizedDescription)"
        }
    }

    /// 当前卡淡出上移 200ms，然后换下一张再反向淡入。
    private func advance() {
        // 上一张的读音不能压到下一张上 —— 看着新词听着旧词是最糟的组合
        Speaker.shared.stop()
        withAnimation(.easeOut(duration: 0.2)) {
            cardOpacity = 0
            cardOffset = 14
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            revealed = false
            index += 1
            // 走到底了就回数据库再要一批 —— 刚才按「忘了」的卡，
            // 一分钟后到期还得再见，不重新查就漏掉了。
            //
            // 专项复习例外：它的队列是点名固定的，再 reload 会把同一批重新装填，
            // 永远走不到头。刷完就是刷完。
            if index >= queue.count {
                if drillUUIDs != nil {
                    queue = []
                } else {
                    reload()
                }
            } else if let current {
                makeQuestion(for: current)
            }
            cardOffset = -14
            withAnimation(.easeOut(duration: 0.2)) {
                cardOpacity = 1
                cardOffset = 0
            }
        }
    }

    private func reload() {
        do {
            // 专项复习：只刷点名的那几张，不受每日额度和到期时间限制 ——
            // 这是用户主动要求的加练，不是当天的配额。
            //
            // 但评分照样走 `session.answer`，进度、间隔、遗忘次数全部真实更新。
            // 一个「练了不算数」的模式毫无意义：你以为攻下来了，
            // 调度器却当无事发生，下次还是同样的间隔。
            if let drillUUIDs {
                let all = try context.fetch(
                    FetchDescriptor<ReviewItemEntity>(
                        predicate: #Predicate { $0.isSuspended == false }
                    )
                )
                let byUUID = Dictionary(uniqueKeysWithValues: all.map { ($0.uuid, $0) })
                queue = drillUUIDs.compactMap { byUUID[$0] }
                index = 0
                revealed = false
                if isQuiz, quizPool.isEmpty {
                    quizPool = (try? QuizService().pool(in: context, levels: scope)) ?? []
                }
                if let first = queue.first { makeQuestion(for: first) }
                pendingLearning = nil
                return
            }

            let built = try session.todayQueue(in: context, levels: scope, packIDs: packIDs)
            queue = built.ordered
            index = 0
            revealed = false
            if isQuiz, quizPool.isEmpty {
                quizPool = (try? QuizService().pool(in: context, levels: scope)) ?? []
            }
            if let first = queue.first { makeQuestion(for: first) }
            pendingLearning = built.isEmpty ? nextLearningDueDate() : nil
        } catch {
            errorText = "读取队列失败：\(error.localizedDescription)"
            queue = []
        }
    }

    /// 队列空了，但可能有分钟级的巩固卡还没到点，告诉用户什么时候回来。
    private func nextLearningDueDate() -> Date? {
        let now = Date()
        let items = (try? context.fetch(
            FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.isSuspended == false })
        )) ?? []
        return items
            .filter { $0.srs.stage == .learning || $0.srs.stage == .relearning }
            .compactMap(\.srs.dueDate)
            .filter { $0 > now }
            .min()
    }
}

// MARK: - 完成页

/// 「3. 复习完成」。背景一个巨大的金色淡数字从 0 逐格数上来。
private struct DoneView: View {
    let answered: Int
    let ratings: [Rating: Int]
    let pendingLearning: Date?
    let onHome: () -> Void

    @State private var counter = 0
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .top) {
            Text("\(counter)")
                .font(.classicalHeading(170, weight: .regular, liningFigures: true))
                .foregroundStyle(Theme.Palette.accent200)
                .padding(.top, 130)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: appeared)

            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Kicker(text: "这一轮毕")
                    Text(answered > 0 ? "\(answered) 张，收工" : "现在没有到期的卡")
                        .font(.classicalHeading(34))
                        .foregroundStyle(Theme.Palette.text)
                    Text(subtitle)
                        .font(.classicalBody(13))
                        .lineSpacing(13 * 0.9)
                        .foregroundStyle(Theme.Palette.neutral600)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .rise(appeared, delay: 0)

                if answered > 0 {
                    statGrid.rise(appeared, delay: 0.08)
                }

                Button { onHome() } label: {
                    Text("回首页").frame(maxWidth: .infinity)
                }
                .buttonStyle(ClassicalButtonStyle(kind: .secondary))
                    .rise(appeared, delay: 0.14)

                Spacer()
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.top, Theme.Space.s8)
        }
        .onAppear {
            appeared = true
            countUp()
        }
    }

    private var subtitle: String {
        if let pendingLearning {
            return "还有巩固中的卡，\(IntervalFormatter.string(from: Date(), to: pendingLearning)) 后回来。"
        }
        return answered > 0
            ? "这一轮的卡都过了一遍。到期的会按各自的间隔回来。"
            : "队列是空的。可以去书架读点东西，遇到生词随手收进来。"
    }

    private var statGrid: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                cell("记得", ratings[.good] ?? 0)
                divider
                cell("困难", ratings[.hard] ?? 0)
                divider
                cell("忘了", ratings[.again] ?? 0, tint: Theme.Palette.accent700)
                divider
                cell("简单", ratings[.easy] ?? 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            Hairline()
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.divider).frame(width: Theme.hairline)
    }

    private func cell(_ label: String, _ value: Int, tint: Color = Theme.Palette.text) -> some View {
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

    /// 从 0 逐格数上来，40ms 一步。
    private func countUp() {
        guard answered > 0 else { return }
        for step in 0...answered {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.04) {
                counter = step
            }
        }
    }
}

private extension View {
    func rise(_ appeared: Bool, delay: Double) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.easeOut(duration: 0.3).delay(delay), value: appeared)
    }
}
