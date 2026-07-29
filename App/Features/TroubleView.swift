import SwiftUI
import SwiftData
import JLPTCore
import JLPTContent

/// 错题本。最近反复答错的词，错得最狠的排前面。
///
/// 数据一直在 `ReviewLogEntity` 里躺着 —— 每一次评分都记了，只是从来没人读。
/// 备考到后期，攻下反复错的这几十个词，比再背几百个新词有用。
struct TroubleView: View {
    let scope: Set<JLPTLevel>
    let packIDs: Set<String>
    let newCardsPerDay: Int
    let maxReviewsPerDay: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var spots: [ReviewSession.TroubleSpot] = []
    /// 做错的真题。和背单词的错题分开列 —— 它们是两种不同的错。
    @State private var examMistakes: [ExamQuestionEntity] = []
    @State private var openedExam: ExamEntity?
    @State private var drilling = false

    /// 统计窗口。三个月前错过、现在已经稳了的词，再摆出来只会制造焦虑。
    private let windowDays = 60

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if spots.isEmpty && examMistakes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !spots.isEmpty { summary }
                        ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                            Hairline()
                            row(spot)
                        }
                        Hairline()
                        if !examMistakes.isEmpty { examSection }
                    }
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.bottom, Theme.Space.s6)
                }
                drillBar
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .task { load() }
        .fullScreenCover(item: $openedExam, onDismiss: load) { ExamRunnerView(exam: $0) }
        .fullScreenCover(isPresented: $drilling, onDismiss: load) {
            StudyView(
                newCardsPerDay: newCardsPerDay,
                maxReviewsPerDay: maxReviewsPerDay,
                scope: scope,
                packIDs: packIDs,
                drillUUIDs: spots.map(\.item.uuid)
            )
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← 设置") { dismiss() }
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
                Spacer()
                Text("错题本")
                    .font(.classicalHeading(19))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Text("← 设置")
                    .font(.classicalBody(13))
                    .opacity(0)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
            Hairline()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text("最近 \(windowDays) 天里，有 \(spots.count) 个词你按过「忘了」。")
                .font(.classicalBody(13))
                .foregroundStyle(Theme.Palette.text)
            Text("按错的次数排，次数相同看正确率。\n只错过一次的排在后面 —— 那多半是还没学熟，不是难点。")
                .font(.classicalBody(12))
                .lineSpacing(4)
                .foregroundStyle(Theme.Palette.neutral600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Space.s4)
    }

    private func row(_ spot: ReviewSession.TroubleSpot) -> some View {
        let vocab = lookup(spot.item.contentSlug)
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s3) {
            VStack(alignment: .leading, spacing: Theme.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s2) {
                    Text(vocab?.expression ?? spot.item.contentSlug)
                        .font(.japanese(20, weight: .medium))
                        .foregroundStyle(Theme.Palette.text)
                    if let reading = vocab?.reading, !reading.isEmpty {
                        Text(reading)
                            .font(.japanese(13))
                            .foregroundStyle(Theme.Palette.neutral600)
                    }
                }
                if let meaning = vocab?.displayMeaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.classicalBody(13))
                        .foregroundStyle(Theme.Palette.neutral700)
                        .lineLimit(1)
                }
                Text(detail(spot))
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral500)
            }
            Spacer(minLength: Theme.Space.s2)
            // 错的次数用金色大字 —— 这一列是整页唯一要一眼扫到的信息
            Text("\(spot.againCount)")
                .font(.classicalHeading(24, liningFigures: true))
                .foregroundStyle(Theme.Palette.accent700)
        }
        .padding(.vertical, Theme.Space.s3)
    }

    private func detail(_ spot: ReviewSession.TroubleSpot) -> String {
        let percent = Int((spot.accuracy * 100).rounded())
        var parts = ["\(spot.totalCount) 次里对 \(percent)%"]
        if spot.lapses > spot.againCount {
            parts.append("累计遗忘 \(spot.lapses) 次")
        }
        parts.append(relative(spot.lastAgainAt))
        return parts.joined(separator: " · ")
    }

    private func relative(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        return switch days {
        case ..<1: "今天错过"
        case 1: "昨天错过"
        default: "\(days) 天前错过"
        }
    }

    // MARK: - 真题错题

    private var examSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "真题错题")
                Spacer()
                Text("\(examMistakes.count) 道")
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral600)
            }
            .padding(.top, Theme.Space.s8)
            .padding(.bottom, Theme.Space.s3)

            Text("和上面的单词错题分开列。单词错是「没记住」，\n真题错可能是语法没懂、读解看岔、听力没听清 —— 不是一回事。")
                .font(.classicalBody(11))
                .lineSpacing(4)
                .foregroundStyle(Theme.Palette.neutral600)
                .padding(.bottom, Theme.Space.s3)

            ForEach(examMistakes) { q in
                Hairline()
                examRow(q)
            }
            Hairline()
        }
    }

    private func examRow(_ q: ExamQuestionEntity) -> some View {
        Button { openedExam = q.exam } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                HStack(spacing: Theme.Space.s2) {
                    ClassicalTag(text: q.subject, style: .outline)
                    Text("\(q.exam?.session ?? "") · 第 \(q.number) 题")
                        .font(.classicalBody(11))
                        .foregroundStyle(Theme.Palette.neutral600)
                    Spacer()
                }
                Text(q.isListening && q.stem.isEmpty ? "（听力题）" : q.stem)
                    .font(.japanese(15))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                // 你选的 vs 正确的 —— 这一行是这条记录的全部价值
                if let picked = q.picked, picked <= q.options.count {
                    HStack(alignment: .top, spacing: Theme.Space.s2) {
                        Text("你选 \(picked)")
                            .font(.classicalBody(11))
                            .foregroundStyle(Theme.Palette.neutral500)
                        Text("正确 \(q.answer)．\(q.options[q.answer - 1])")
                            .font(.classicalBody(11))
                            .foregroundStyle(Theme.Palette.accent700)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.s3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var drillBar: some View {
        VStack(spacing: 0) {
            Hairline()
            Button { drilling = true } label: {
                Text("专项复习 · \(spots.count) 张").frame(maxWidth: .infinity)
            }
            .buttonStyle(ClassicalButtonStyle())
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s4) {
            Spacer()
            Text("还没有错题")
                .font(.classicalHeading(26))
                .foregroundStyle(Theme.Palette.text)
            Text("复习时按过「忘了」的词、做真题选错的题，都会收到这里。\n最近 \(windowDays) 天还没有。")
                .font(.classicalBody(13))
                .lineSpacing(8)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Palette.neutral600)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.s8)
    }

    // MARK: - 数据

    private func load() {
        spots = (try? ReviewSession().troubleSpots(
            in: context, days: windowDays, levels: scope, packIDs: packIDs
        )) ?? []
        examMistakes = (try? ReviewSession().examMistakes(in: context)) ?? []
        #if DEBUG
        // 截图时少显示几道单词错题，好把下面的真题错题一节也框进来
        if ScreenshotMode.current == .trouble { spots = Array(spots.prefix(2)) }
        #endif
    }

    private func lookup(_ slug: String) -> VocabEntity? {
        var descriptor = FetchDescriptor<VocabEntity>(
            predicate: #Predicate { $0.slug == slug }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
