import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import JLPTContent

/// 「4. 书架」。正在读的书用卡片突出，其余是纯 hairline 列表行。
struct BookshelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BookEntity.importedAt, order: .reverse) private var books: [BookEntity]

    @AppStorage(SettingKey.didSeedSampleBook) private var didSeedSampleBook = false

    @State private var showingImporter = false
    @State private var importError: String?
    @State private var openedBook: BookEntity?
    @State private var showingNotes = false

    /// 正在读：最近打开过且没读完。
    private var currentBook: BookEntity? {
        books
            .filter { $0.lastOpenedAt != nil && $0.progress < 1 }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    private var others: [BookEntity] {
        books.filter { $0.uuid != currentBook?.uuid }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if books.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s6) {
                        if let currentBook {
                            currentCard(currentBook)
                        }
                        if let importError {
                            errorCard(importError)
                        }
                        list
                    }
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.vertical, Theme.Space.s4)
                }
            }
        }
        .background(Theme.Palette.bg)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .text, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .task {
            seedSampleBookIfNeeded()
            #if DEBUG
            // 笔记要挂在书上，必须等随包书籍落库之后再铺
            ScreenshotSeed.apply(in: context)
            if let index = CommandLine.arguments.firstIndex(of: "-openTitled"),
               index + 1 < CommandLine.arguments.count {
                let needle = CommandLine.arguments[index + 1]
                openedBook = books.first { $0.title.contains(needle) }
            } else if CommandLine.arguments.contains("-autoOpenBook") {
                openedBook = books.first { $0.title.contains("蜘蛛") } ?? books.first
            }
            switch ScreenshotMode.current {
            case .reader, .readerVertical, .wordDetail:
                openedBook = books.first { $0.title.contains("蜘蛛") } ?? books.first
            case .notes:
                showingNotes = true
            default:
                break
            }
            #endif
        }
        .fullScreenCover(item: $openedBook) { book in
            ReaderView(book: book)
        }
        .sheet(isPresented: $showingNotes) { NotesView() }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("书架")
                    .font(.classicalHeading(26))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Button("笔记") { showingNotes = true }
                    .buttonStyle(ClassicalButtonStyle(kind: .secondary, size: 13, verticalPadding: 6))
                Button("导入") { showingImporter = true }
                    .buttonStyle(ClassicalButtonStyle(size: 13, verticalPadding: 6))
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.top, Theme.Space.s4)
            .padding(.bottom, Theme.Space.s3)
            Hairline()
        }
    }

    // MARK: - 正在读

    private func currentCard(_ book: BookEntity) -> some View {
        Button { openedBook = book } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                Kicker(text: "正在读")
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Theme.Space.s1) {
                        Text(book.title)
                            .font(.japanese(25, weight: .medium))
                            .foregroundStyle(Theme.Palette.text)
                            .multilineTextAlignment(.leading)
                        Text(book.author ?? "—")
                            .font(.classicalBody(13))
                            .foregroundStyle(Theme.Palette.neutral700)
                    }
                    Spacer()
                    Text("\(Int(book.progress * 100))%")
                        .font(.classicalHeading(28, liningFigures: true))
                        .foregroundStyle(Theme.Palette.accent700)
                }
                ClassicalProgress(value: book.progress)
                Text(meta(book))
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral600)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .classicalCard()
        }
        .buttonStyle(.plain)
    }

    private func meta(_ book: BookEntity) -> String {
        var parts = ["\(book.charCount) 字"]
        if book.hasEmbeddedRuby { parts.append("原文注音") }
        parts.append(book.encodingName)
        parts.append("第 \(book.paragraphIndex) 段")
        return parts.joined(separator: " · ")
    }

    // MARK: - 其余书

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(others) { book in
                Hairline()
                Button { openedBook = book } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Theme.Space.s1) {
                            Text(book.title)
                                .font(.japanese(18, weight: .medium))
                                .foregroundStyle(Theme.Palette.text)
                                .lineLimit(1)
                            Text(shortMeta(book))
                                .font(.classicalBody(11))
                                .monospacedDigit()
                                .foregroundStyle(Theme.Palette.neutral600)
                        }
                        Spacer()
                        Text(status(book))
                            .font(.classicalBody(12))
                            .monospacedDigit()
                            .foregroundStyle(
                                book.progress > 0 ? Theme.Palette.accent700 : Theme.Palette.neutral600
                            )
                    }
                    .padding(.vertical, Theme.Space.s3)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Hairline()
        }
    }

    private func shortMeta(_ book: BookEntity) -> String {
        var parts: [String] = []
        if let author = book.author { parts.append(author) }
        parts.append("\(book.charCount) 字")
        if book.hasEmbeddedRuby { parts.append("原文注音") }
        return parts.joined(separator: " · ")
    }

    private func status(_ book: BookEntity) -> String {
        if book.progress >= 1 { return "读完" }
        if book.paragraphIndex > 0 { return "\(Int(book.progress * 100))%" }
        return "未读"
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s6) {
            Spacer()
            BookSpine()
            VStack(spacing: Theme.Space.s3) {
                Text("架子还空着")
                    .font(.classicalHeading(26))
                    .foregroundStyle(Theme.Palette.text)
                Text("导入 .txt 或带文字层的 PDF。\n编码认得 UTF-8 / Shift_JIS / EUC-JP，\n青空文庫的原文注音会自动识别。")
                    .font(.classicalBody(13))
                    .lineSpacing(13)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Palette.neutral600)
                Text("扫描件不行 —— 本 App 不做 OCR")
                    .font(.classicalBody(11))
                    .foregroundStyle(Theme.Palette.neutral500)
            }
            Button("导入文件") { showingImporter = true }
                .buttonStyle(ClassicalButtonStyle())
            Spacer()
        }
        .padding(.horizontal, Theme.Space.s8)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text(message)
                .font(.classicalBody(13))
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("其他文件不受影响，可以继续导入。")
                .font(.classicalBody(12))
                .foregroundStyle(Theme.Palette.neutral600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.s4)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                // 这套系统里没有语义红，错误态也用金描边
                .strokeBorder(Theme.Palette.accent, lineWidth: Theme.hairline)
        )
    }

    // MARK: - 导入

    /// 首次启动导入随包的书。只做一次 —— 用户删掉哪本就是不想要哪本。
    private func seedSampleBookIfNeeded() {
        guard !didSeedSampleBook else { return }
        didSeedSampleBook = true

        // 显式清单，不是「导入 bundle 里所有 .txt」——
        // 那样字体许可这类资源文件也会被当成书导进来（真发生过）。
        let bundled = [
            "gon_gitsune", "tebukuro_wo_kai_ni",
            "kumo_no_ito", "toshishun", "rashomon",
            "chumon_no_oi_ryoriten", "cello_hiki_no_goshu",
            "hashire_melos", "sample_reading",
        ]
        let urls = bundled.compactMap { Bundle.main.url(forResource: $0, withExtension: "txt") }
        guard !urls.isEmpty else { return }

        let importer = BookImporter()
        var failures: [String] = []
        for url in urls {
            do {
                try importer.importBook(
                    data: Data(contentsOf: url),
                    filename: url.lastPathComponent,
                    into: context
                )
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        if !failures.isEmpty {
            importError = "这些随包读物导入失败：\(failures.joined(separator: "、"))"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let importer = BookImporter()
            for url in urls {
                // 文件选择器给的是沙盒外的 URL，必须先申请访问权限。
                guard url.startAccessingSecurityScopedResource() else {
                    importError = "无法访问 \(url.lastPathComponent)"
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                try importer.importBook(data: data, filename: url.lastPathComponent, into: context)
            }
            importError = nil
        } catch let error as BookImportError {
            importError = error.errorDescription
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// 空状态的书影：1px 描边矩形 + 135° 斜纹。设计里没有位图资源。
private struct BookSpine: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 12
            var offset: CGFloat = -size.height
            while offset < size.width {
                var path = Path()
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                context.stroke(path, with: .color(Theme.Palette.neutral300), lineWidth: 6)
                offset += spacing
            }
        }
        .frame(width: 118, height: 154)
        .clipped()
        .overlay(
            Rectangle().strokeBorder(Theme.divider, lineWidth: Theme.hairline)
        )
    }
}
