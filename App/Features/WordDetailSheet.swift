import SwiftUI
import SwiftData
import JLPTCore
import JLPTContent
import JLPTJapanese

/// 「6. 点词详情」底部弹层。
///
/// 分两层信息：**词形还原**不依赖词库，任何词都给得出；
/// **释义**依赖词库，查不到就明说查不到，不编。
struct WordDetailSheet: View {
    let word: ReaderWord
    let bookTitle: String
    let bookUUID: UUID
    let paragraphIndex: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var analysis: [Deinflection] = []
    @State private var entry: VocabEntity?
    @State private var dictionaryEntries: [DictionaryEntry] = []
    @State private var starred = false
    @State private var collected = false
    @State private var noteText = ""
    @State private var noteSaved = false

    var body: some View {
        VStack(spacing: 0) {
            handle
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                    header
                    morphology
                    meaning
                    noteEditor
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, Theme.Space.s4)
            }
            actions
        }
        .background(Theme.Palette.bg)
        .task { load() }
    }

    private var handle: some View {
        Rectangle()
            .fill(Theme.Palette.neutral400)
            .frame(width: 36, height: 1)
            .padding(.top, Theme.Space.s2)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Space.s1) {
                    TappableRubyText(
                        words: [word],
                        showFurigana: true,
                        baseSize: 38,
                        onTap: { _ in }
                    )
                    Kicker(
                        text: "\(bookTitle) · 第 \(paragraphIndex) 段",
                        color: Theme.Palette.neutral600,
                        size: 11
                    )
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Theme.Space.s2) {
                    if Speaker.shared.isAvailable, spokenText != nil {
                        Button(isSpeaking ? "朗读中" : "朗读") { speak() }
                            .buttonStyle(ClassicalButtonStyle(
                                kind: isSpeaking ? .primary : .secondary,
                                size: 13,
                                verticalPadding: 6
                            ))
                    }
                    Button(starred ? "已收藏" : "收藏") { toggleStar() }
                        .buttonStyle(ClassicalButtonStyle(
                            kind: starred ? .primary : .secondary,
                            size: 13,
                            verticalPadding: 6
                        ))
                }
            }
            Hairline()
        }
    }

    // MARK: - 朗读

    /// 念什么：**假名优先**。
    ///
    /// 合成器拿到汉字会自己猜读音，多音词上经常猜错 ——「乾く」可能读成 かんく。
    /// 词库里的读音是经过校验的，能用就用它；退而求其次用分词器给的读音；
    /// 都没有（纯假名词）才用原文本身。
    private var spokenText: String? {
        if let reading = entry?.reading, !reading.isEmpty { return reading }
        if let reading = word.reading, !reading.isEmpty { return reading }
        return word.isLookupable ? word.surface : nil
    }

    private var isSpeaking: Bool {
        spokenText != nil && Speaker.shared.speaking == spokenText
    }

    private func speak() {
        guard let spokenText else { return }
        Speaker.shared.speak(spokenText)
    }

    // MARK: - 词形还原（不依赖词库）

    @ViewBuilder
    private var morphology: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Kicker(text: "词形还原")

            if let best = analysis.first {
                HStack(spacing: Theme.Space.s2) {
                    Text(best.dictionaryForm)
                        .font(.japanese(26, weight: .medium))
                        .foregroundStyle(Theme.Palette.text)
                    if best.wordClass != .unknown {
                        ClassicalTag(text: best.wordClass.labelZh, style: .outline)
                    }
                    Spacer()
                }

                // 链式展示：待って ← [て形] ← 待つ
                if !best.isBaseForm {
                    Text(chain(best))
                        .font(.japanese(13))
                        .foregroundStyle(Theme.Palette.neutral700)
                }

                // 有歧义时把其他候选也列出来，不假装只有一个答案
                let others = analysis.dropFirst().prefix(3)
                if !others.isEmpty {
                    Text("其他可能：" + others.map(\.dictionaryForm).joined(separator: "、"))
                        .font(.classicalBody(12))
                        .foregroundStyle(Theme.Palette.neutral500)
                }
            } else {
                Text("没有识别出活用变形，可能是名词、助词或专有名词。")
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
            }
        }
    }

    private func chain(_ deinflection: Deinflection) -> String {
        // steps 是「由近到远」，链式展示要从表面形一路退回原形
        let arrows = deinflection.steps.map { "← [\($0)] " }.joined()
        return "\(word.surface) \(arrows)← \(deinflection.dictionaryForm)"
    }

    // MARK: - 释义（依赖词库）

    @ViewBuilder
    private var meaning: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack {
                Kicker(text: "释义")
                Spacer()
                if entry != nil {
                    Kicker(text: "本地词库", color: Theme.Palette.neutral500, size: 10)
                } else if !dictionaryEntries.isEmpty {
                    Kicker(text: "JMdict", color: Theme.Palette.neutral500, size: 10)
                }
            }

            if let entry {
                Text(entry.displayMeaning)
                    .font(.classicalBody(15))
                    .lineSpacing(15 * 0.8)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Space.s2) {
                    ClassicalTag(text: entry.partOfSpeech, style: .neutral)
                    ClassicalTag(text: entry.level.rawValue, style: .accent)
                    Spacer()
                }
            } else if !dictionaryEntries.isEmpty {
                ForEach(dictionaryEntries.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: Theme.Space.s1) {
                        HStack(spacing: Theme.Space.s2) {
                            Text(item.headword)
                                .font(.japanese(15, weight: .medium))
                            if item.headword != item.reading {
                                Text(item.reading)
                                    .font(.japanese(13))
                                    .foregroundStyle(Theme.Palette.neutral600)
                            }
                            if item.isCommon {
                                ClassicalTag(text: "常用", style: .accent)
                            }
                            Spacer()
                        }
                        Text(item.glossesEn)
                            .font(.classicalBody(14))
                            .foregroundStyle(Theme.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.partOfSpeechLabelsZh.isEmpty {
                            Text(item.partOfSpeechLabelsZh.joined(separator: " · "))
                                .font(.classicalBody(11))
                                .foregroundStyle(Theme.Palette.neutral600)
                        }
                    }
                    .padding(.vertical, Theme.Space.s2)
                }
                Text("中文释义只覆盖 JLPT 核心词，其余显示 JMdict 的英文。")
                    .font(.classicalBody(12))
                    .foregroundStyle(Theme.Palette.neutral600)
            } else {
                Text(DictionaryStore.isAvailable ? "词典里没有这个词。" : "词典未安装。")
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
            }
        }
    }

    // MARK: - 笔记

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Kicker(text: "笔记")
            TextField("记点什么…", text: $noteText, axis: .vertical)
                .font(.classicalBody(14))
                .lineLimit(2...5)
                .padding(Theme.Space.s3)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(Theme.divider, lineWidth: Theme.hairline)
                )
                .onChange(of: noteText) { noteSaved = false }

            Button { saveNote() } label: {
                Text(noteSaved ? "已存进笔记" : "存进笔记").frame(maxWidth: .infinity)
            }
            .buttonStyle(ClassicalButtonStyle(kind: .secondary, size: 13, verticalPadding: 8))
            .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || noteSaved)
        }
    }

    private func saveNote() {
        let body = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        context.insert(NoteEntity(
            bookUUID: bookUUID,
            paragraphIndex: paragraphIndex,
            quotedText: word.surface,
            body: body
        ))
        try? context.save()
        noteSaved = true
    }

    // MARK: - 底部两键

    private var actions: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Theme.Space.s2) {
                Button { dismiss() } label: {
                    Text("关掉").frame(maxWidth: .infinity)
                }
                .buttonStyle(ClassicalButtonStyle(kind: .secondary))

                Button { collect() } label: {
                    Text(collected ? "已加入今日卡组" : "加进今日卡组").frame(maxWidth: .infinity)
                }
                .buttonStyle(ClassicalButtonStyle())
                .disabled(collected)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
        }
    }

    // MARK: - 数据

    private func load() {
        let dictionary = DictionaryStore.shared

        // 活用消歧同时问两个来源：自有词库（有中文）和 JMdict（20 万词条兜底）。
        let candidates = Deinflector.deinflect(word.surface) { form in
            lookup(form) != nil || dictionary?.contains(form) == true
        }
        analysis = candidates

        let forms = [word.surface] + candidates.map(\.dictionaryForm)
        entry = forms.lazy.compactMap { lookup($0) }.first
        if entry == nil, let dictionary {
            dictionaryEntries = forms.lazy.map { dictionary.lookup($0) }.first { !$0.isEmpty } ?? []
        }
        starred = entry.flatMap { reviewItem(for: $0.slug)?.isStarred } ?? false
        collected = entry != nil
    }

    private func lookup(_ text: String) -> VocabEntity? {
        var descriptor = FetchDescriptor<VocabEntity>(
            predicate: #Predicate { $0.expression == text && $0.isRetired == false }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func reviewItem(for slug: String) -> ReviewItemEntity? {
        let key = ReviewItemEntity.key(kind: .vocab, slug: slug)
        var descriptor = FetchDescriptor<ReviewItemEntity>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func toggleStar() {
        guard let entry, let item = reviewItem(for: entry.slug) else { return }
        item.isStarred.toggle()
        starred = item.isStarred
        try? context.save()
    }

    /// 把这个词收进生词本并进 SRS 队列。这是「阅读 → 背词」闭环的那一步。
    private func collect() {
        let best = analysis.first
        let expression = best?.dictionaryForm ?? word.surface
        let reading = word.reading ?? expression
        // 中文优先；没有就用 JMdict 的英文，总比空着强
        let meaning = entry?.displayMeaning ?? dictionaryEntries.first?.glossesEn ?? ""
        let pos = entry?.partOfSpeech
            ?? dictionaryEntries.first?.partOfSpeechLabelsZh.first
            ?? best?.wordClass.labelZh
            ?? "未分类"

        do {
            try VocabCollector().collect(
                expression: expression,
                reading: reading,
                meaningZh: meaning,
                partOfSpeech: pos,
                into: context
            )
            collected = true
        } catch {
            collected = false
        }
    }
}
