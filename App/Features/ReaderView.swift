import SwiftUI
import SwiftData
import JLPTCore
import JLPTContent
import JLPTJapanese

/// 「5. 阅读器」。
struct ReaderView: View {
    let book: BookEntity
    /// 从笔记跳回来时指定的段落；nil 表示接着上次读到的地方。
    var jumpToParagraph: Int?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.showFurigana) private var showFurigana = true
    @AppStorage(SettingKey.readerVertical) private var defaultVertical = false

    @State private var paragraphs: [String] = []
    @State private var selection: WordSelection?
    @State private var sentenceSelection: SentenceSelection?
    /// 点过的词和选中的句子，用来画高亮。
    @State private var highlightedWord: Int?
    @State private var highlightedSentence: Int?
    @State private var highlightedParagraph: Int?
    @State private var vertical = false
    /// 阅读位置只在内存里累加，退出时才写库。几万段的书快速滚一遍
    /// 会触发几万次 onAppear，每次都写 SwiftData 会明显掉帧。
    @State private var furthestParagraph = 0
    @State private var visibleParagraph = 0

    struct SentenceSelection: Identifiable {
        let text: String
        let paragraphIndex: Int
        var id: String { "\(paragraphIndex)-\(text.hashValue)" }
    }

    struct WordSelection: Identifiable {
        let word: ReaderWord
        let paragraphIndex: Int
        var id: String { "\(paragraphIndex)-\(word.id)" }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
            bottomBar
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .sheet(item: $selection) { selection in
            WordDetailSheet(
                word: selection.word,
                bookTitle: book.title,
                bookUUID: book.uuid,
                paragraphIndex: selection.paragraphIndex
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(Theme.Radius.lg)
        }
        .sheet(item: $sentenceSelection) { selection in
            SentenceSheet(
                sentence: selection.text,
                bookTitle: book.title,
                bookUUID: book.uuid,
                paragraphIndex: selection.paragraphIndex
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(Theme.Radius.lg)
        }
        .onAppear {
            paragraphs = book.splitParagraphs()
            let start = jumpToParagraph ?? book.paragraphIndex
            furthestParagraph = book.paragraphIndex
            visibleParagraph = start
            vertical = defaultVertical
            #if DEBUG
            if CommandLine.arguments.contains("-autoVertical") { vertical = true }
            if ScreenshotMode.current == .readerVertical { vertical = true }
            if CommandLine.arguments.contains("-autoSentence") {
                // 自动化验证：选中第一段的第一句
                let text = paragraphs.first ?? ""
                let plain = FuriganaParser.plainText(text)
                if let first = SentenceSplitter.sentences(in: plain).first {
                    highlightedParagraph = 0
                    highlightedSentence = 0
                    sentenceSelection = SentenceSelection(text: first, paragraphIndex: 0)
                }
            }
            if ScreenshotMode.current == .wordDetail {
                // 挑第一段里第一个带汉字的词 —— 纯假名词看不出词形还原，
                // 也体现不了「朗读喂的是假名不是汉字」这件事。
                // 找第一个「像样的词」：两字以上、含汉字、有读音。
                // 单字会挑到章节号「一」那种数词 —— 既看不出词形还原，
                // 也体现不了「朗读喂假名而不是汉字」这件事。
                // 要跨段找：第一段往往只有一个章节号。
                outer: for (index, paragraph) in paragraphs.enumerated() {
                    for word in ReaderText.words(annotated: paragraph)
                    where word.isLookupable
                        && word.surface.count >= 2
                        && word.surface.unicodeScalars.contains(where: Kana.isKanji)
                        && word.reading?.isEmpty == false
                    {
                        selection = WordSelection(word: word, paragraphIndex: index)
                        break outer
                    }
                }
            }
            #endif
            book.lastOpenedAt = Date()
        }
        .onDisappear {
            // 只往前记，不因为向上翻看一眼就把进度倒退回去。
            book.paragraphIndex = max(book.paragraphIndex, furthestParagraph)
            try? context.save()
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← 书架") { dismiss() }
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
                Spacer()
                OrientationSegment(vertical: $vertical)
                Spacer()
                Button(showFurigana ? "ふり ON" : "ふり OFF") { showFurigana.toggle() }
                    .font(.classicalBody(12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.accent700)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
            Hairline()
        }
    }

    // MARK: - 正文

    @ViewBuilder
    private var content: some View {
        if vertical {
            VerticalReader(
                paragraphs: paragraphs,
                startIndex: jumpToParagraph ?? book.paragraphIndex,
                isPreAnnotated: book.hasEmbeddedRuby,
                showFurigana: showFurigana,
                onTapWord: { word, index in
                    selection = WordSelection(word: word, paragraphIndex: index)
                },
                onVisibleParagraph: { index in
                    furthestParagraph = max(furthestParagraph, index)
                    visibleParagraph = index
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.s4) {
                        // 用下标而不是 enumerated()：后者每次 body 求值都要
                        // 现造一个几万元素的元组数组。
                        ForEach(paragraphs.indices, id: \.self) { index in
                            ParagraphView(
                                text: paragraphs[index],
                                isPreAnnotated: book.hasEmbeddedRuby,
                                showFurigana: showFurigana,
                                highlightedWord: highlightedParagraph == index ? highlightedWord : nil,
                                highlightedSentence: highlightedParagraph == index ? highlightedSentence : nil,
                                onTapWord: { word in
                                    highlightedParagraph = index
                                    highlightedWord = word.id
                                    highlightedSentence = nil
                                    selection = WordSelection(word: word, paragraphIndex: index)
                                },
                                onLongPressWord: { word, sentence in
                                    highlightedParagraph = index
                                    highlightedSentence = word.sentenceIndex
                                    highlightedWord = nil
                                    sentenceSelection = SentenceSelection(text: sentence, paragraphIndex: index)
                                }
                            )
                            .id(index)
                            .onAppear {
                                furthestParagraph = max(furthestParagraph, index)
                                visibleParagraph = index
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.vertical, Theme.Space.s6)
                }
                .onAppear {
                    let start = jumpToParagraph ?? book.paragraphIndex
                    if start > 0 { proxy.scrollTo(start, anchor: .top) }
                }
            }
        }
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Theme.Space.s3) {
                Text("\(visibleParagraph)")
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral600)
                GeometryReader { geometry in
                    let fraction = paragraphs.count > 1
                        ? Double(visibleParagraph) / Double(paragraphs.count - 1)
                        : 0
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: Theme.hairline)
                            .frame(maxHeight: .infinity, alignment: .center)
                        // 位置是一个 7×7 的金色方点，不是圆头滑块
                        Rectangle()
                            .fill(Theme.Palette.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: max(0, (geometry.size.width - 7) * fraction))
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(height: 7)
                Text("\(paragraphs.count)")
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral600)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
        }
    }
}

/// 横/縦 段控。
private struct OrientationSegment: View {
    @Binding var vertical: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment("横", selected: !vertical) { vertical = false }
            segment("縦", selected: vertical) { vertical = true }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .strokeBorder(Theme.divider, lineWidth: Theme.hairline)
        )
    }

    private func segment(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.japanese(13))
                .foregroundStyle(selected ? Theme.Palette.accent700 : Theme.Palette.neutral600)
                .padding(.horizontal, Theme.Space.s3)
                .padding(.vertical, Theme.Space.s1)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .strokeBorder(selected ? Theme.Palette.accent : .clear, lineWidth: Theme.hairline)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// 一个段落。
///
/// 注音和分词都在**这一层**按需做，不是整本书一次性算完 —— 一部长篇有几万字，
/// 全量处理要好几秒，而 `LazyVStack` 只会构造屏幕上看得见的那几段。
private struct ParagraphView: View {
    let text: String
    /// 原文已经带注音（青空文庫），跳过运行时分词生成注音这一步。
    let isPreAnnotated: Bool
    let showFurigana: Bool
    var highlightedWord: Int?
    var highlightedSentence: Int?
    let onTapWord: (ReaderWord) -> Void
    let onLongPressWord: (ReaderWord, String) -> Void

    @State private var words: [ReaderWord]?

    var body: some View {
        Group {
            if let words {
                TappableRubyText(
                    words: words,
                    showFurigana: showFurigana,
                    baseSize: 19,
                    highlightedWordID: highlightedWord,
                    highlightedSentence: highlightedSentence,
                    onTap: onTapWord,
                    onLongPress: { word in
                        // 整句文本从同一批词里拼回来，保证和高亮范围完全一致
                        let sentence = words
                            .filter { $0.sentenceIndex == word.sentenceIndex }
                            .map(\.surface)
                            .joined()
                        onLongPressWord(word, sentence)
                    }
                )
            } else {
                // 还在处理时先把原文显示出来，不留白。
                Text(FuriganaParser.plainText(text))
                    .font(.japanese(19))
                    .foregroundStyle(Theme.Palette.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: text) {
            guard words == nil else { return }
            let source = text
            let preAnnotated = isPreAnnotated
            words = await Task.detached(priority: .userInitiated) {
                let annotated = preAnnotated ? source : RubyAnnotator.annotate(source)
                return ReaderText.words(annotated: annotated)
            }.value
        }
    }
}
