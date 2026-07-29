import SwiftUI
import JLPTCore

/// 选择题卡片。
///
/// 和翻卡自评的区别不只是形式：自评是「我觉得我记得」，选择题是**从四个近似选项里选对**。
/// 后者才是考场上的动作，也才能把「蒙对」和「真会」分开 ——
/// 配合 `SRSConfig.requiredCorrectToGraduate`（默认三次）滤掉 25% 的瞎猜基线。
struct QuizCard: View {
    let question: QuizQuestion
    let showFurigana: Bool
    /// 已选的选项。nil 表示还没答。
    let selected: Int?
    let onSelect: (Int) -> Void

    private var answered: Bool { selected != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Kicker(text: question.type.labelZh)

            prompt

            VStack(spacing: Theme.Space.s2) {
                ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                    choiceRow(index: index, text: choice)
                }
            }
            .padding(.top, Theme.Space.s2)

            if answered, let explanation = question.explanation {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Rectangle()
                        .fill(Theme.Palette.accent)
                        .frame(width: 48, height: Theme.hairline)
                    Text(explanation)
                        .font(.classicalBody(14))
                        .lineSpacing(5)
                        .foregroundStyle(Theme.Palette.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Theme.Space.s2)
                .transition(.opacity)
            }
        }
    }

    // MARK: - 题干

    @ViewBuilder
    private var prompt: some View {
        if question.type.promptIsJapanese {
            // 汉字读音题绝不给振假名 —— 那等于把答案印在题面上。
            // `promptFurigana` 在那一类里本来就是 nil，这里只是不额外去生成。
            RubyText(
                annotated: question.promptFurigana ?? question.prompt,
                showFurigana: showFurigana && question.promptFurigana != nil,
                baseSize: question.type == .contextFill ? 22 : 46,
                color: Theme.Palette.text
            )
        } else {
            Text(question.prompt)
                .font(.classicalHeading(34))
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 选项

    private func choiceRow(index: Int, text: String) -> some View {
        let isAnswer = index == question.answerIndex
        let isPicked = index == selected

        return Button {
            guard !answered else { return }
            onSelect(index)
        } label: {
            HStack(spacing: Theme.Space.s3) {
                // 序号用等宽数字，四行才对得齐
                Text("\(index + 1)")
                    .font(.classicalHeading(15, liningFigures: true))
                    .foregroundStyle(Theme.Palette.neutral500)
                    .frame(width: 16, alignment: .leading)

                Text(text)
                    .font(isJapaneseChoice ? .japanese(19) : .classicalBody(15))
                    .foregroundStyle(Theme.Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if answered, isAnswer {
                    // 这套系统里没有语义绿，正解用金色的「正」
                    Text("正")
                        .font(.japanese(13))
                        .foregroundStyle(Theme.Palette.accent700)
                }
            }
            .padding(.vertical, Theme.Space.s3)
            .padding(.horizontal, Theme.Space.s3)
            .background(background(isAnswer: isAnswer, isPicked: isPicked))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(border(isAnswer: isAnswer, isPicked: isPicked), lineWidth: Theme.hairline)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    /// 选项是日文还是中文，决定用哪套字体。
    private var isJapaneseChoice: Bool {
        switch question.type {
        case .kanjiReading, .kanaToKanji, .meaningToWord, .contextFill: true
        case .wordToMeaning: false
        }
    }

    private func background(isAnswer: Bool, isPicked: Bool) -> Color {
        guard answered else { return .clear }
        if isAnswer { return Theme.Palette.accent100 }
        // 选错的那一项不用红底 —— 这套系统里没有语义红，
        // 靠「正解被点亮、自己选的没亮」这个对比就够说明问题。
        return isPicked ? Theme.Palette.neutral100 : .clear
    }

    private func border(isAnswer: Bool, isPicked: Bool) -> Color {
        guard answered else { return Theme.divider }
        if isAnswer { return Theme.Palette.accent }
        return isPicked ? Theme.Palette.neutral400 : Theme.divider
    }
}
