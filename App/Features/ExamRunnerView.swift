import SwiftUI
import SwiftData
import JLPTCore
import JLPTContent

/// 做真题。一次一道，选完立刻判对错。
///
/// 和复习卡的关键区别：**这里不改任何 SRS 状态**。真题是检验，不是训练 ——
/// 把做错的真题塞进复习队列会污染间隔重复的节奏（一次考试几十道，
/// 全按「忘了」处理，接下来几天的队列就废了）。
/// 想背的词从「加进今日卡组」单独收。
struct ExamRunnerView: View {
    let exam: ExamEntity

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var revealed = false

    /// 按科目、大题、题号排好的题序。
    private var questions: [ExamQuestionEntity] {
        exam.questions.sorted {
            ($0.subject, $0.section, $0.number) < ($1.subject, $1.section, $1.number)
        }
    }

    private var current: ExamQuestionEntity? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let q = current {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s6) {
                        tags(q)
                        stem(q)
                        options(q)
                        if revealed { verdict(q) }
                    }
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.vertical, Theme.Space.s6)
                }
                bottomBar
            } else {
                finished
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .onAppear {
            // 接着上次没做的那道继续
            index = questions.firstIndex { $0.picked == nil } ?? 0
            revealed = current?.picked != nil
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button("收工") { dismiss() }
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
                Spacer()
                Text("\(exam.level) · \(exam.session)")
                    .font(.classicalBody(12))
                    .foregroundStyle(Theme.Palette.neutral600)
                    .lineLimit(1)
                Spacer()
                Text("\(min(index + 1, questions.count)) / \(questions.count)")
                    .font(.classicalBody(12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral600)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
            Hairline()
        }
    }

    private func tags(_ q: ExamQuestionEntity) -> some View {
        HStack(spacing: Theme.Space.s2) {
            ClassicalTag(text: q.subject, style: .outline)
            ClassicalTag(text: "第 \(q.number) 题", style: .neutral)
            Spacer()
        }
    }

    @ViewBuilder
    private func stem(_ q: ExamQuestionEntity) -> some View {
        if q.stem.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text("听力题")
                    .font(.classicalHeading(22))
                    .foregroundStyle(Theme.Palette.text)
                Text(exam.hasAudio
                     ? "题目在音频里。这套试卷配有听力音频，但按题切分还没做，\n暂时只能对着选项作答。"
                     : "题目在音频里，而这套试卷没有配套音频。")
                    .font(.classicalBody(12))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.Palette.neutral600)
            }
        } else {
            Text(q.stem)
                .font(.japanese(20))
                .lineSpacing(7)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func options(_ q: ExamQuestionEntity) -> some View {
        VStack(spacing: Theme.Space.s2) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { offset, text in
                let number = offset + 1
                Button { pick(number, on: q) } label: {
                    HStack(alignment: .top, spacing: Theme.Space.s3) {
                        Text("\(number)")
                            .font(.classicalHeading(14, liningFigures: true))
                            .foregroundStyle(Theme.Palette.neutral500)
                            .frame(width: 16, alignment: .leading)
                        Text(text)
                            .font(.japanese(16))
                            .foregroundStyle(Theme.Palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, Theme.Space.s3)
                    .padding(.horizontal, Theme.Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .strokeBorder(border(number, q), lineWidth: Theme.hairline)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(revealed)
            }
        }
    }

    /// 判对错后才上色。这套设计里没有语义红绿 ——
    /// 正确项用金描边，选错的那一项描边淡下去，靠对比而不是颜色区分。
    private func border(_ number: Int, _ q: ExamQuestionEntity) -> Color {
        guard revealed else { return Theme.divider }
        if number == q.answer { return Theme.Palette.accent }
        if number == q.picked { return Theme.Palette.neutral400 }
        return Theme.divider
    }

    private func verdict(_ q: ExamQuestionEntity) -> some View {
        HStack(spacing: Theme.Space.s2) {
            Rectangle()
                .fill(Theme.Palette.accent)
                .frame(width: 24, height: Theme.hairline)
            Text(q.isCorrect == true ? "答对了" : "正确答案是 \(q.answer)")
                .font(.classicalBody(14))
                .foregroundStyle(q.isCorrect == true ? Theme.Palette.accent700 : Theme.Palette.text)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Theme.Space.s2) {
                if index > 0 {
                    Button { step(-1) } label: {
                        Text("上一题").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ClassicalButtonStyle(kind: .secondary))
                }
                Button { step(1) } label: {
                    Text(index + 1 >= questions.count ? "看结果" : "下一题")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ClassicalButtonStyle())
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
        }
    }

    private var finished: some View {
        VStack(spacing: Theme.Space.s6) {
            Spacer()
            Text("做完了")
                .font(.classicalHeading(28))
                .foregroundStyle(Theme.Palette.text)
            if let accuracy = exam.accuracy {
                Text("\(Int((accuracy * 100).rounded()))%")
                    .font(.classicalHeading(56, weight: .regular, liningFigures: true))
                    .foregroundStyle(Theme.Palette.accent700)
                Text("\(exam.questions.count) 题里做了 \(exam.answeredCount)，对 \(exam.correctCount)")
                    .font(.classicalBody(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral600)
            }
            HStack(spacing: Theme.Space.s2) {
                Button { restart() } label: {
                    Text("重做").frame(maxWidth: .infinity)
                }
                .buttonStyle(ClassicalButtonStyle(kind: .secondary))
                Button { dismiss() } label: {
                    Text("收工").frame(maxWidth: .infinity)
                }
                .buttonStyle(ClassicalButtonStyle())
            }
            .padding(.horizontal, Theme.Space.s8)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.screen)
    }

    // MARK: - 操作

    private func pick(_ number: Int, on q: ExamQuestionEntity) {
        guard !revealed else { return }
        q.picked = number
        q.answeredAt = Date()
        try? context.save()
        withAnimation(.easeOut(duration: 0.2)) { revealed = true }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard next >= 0 else { return }
        index = next
        revealed = current?.picked != nil
    }

    private func restart() {
        for q in exam.questions {
            q.picked = nil
            q.answeredAt = nil
        }
        try? context.save()
        index = 0
        revealed = false
    }
}
