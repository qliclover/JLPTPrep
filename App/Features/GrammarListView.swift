import SwiftUI
import SwiftData
import JLPTCore
import JLPTContent

/// 语法列表。按等级分组，点一条看详解。
///
/// 语法条目和单词共用同一套 SRS —— 它们的 `ReviewItemEntity` 只是 kind 不同，
/// 所以会一起进每日队列，不需要单独的复习入口。
struct GrammarListView: View {
    let scope: Set<JLPTLevel>

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \GrammarEntity.slug) private var all: [GrammarEntity]
    @State private var search = ""
    @State private var opened: GrammarEntity?

    private var entries: [GrammarEntity] {
        all.filter { entry in
            guard !entry.isRetired, scope.contains(entry.level) else { return false }
            guard !search.isEmpty else { return true }
            return entry.pattern.contains(search)
                || entry.meaningZh.contains(search)
                || entry.tags.contains { $0.contains(search) }
        }
    }

    private var grouped: [(level: JLPTLevel, entries: [GrammarEntity])] {
        Dictionary(grouping: entries, by: \.level)
            .map { (level: $0.key, entries: $0.value) }
            .sorted { $0.level.difficulty < $1.level.difficulty }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(grouped, id: \.level) { group in
                            section(group.level, group.entries)
                        }
                    }
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.bottom, Theme.Space.s6)
                }
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .sheet(item: $opened) { GrammarDetailSheet(entry: $0, all: all) }
        #if DEBUG
        .task {
            // 验证用：直接打开一条带辨析和易混跳转的
            if ScreenshotMode.current == .grammar {
                opened = entries.first { $0.slug == "n4-sou-hearsay" } ?? entries.first
            }
        }
        #endif
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← 设置") { dismiss() }
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
                Spacer()
                Text("语法")
                    .font(.classicalHeading(19))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Text("← 设置")
                    .font(.classicalBody(13))
                    .opacity(0)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)

            // 自绘搜索框：系统 searchable 会带自己的圆角和背景，
            // 和这套设计的发丝线语言不搭
            HStack(spacing: Theme.Space.s2) {
                Text("搜索")
                    .font(.classicalBody(12))
                    .foregroundStyle(Theme.Palette.neutral500)
                TextField("句型、意思或标签", text: $search)
                    .font(.classicalBody(14))
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button("清除") { search = "" }
                        .font(.classicalBody(12))
                        .foregroundStyle(Theme.Palette.accent700)
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, Theme.Space.s3)
            Hairline()
        }
    }

    private func section(_ level: JLPTLevel, _ items: [GrammarEntity]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: level.rawValue)
                Spacer()
                Text("\(items.count) 条")
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral600)
            }
            .padding(.top, Theme.Space.s6)
            .padding(.bottom, Theme.Space.s3)

            ForEach(items) { entry in
                Hairline()
                row(entry)
            }
            Hairline()
        }
    }

    private func row(_ entry: GrammarEntity) -> some View {
        Button { opened = entry } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s1) {
                Text(entry.pattern)
                    .font(.japanese(19, weight: .medium))
                    .foregroundStyle(Theme.Palette.text)
                Text(entry.meaningZh)
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral700)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.s3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s4) {
            Spacer()
            Text(search.isEmpty ? "还没有语法条目" : "没找到")
                .font(.classicalHeading(24))
                .foregroundStyle(Theme.Palette.text)
            Spacer()
        }
    }
}

/// 语法详解。
struct GrammarDetailSheet: View {
    let entry: GrammarEntity
    let all: [GrammarEntity]

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.showFurigana) private var showFurigana = true

    private var contrasts: [GrammarEntity] {
        entry.contrastSlugs.compactMap { slug in all.first { $0.slug == slug } }
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Palette.neutral400)
                .frame(width: 36, height: 1)
                .padding(.top, Theme.Space.s2)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                    header
                    field("接续", entry.connectionRule)
                    field("意思", entry.meaningZh)
                    if let note = entry.noteZh, !note.isEmpty { discussion(note) }
                    examples
                    if !contrasts.isEmpty { contrastSection }
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, Theme.Space.s4)
            }

            VStack(spacing: 0) {
                Hairline()
                Button { dismiss() } label: {
                    Text("关掉").frame(maxWidth: .infinity)
                }
                .buttonStyle(ClassicalButtonStyle(kind: .secondary))
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, Theme.Space.s3)
            }
        }
        .background(Theme.Palette.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack(alignment: .top) {
                Text(entry.pattern)
                    .font(.japanese(30, weight: .medium))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                ClassicalTag(text: entry.level.rawValue, style: .accent)
            }
            if !entry.tags.isEmpty {
                HStack(spacing: Theme.Space.s2) {
                    ForEach(entry.tags, id: \.self) { tag in
                        ClassicalTag(text: tag, style: .neutral)
                    }
                    Spacer()
                }
            }
            Hairline()
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Kicker(text: label)
            Text(value)
                .font(.classicalBody(15))
                .lineSpacing(5)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 辨析。这一节是整条语法里最该看的东西 —— 真题考的就是这些差别，
    /// 所以给它一个金色描边的块，和普通字段区分开。
    ///
    /// 正文里的 `**…**` 标出的是关键区别（比如「只靠接续区分」），
    /// 必须渲染成粗体。SwiftUI 的 `Text` 只对**字符串字面量**解析 Markdown，
    /// 对变量不解析 —— 直接传变量的话星号会原样显示。
    private func discussion(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Kicker(text: "要点")
            Text(markdown(text))
                .font(.classicalBody(14))
                .lineSpacing(6)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.s4)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(Theme.Palette.accent, lineWidth: Theme.hairline)
                )
        }
    }

    /// 把 `**粗体**` 解析成富文本。解析失败就退回纯文本 ——
    /// 内容里带个孤零零的星号不该让整段消失。
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Kicker(text: "例句")
            ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, example in
                HStack(alignment: .top, spacing: 0) {
                    // 例句块左侧一条金色竖线，和复习卡、笔记同一套语言
                    Rectangle()
                        .fill(Theme.Palette.accent)
                        .frame(width: Theme.hairline)
                    VStack(alignment: .leading, spacing: Theme.Space.s1) {
                        RubyText(
                            annotated: example.furigana ?? example.ja,
                            showFurigana: showFurigana,
                            baseSize: 17,
                            color: Theme.Palette.text
                        )
                        Text(example.zh)
                            .font(.classicalBody(13))
                            .foregroundStyle(Theme.Palette.neutral700)
                    }
                    .padding(.leading, Theme.Space.s3)
                }
            }
        }
    }

    private var contrastSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Kicker(text: "易混")
            ForEach(contrasts) { other in
                VStack(alignment: .leading, spacing: 2) {
                    Text(other.pattern)
                        .font(.japanese(17, weight: .medium))
                        .foregroundStyle(Theme.Palette.text)
                    Text(other.meaningZh)
                        .font(.classicalBody(12))
                        .foregroundStyle(Theme.Palette.neutral600)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Theme.Space.s2)
                Hairline()
            }
        }
    }
}
