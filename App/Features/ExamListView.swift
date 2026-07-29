import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import JLPTCore
import JLPTContent

/// 真题列表。导入的试卷都在这儿，点一份开始做。
///
/// App 出厂**不带任何试卷** —— 真题是在卖的商品，打进上架的包就是再分发。
/// 你导入自己的题库文件，内容始终留在自己设备上。
struct ExamListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ExamEntity.session, order: .reverse) private var exams: [ExamEntity]

    @State private var showingImporter = false
    @State private var message: String?
    @State private var opened: ExamEntity?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if exams.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        summary
                        ForEach(exams) { exam in
                            Hairline()
                            row(exam)
                        }
                        Hairline()
                        if let message { note(message) }
                    }
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.bottom, Theme.Space.s6)
                }
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .fullScreenCover(item: $opened) { ExamRunnerView(exam: $0) }
        #if DEBUG
        .task {
            // 验证用：直接进第一套试卷
            if ScreenshotMode.current == .examRunner { opened = exams.first }
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
                Text("真题")
                    .font(.classicalHeading(19))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Button("导入") { showingImporter = true }
                    .buttonStyle(ClassicalButtonStyle(size: 13, verticalPadding: 6))
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
            Hairline()
        }
    }

    private var summary: some View {
        let total = exams.reduce(0) { $0 + $1.questions.count }
        let done = exams.reduce(0) { $0 + $1.answeredCount }
        return Text("\(exams.count) 套试卷 · 共 \(total) 题 · 做过 \(done) 题")
            .font(.classicalBody(12))
            .monospacedDigit()
            .foregroundStyle(Theme.Palette.neutral600)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.s4)
    }

    private func row(_ exam: ExamEntity) -> some View {
        Button { opened = exam } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Space.s2) {
                        Text(exam.session)
                            .font(.classicalBody(15))
                            .foregroundStyle(Theme.Palette.text)
                        ClassicalTag(text: exam.level, style: .accent)
                    }
                    Text(detail(exam))
                        .font(.classicalBody(11))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.neutral600)
                }
                Spacer()
                if let accuracy = exam.accuracy {
                    Text("\(Int((accuracy * 100).rounded()))%")
                        .font(.classicalHeading(22, liningFigures: true))
                        .foregroundStyle(Theme.Palette.accent700)
                } else {
                    Text("›")
                        .font(.classicalHeading(18))
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .padding(.vertical, Theme.Space.s3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除这套", role: .destructive) {
                context.delete(exam)
                try? context.save()
            }
        }
    }

    private func detail(_ exam: ExamEntity) -> String {
        var parts = ["\(exam.questions.count) 题"]
        if exam.answeredCount > 0 {
            parts.append("做了 \(exam.answeredCount) · 对 \(exam.correctCount)")
        }
        if exam.hasAudio { parts.append("有听力音频") }
        return parts.joined(separator: " · ")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.classicalBody(13))
            .lineSpacing(4)
            .foregroundStyle(Theme.Palette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.s4)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.Palette.accent, lineWidth: Theme.hairline)
            )
            .padding(.top, Theme.Space.s4)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s4) {
            Spacer()
            Text("还没有试卷")
                .font(.classicalHeading(26))
                .foregroundStyle(Theme.Palette.text)
            Text("""
                 点右上角导入题库文件（.json）。

                 App 不随包附带任何真题 —— 真题是在卖的商品，\
                 打进安装包就是再分发。你导入自己的文件，\
                 内容始终留在这台设备上。
                 """)
                .font(.classicalBody(13))
                .lineSpacing(7)
                .multilineTextAlignment(.leading)
                .foregroundStyle(Theme.Palette.neutral600)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.s8)
    }

    private func handleImport(_ result: Result<[URL], any Error>) {
        do {
            var imported = 0, skipped = 0, files = 0
            for url in try result.get() {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let report = try ExamImporter.import(
                        data: Data(contentsOf: url), into: context
                    )
                    imported += report.imported
                    skipped += report.skipped
                    files += 1
                } catch {
                    // 单个文件失败不该中断整批 —— 一次选二十份，
                    // 其中一份没有可用题目是常事。
                    continue
                }
            }
            message = files == 0
                ? "选中的文件里没有可用的题目。"
                : "导入 \(files) 套试卷、\(imported) 道题。"
                    + (skipped > 0 ? "\n跳过 \(skipped) 道：缺答案或选项不全。" : "")
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }
}
