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
        .onDisappear { SegmentPlayer.shared.stop() }
        .onAppear {
            // 接着上次没做的那道继续
            index = questions.firstIndex { $0.picked == nil } ?? 0
            #if DEBUG
            // 验证听力时直接跳到第一道有音频片段的题
            if ScreenshotMode.current == .examRunner,
               let i = questions.firstIndex(where: { $0.hasSegment }) { index = i }
            #endif
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
        // 按**科目**判断，不看题干是否为空。听力题的题干在音频里，
        // 但 OCR 常把「1ばん」这类播报残渣留在题干上 —— 用 isEmpty 判断
        // 会让这些题走成普通题的布局，音频控件根本不出现。
        if q.isListening {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                Text("听力题")
                    .font(.classicalHeading(22))
                    .foregroundStyle(Theme.Palette.text)

                if q.hasSegment, ExamAudioStore.exists(exam.audioFilename) {
                    audioControl(q)
                } else {
                    Text(audioHint(q))
                        .font(.classicalBody(12))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.Palette.neutral600)
                }
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

    /// 播放这道题对应的录音片段。
    ///
    /// 播的是整份录音的一个区间，不是切好的小文件 —— 时间点由
    /// `Tools/SplitAudio` 算出（静音找候选边界、语音识别确认「Nばん」）。
    private func audioControl(_ q: ExamQuestionEntity) -> some View {
        let id = "\(exam.id)-\(q.section)-\(q.number)"
        let playing = SegmentPlayer.shared.isPlaying(id)
        return VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Button {
                if playing {
                    SegmentPlayer.shared.stop()
                } else if let name = exam.audioFilename,
                          let start = q.audioStart, let end = q.audioEnd {
                    SegmentPlayer.shared.play(
                        url: ExamAudioStore.url(for: name), from: start, to: end, id: id
                    )
                }
            } label: {
                Text(playing ? "停止" : "播放这道题")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ClassicalButtonStyle(kind: playing ? .emphasis : .primary))

            // 进度条：1px 轨 + 金色已播段，和设置里的滑杆同一套
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.divider).frame(height: Theme.hairline)
                    Rectangle().fill(Theme.Palette.accent)
                        .frame(width: geo.size.width * (playing ? SegmentPlayer.shared.progress : 0),
                               height: 2)
                }
            }
            .frame(height: 2)

            if let start = q.audioStart, let end = q.audioEnd {
                Text("片段 \(Int(end - start)) 秒 · 录音第 \(Int(start / 60)) 分处")
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral500)
            }
        }
    }

    private func audioHint(_ q: ExamQuestionEntity) -> String {
        if !exam.hasAudio { return "题目在音频里，而这套试卷没有配套音频。" }
        if !ExamAudioStore.exists(exam.audioFilename) {
            return "题目在音频里。回到试卷列表长按这一套，选「导入听力音频」。"
        }
        return "题目在音频里，但这一道没有定位到对应的录音片段。"
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
        // 换题时停掉上一题的录音 —— 看着新题听着旧题是最糟的组合
        SegmentPlayer.shared.stop()
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
