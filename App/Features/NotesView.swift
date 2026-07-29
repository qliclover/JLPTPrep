import SwiftUI
import SwiftData
import JLPTContent

/// 笔记列表。按书分组，点一条跳回原文那一段。
///
/// 之前笔记只能写不能看 —— 存了也是石沉大海，等于没有这个功能。
struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \NoteEntity.createdAt, order: .reverse) private var notes: [NoteEntity]
    @Query private var books: [BookEntity]

    /// 点开某条笔记要跳回的书和段落。
    @State private var jump: Jump?

    struct Jump: Identifiable {
        let book: BookEntity
        let paragraphIndex: Int
        var id: String { "\(book.uuid)-\(paragraphIndex)" }
    }

    private struct Group: Identifiable {
        let book: BookEntity?
        let notes: [NoteEntity]
        var id: String { book?.uuid.uuidString ?? "orphan" }
        var title: String { book?.title ?? "已删除的书" }
    }

    private var groups: [Group] {
        let byBook = Dictionary(grouping: notes, by: \.bookUUID)
        return byBook
            .map { uuid, notes in
                Group(book: books.first { $0.uuid == uuid }, notes: notes)
            }
            // 最近记过笔记的书排前面
            .sorted { ($0.notes.first?.createdAt ?? .distantPast) > ($1.notes.first?.createdAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if notes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s6) {
                        ForEach(groups) { group in
                            section(group)
                        }
                    }
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.vertical, Theme.Space.s4)
                }
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .fullScreenCover(item: $jump) { jump in
            ReaderView(book: jump.book, jumpToParagraph: jump.paragraphIndex)
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← 书架") { dismiss() }
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
                Spacer()
                Text("笔记")
                    .font(.classicalHeading(19))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Text("← 书架")
                    .font(.classicalBody(13))
                    .opacity(0)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
            Hairline()
        }
    }

    private func section(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.title)
                    .font(.japanese(18, weight: .medium))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Text("\(group.notes.count) 条")
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral600)
            }
            .padding(.bottom, Theme.Space.s3)

            ForEach(group.notes) { note in
                Hairline()
                row(note, book: group.book)
            }
            Hairline()
        }
    }

    private func row(_ note: NoteEntity, book: BookEntity?) -> some View {
        Button {
            if let book { jump = Jump(book: book, paragraphIndex: note.paragraphIndex) }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                // 划选的原文：左侧一条金色竖线，和复习卡的例句块同一套语言
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(Theme.Palette.accent)
                        .frame(width: Theme.hairline)
                    Text(note.quotedText)
                        .font(.japanese(15))
                        .foregroundStyle(Theme.Palette.neutral700)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .padding(.leading, Theme.Space.s3)
                }

                Text(note.body)
                    .font(.classicalBody(14))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                Text("第 \(note.paragraphIndex) 段 · \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.s3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) { delete(note) }
        }
        // ScrollView 里没有 swipeActions，用长按补一个删除出口
        .contextMenu {
            Button("删除这条笔记", role: .destructive) { delete(note) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s4) {
            Spacer()
            Text("还没有笔记")
                .font(.classicalHeading(26))
                .foregroundStyle(Theme.Palette.text)
            Text("读书时点一个词或长按一句，\n在弹出的面板里就能记。")
                .font(.classicalBody(13))
                .lineSpacing(8)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Palette.neutral600)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.s8)
    }

    private func delete(_ note: NoteEntity) {
        context.delete(note)
        try? context.save()
    }
}
