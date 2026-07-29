import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import JLPTCore
import JLPTContent

/// 备份与恢复。
///
/// 从现在到考试是几个月的投入，而这些数据只在一台手机上。
/// 手机丢了、误删了 App —— 全部归零，没有第二份。
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var stats = Stats()
    @State private var exportURL: URL?
    @State private var showingImporter = false
    @State private var message: Message?

    private struct Stats {
        var items = 0
        var studied = 0
        var logs = 0
        var notes = 0
        var books = 0
    }

    private struct Message: Identifiable {
        let text: String
        let isError: Bool
        var id: String { text }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                    contents
                    actions
                    if let message {
                        note(message)
                    }
                    explanation
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, Theme.Space.s4)
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .task {
            refresh()
            #if DEBUG
            runProbeIfRequested()
            #endif
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(item: $exportURL) { url in
            ShareSheet(items: [url])
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← 设置") { dismiss() }
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
                Spacer()
                Text("备份")
                    .font(.classicalHeading(19))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Text("← 设置")
                    .font(.classicalBody(13))
                    .opacity(0)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
            Hairline()
        }
    }

    // MARK: - 内容清单

    private var contents: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: "会备份什么")
                .padding(.bottom, Theme.Space.s3)
            statRow("学过的词", "\(stats.studied) / \(stats.items)")
            Hairline()
            statRow("复习记录", "\(stats.logs) 条")
            Hairline()
            statRow("笔记", "\(stats.notes) 条")
            Hairline()
            statRow("书籍进度", "\(stats.books) 本")
            Hairline()
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.classicalBody(14))
                .foregroundStyle(Theme.Palette.text)
            Spacer()
            Text(value)
                .font(.classicalBody(13))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.neutral600)
        }
        .padding(.vertical, Theme.Space.s3)
    }

    // MARK: - 动作

    private var actions: some View {
        VStack(spacing: Theme.Space.s3) {
            Button { makeExport() } label: {
                Text("导出备份文件").frame(maxWidth: .infinity)
            }
            .buttonStyle(ClassicalButtonStyle())

            Button { showingImporter = true } label: {
                Text("从备份恢复").frame(maxWidth: .infinity)
            }
            .buttonStyle(ClassicalButtonStyle(kind: .secondary))
        }
    }

    private func note(_ message: Message) -> some View {
        Text(message.text)
            .font(.classicalBody(13))
            .lineSpacing(4)
            .foregroundStyle(message.isError ? Theme.Palette.accent700 : Theme.Palette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.s4)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    // 这套系统里没有语义红，错误态也用金描边
                    .strokeBorder(Theme.Palette.accent, lineWidth: Theme.hairline)
            )
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Kicker(text: "说明")
            Text("""
                 备份是一个可读的 JSON 文件，存到「文件」App 或隔空投送到电脑都行。\
                 出问题时你能自己打开看。

                 恢复是**合并**，不是覆盖：同一个词两边都有进度时，取最近复习过的那一份。\
                 导入一份旧备份不会把这之后学的推回去。

                 词库和随包的 8 本书不进备份 —— 重装就有。\
                 你自己导入的书会连正文一起存，因为原文件可能早就删了。
                 """)
                .font(.classicalBody(12))
                .lineSpacing(5)
                .foregroundStyle(Theme.Palette.neutral600)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 数据

    private func refresh() {
        let items = (try? context.fetch(FetchDescriptor<ReviewItemEntity>())) ?? []
        stats = Stats(
            items: items.count,
            studied: items.count { $0.srs.stage != .new },
            logs: (try? context.fetchCount(FetchDescriptor<ReviewLogEntity>())) ?? 0,
            notes: (try? context.fetchCount(FetchDescriptor<NoteEntity>())) ?? 0,
            books: (try? context.fetchCount(FetchDescriptor<BookEntity>())) ?? 0
        )
    }

    private func makeExport() {
        do {
            let data = try ProgressArchive.encode(ProgressArchive.export(from: context))
            let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("日本語-备份-\(stamp).json")
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            message = Message(text: "导出失败：\(error.localizedDescription)", isError: true)
        }
    }

    private func handleImport(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { return }
            // 文件选择器给的是沙箱外的 URL，必须显式申请访问
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let archive = try ProgressArchive.decode(Data(contentsOf: url))
            let report = try ProgressArchive.restore(archive, into: context)
            refresh()

            var parts: [String] = []
            if report.itemsUpdated > 0 { parts.append("\(report.itemsUpdated) 个词的进度") }
            if report.logsInserted > 0 { parts.append("\(report.logsInserted) 条复习记录") }
            if report.notesInserted > 0 { parts.append("\(report.notesInserted) 条笔记") }
            if report.booksInserted > 0 { parts.append("\(report.booksInserted) 本书") }

            message = if parts.isEmpty {
                Message(
                    text: "备份里的内容这台设备上都已经有了，或者更新。什么都没改。",
                    isError: false
                )
            } else {
                Message(
                    text: "恢复了 \(parts.joined(separator: "、"))。"
                        + (report.itemsSkipped > 0
                           ? "\n跳过 \(report.itemsSkipped) 个：本地进度更新，或词库里没有这个词。"
                           : ""),
                    isError: false
                )
            }
        } catch {
            message = Message(text: "恢复失败：\(error.localizedDescription)", isError: true)
        }
    }
}

#if DEBUG
extension BackupView {
    /// `-verifyBackup`：用**真实的随包内容**跑一次导出→解码→恢复。
    ///
    /// 单元测试用的是几条合成数据；这里是 1382 个词、上百条日志、9 本书的实际规模，
    /// 验的是文件大小、编码耗时、以及「恢复到自己身上不该改动任何东西」。
    func runProbeIfRequested() {
        guard CommandLine.arguments.contains("-verifyBackup") else { return }
        do {
            let started = Date()
            let archive = try ProgressArchive.export(from: context)
            let data = try ProgressArchive.encode(archive)
            let encodeTime = Date().timeIntervalSince(started)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("probe-backup.json")
            try data.write(to: url, options: .atomic)

            NSLog("[BackupProbe] 卡片 %d · 日志 %d · 笔记 %d · 书 %d",
                  archive.items.count, archive.logs.count,
                  archive.notes.count, archive.books.count)
            NSLog("[BackupProbe] 文件 %.1f KB，编码耗时 %.2fs",
                  Double(data.count) / 1024, encodeTime)
            NSLog("[BackupProbe] 带正文的书 %d 本（其余是随包的，不存正文）",
                  archive.books.count { $0.text != nil })

            // 恢复到自己身上：一切都已存在且不更新，应该什么都不改
            let decoded = try ProgressArchive.decode(data)
            let report = try ProgressArchive.restore(decoded, into: context)
            NSLog("[BackupProbe] 自恢复：更新 %d · 跳过 %d · 新增日志 %d · 笔记 %d · 书 %d",
                  report.itemsUpdated, report.itemsSkipped,
                  report.logsInserted, report.notesInserted, report.booksInserted)
            NSLog("[BackupProbe] %@", report.logsInserted == 0 && report.notesInserted == 0
                  && report.booksInserted == 0 ? "✓ 幂等" : "✗ 自恢复产生了重复数据")
        } catch {
            NSLog("[BackupProbe] ✗ %@", error.localizedDescription)
        }
    }
}
#endif

/// 让 URL 能直接喂给 `.sheet(item:)`。
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// 系统分享面板。导出后交给用户自己决定存哪儿 ——
/// 存「文件」、隔空投送、发给自己，都比 App 自作主张选一个位置强。
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
