import SwiftUI
import JLPTCore
import JLPTJapanese

/// 可点词的日语正文。
///
/// 和 `RubyText` 的区别只在交互：渲染逻辑一样，但每个词是独立的点击目标。
/// 词的切分由 `ReaderText` 决定 —— 注音单元不会被拆到两个点击区里。
struct TappableRubyText: View {
    let words: [ReaderWord]
    var showFurigana: Bool = true
    var baseSize: CGFloat = 19
    /// 命中的词：下方 2pt 金色下划线。
    var highlightedWordID: Int?
    /// 选中的句子：整句淡金底。
    var highlightedSentence: Int?
    var onTap: (ReaderWord) -> Void
    var onLongPress: ((ReaderWord) -> Void)?

    var body: some View {
        RubyFlowLayout(lineSpacing: baseSize * 0.45) {
            ForEach(words) { word in
                ForEach(Array(units(for: word).enumerated()), id: \.offset) { _, unit in
                    RubyUnitView(
                        unit: unit,
                        showFurigana: showFurigana,
                        baseSize: baseSize,
                        isHighlighted: word.id == highlightedWordID,
                        inSelectedSentence: word.sentenceIndex == highlightedSentence
                    )
                    .contentShape(.rect)
                    .onTapGesture {
                        guard word.isLookupable else { return }
                        onTap(word)
                    }
                    .onLongPressGesture(minimumDuration: 0.35) {
                        onLongPress?(word)
                    }
                }
            }
        }
    }

    /// 一个词拆成若干渲染单位：注音段整体一个，普通文字逐字一个（这样才能换行）。
    private func units(for word: ReaderWord) -> [RubyUnit] {
        word.segments.flatMap { segment -> [RubyUnit] in
            switch segment {
            case .plain(let text):
                text.map { RubyUnit(base: String($0), reading: nil) }
            case .ruby(let base, let reading):
                [RubyUnit(base: base, reading: reading)]
            }
        }
    }
}

struct RubyUnit {
    let base: String
    let reading: String?
}

struct RubyUnitView: View {
    let unit: RubyUnit
    let showFurigana: Bool
    let baseSize: CGFloat
    var isHighlighted: Bool = false
    var inSelectedSentence: Bool = false
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 0) {
            // 没注音的字也占一行高度，否则同一行里带注音和不带注音的字会错开。
            Text(unit.reading ?? " ")
                .font(.japanese(baseSize * 0.5))
                .foregroundStyle(color.opacity(0.7))
                // 关闭时用透明度而不是移除 —— 行高不能跳
                .opacity(showFurigana && unit.reading != nil ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: showFurigana)
            VStack(spacing: 1) {
                Text(unit.base)
                    .font(.japanese(baseSize))
                    .foregroundStyle(color)
                    // 选中整句时铺一层最淡的金底。金色不做大面积填充是这套系统的规矩，
                    // 但 accent-100 已经淡到只是「有色的纸」，不算填充。
                    .background(inSelectedSentence ? Theme.Palette.accent100 : .clear)
                // 命中时下方 2pt 金色下划线。未选中时是同宽透明条，
                // 不用 if 判断增删视图 —— 那会让整行文字上下跳动。
                Rectangle()
                    .fill(isHighlighted ? Theme.Palette.accent : Color.clear)
                    .frame(height: 2)
            }
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.2), value: inSelectedSentence)
    }
}

/// 折行流式布局：一行放不下就换行。
struct RubyFlowLayout: Layout {
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = arrange(subviews: subviews, maxWidth: maxWidth)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (line.height - item.size.height)),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width
            }
            y += line.height + lineSpacing
        }
    }

    private struct Item { let index: Int; let size: CGSize }
    private struct Line {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.items.isEmpty, current.width + size.width > maxWidth {
                lines.append(current)
                current = Line()
            }
            current.items.append(Item(index: index, size: size))
            current.width += size.width
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty { lines.append(current) }
        return lines
    }
}
