import SwiftUI
import JLPTCore
import JLPTJapanese

/// 竖排阅读。
///
/// 逐字自上而下、列自右向左；振假名排在字的**右侧**（横排时在上方）。
/// 标点和延伸记号按 `VerticalGlyph` 的规则旋转或偏移。
///
/// 分批构建：竖排是逐字布局，一次排完整本几万字会把内存和布局都拖垮。
/// 这里按段落分批，滚到末尾再排下一批。
struct VerticalReader: View {
    let paragraphs: [String]
    let startIndex: Int
    let isPreAnnotated: Bool
    let showFurigana: Bool
    var baseSize: CGFloat = 19
    var onTapWord: (ReaderWord, Int) -> Void
    var onVisibleParagraph: (Int) -> Void

    @State private var columns: [VerticalColumn] = []
    /// 已经排到第几段（相对 `startIndex`）。
    @State private var builtCount = 0
    @State private var building = false
    @State private var columnHeight: CGFloat = 0

    /// 每批排多少段。太小会频繁触发构建，太大就失去了分批的意义。
    private let batchSize = 15

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                // 列自右向左：把列序反过来排，再让滚动视图从右端开始
                HStack(alignment: .top, spacing: baseSize * 1.15) {
                    ForEach(columns.reversed()) { column in
                        columnView(column)
                            .onAppear {
                                onVisibleParagraph(column.paragraphIndex)
                                // 最左（也就是最后排出来的）那一列露头了，就再排一批
                                if column.id == columns.last?.id { extend() }
                            }
                    }
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, Theme.Space.s4)
            }
            .defaultScrollAnchor(.trailing)
            .task(id: paragraphs.count) {
                columnHeight = geometry.size.height - Theme.Space.s4 * 2
                columns = []
                builtCount = 0
                extend()
            }
        }
    }

    private func columnView(_ column: VerticalColumn) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(column.units.enumerated()), id: \.offset) { _, unit in
                VerticalUnitView(unit: unit, showFurigana: showFurigana, baseSize: baseSize)
                    .contentShape(.rect)
                    .onTapGesture {
                        if let word = unit.word, word.isLookupable {
                            onTapWord(word, column.paragraphIndex)
                        }
                    }
            }
            Spacer(minLength: 0)
        }
        .frame(height: max(columnHeight, 1), alignment: .top)
    }

    private func extend() {
        guard !building, columnHeight > 0 else { return }
        let start = startIndex + builtCount
        guard start < paragraphs.count else { return }

        building = true
        let slice = Array(paragraphs[start..<min(start + batchSize, paragraphs.count)])
        let preAnnotated = isPreAnnotated
        let unitsPerColumn = max(4, Int(columnHeight / (baseSize * 1.5)))
        let firstIndex = start

        Task {
            let built = await Task.detached(priority: .userInitiated) {
                VerticalLayout.buildColumns(
                    slice,
                    firstParagraphIndex: firstIndex,
                    preAnnotated: preAnnotated,
                    unitsPerColumn: unitsPerColumn
                )
            }.value
            columns += built
            builtCount += slice.count
            building = false
        }
    }

}

/// 段落 → 列。独立出来是因为 `View` 整体是 MainActor 隔离的，
/// 里面的静态方法也跟着隔离，没法在后台线程调用。
enum VerticalLayout {
    /// `nonisolated`：App 目标默认把一切隔离到 MainActor，
    /// 而这是纯计算，必须能在后台线程跑 —— 分词和注音不便宜。
    nonisolated static func buildColumns(
        _ paragraphs: [String],
        firstParagraphIndex: Int,
        preAnnotated: Bool,
        unitsPerColumn: Int
    ) -> [VerticalColumn] {
        var result: [VerticalColumn] = []
        for (offset, paragraph) in paragraphs.enumerated() {
            let annotated = preAnnotated ? paragraph : RubyAnnotator.annotate(paragraph)
            let words = ReaderText.words(annotated: annotated)

            // 段首全角空格
            var units: [VerticalUnit] = [VerticalUnit(base: "　", reading: nil, word: nil)]
            for word in words {
                for segment in word.segments {
                    switch segment {
                    case .plain(let text):
                        // 拉丁字母和数字要横向成组，不能拆成一串直立字符
                        units += TateChuYoko.runs(in: text).map {
                            VerticalUnit(base: $0.text, reading: nil, word: word, mode: $0.mode)
                        }
                    case .ruby(let base, let reading):
                        // 注音跟着整个汉字词走，不拆
                        units.append(VerticalUnit(base: base, reading: reading, word: word))
                    }
                }
            }

            // 禁则处理：断点不能让「、。」」落到下一列开头，也不能让「「（」留在列尾
            let firsts = units.map { $0.base.first ?? "　" }
            var index = 0
            while index < units.count {
                let proposed = min(index + unitsPerColumn, units.count)
                let end = proposed >= units.count
                    ? proposed
                    : max(index + 1, LineBreakRules.adjustedBreak(firstCharacters: firsts, proposed: proposed))
                result.append(VerticalColumn(
                    paragraphIndex: firstParagraphIndex + offset,
                    units: Array(units[index..<end])
                ))
                index = end
            }
        }
        return result
    }
}

struct VerticalColumn: Identifiable {
    let id = UUID()
    let paragraphIndex: Int
    let units: [VerticalUnit]
}

struct VerticalUnit {
    let base: String
    let reading: String?
    /// 点词时要交回去的词。段首空格之类没有归属的单位为 nil。
    let word: ReaderWord?
    /// 拉丁字母 / 数字的排布方式，见 `TateChuYoko`。日文一律 `.japanese`。
    var mode: TateChuYoko.Mode = .japanese
}

private struct VerticalUnitView: View {
    let unit: VerticalUnit
    let showFurigana: Bool
    let baseSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                switch unit.mode {
                case .japanese:
                    ForEach(Array(unit.base.enumerated()), id: \.offset) { _, character in
                        glyph(character)
                    }
                case .upright:
                    // 縦中横：横着写，塞进一个字格，保持直立
                    Text(unit.base)
                        .font(.classicalBody(baseSize * 0.62))
                        .foregroundStyle(Theme.Palette.text)
                        .frame(width: baseSize * 1.05, height: baseSize * 1.5)
                case .rotated:
                    // 长串整组旋转，读的时候侧头
                    Text(unit.base)
                        .font(.classicalBody(baseSize * 0.9))
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize()
                        .rotationEffect(.degrees(90))
                        .frame(width: baseSize * 1.05)
                        .frame(height: baseSize * 0.62 * CGFloat(unit.base.count) + baseSize * 0.4)
                }
            }
            // 竖排的振假名在右侧
            VStack(spacing: 0) {
                ForEach(Array((unit.reading ?? "").enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.japanese(baseSize * 0.5))
                        .foregroundStyle(Theme.Palette.text.opacity(0.7))
                }
            }
            .frame(width: baseSize * 0.55, alignment: .leading)
            .opacity(showFurigana && unit.reading != nil ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: showFurigana)
        }
    }

    /// 单字。标点和延伸记号要旋转或偏移，见 `VerticalGlyph`。
    private func glyph(_ character: Character) -> some View {
        let placement = VerticalGlyph.placement(for: character)
        return Text(String(character))
            .font(.japanese(baseSize))
            .foregroundStyle(Theme.Palette.text)
            .rotationEffect(.degrees(placement.rotation))
            .offset(
                x: baseSize * placement.offsetX,
                y: baseSize * placement.offsetY
            )
            .frame(width: baseSize * 1.05, height: baseSize * 1.5)
    }
}
