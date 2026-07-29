import SwiftUI
import SwiftData
import JLPTCore
import JLPTContent
import JLPTJapanese
#if canImport(Translation)
import Translation
#endif

/// 选中一句之后的面板：原文 + 翻译。
///
/// 翻译走 Apple 的 `Translation` 框架 —— **端上运行、免费、离线**（首次要下语言包）。
/// 不接联网的 LLM：这个 App 的其他部分都能离线用，为一个功能引入网络依赖不划算。
/// 代价是它只做直译，不解释语法。
struct SentenceSheet: View {
    let sentence: String
    let bookTitle: String
    let bookUUID: UUID
    let paragraphIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingKey.showFurigana) private var showFurigana = true

    @State private var annotated: String?
    @State private var translated: String?
    @State private var translationError: String?
    @State private var noteText = ""
    @State private var noteSaved = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Palette.neutral400)
                .frame(width: 36, height: 1)
                .padding(.top, Theme.Space.s2)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                    original
                    translation
                    noteEditor
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, Theme.Space.s4)
            }

            VStack(spacing: 0) {
                Hairline()
                HStack(spacing: Theme.Space.s2) {
                    Button { dismiss() } label: {
                        Text("关掉").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ClassicalButtonStyle(kind: .secondary))

                    if Speaker.shared.isAvailable {
                        Button { Speaker.shared.speak(sentence) } label: {
                            Text(isSpeaking ? "停下" : "朗读").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ClassicalButtonStyle(kind: isSpeaking ? .emphasis : .primary))
                    }
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, Theme.Space.s3)
            }
        }
        .background(Theme.Palette.bg)
        .task { await prepare() }
        .onDisappear { Speaker.shared.stop() }
        .modifier(TranslationTask(
            text: sentence,
            translated: $translated,
            errorMessage: $translationError
        ))
    }

    // MARK: - 朗读

    private var isSpeaking: Bool { Speaker.shared.speaking == sentence }

    // 整句喂的是**带汉字的原文**，不是假名 —— 和单词那边正好相反。
    //
    // 单个词给假名是为了绕开合成器猜错读音；但整句给纯假名反而更糟：
    // 日语没有词间空格，合成器靠汉字和假名的交替来切词、定重音核。
    // 「にわにはにわにわとりがいる」这种全假名串，人也断不明白。
    //
    // 代价是青空文庫原文里那些生僻读音（作者用《》特意标了的）合成器可能读错。
    // 想彻底解决要把假名转成 IPA 走 `accessibilitySpeechIPANotation`，
    // 那是另一个项目，现在不做。

    // MARK: - 原文

    private var original: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            HStack {
                Kicker(text: "选中的句子")
                Spacer()
                Kicker(
                    text: "\(bookTitle) · 第 \(paragraphIndex) 段",
                    color: Theme.Palette.neutral600,
                    size: 10
                )
            }
            RubyText(
                annotated: annotated ?? sentence,
                showFurigana: showFurigana,
                baseSize: 20
            )
        }
    }

    // MARK: - 翻译

    @ViewBuilder
    private var translation: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack {
                Kicker(text: "翻译")
                Spacer()
                Kicker(text: "端上 · 离线", color: Theme.Palette.neutral500, size: 10)
            }

            if let translated {
                // 左侧一条金色竖线，和复习卡的例句块同一套语言
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(Theme.Palette.accent)
                        .frame(width: Theme.hairline)
                    Text(translated)
                        .font(.classicalBody(15))
                        .lineSpacing(15 * 0.8)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Theme.Space.s4)
                }
            } else if let translationError {
                Text(translationError)
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("翻译中…")
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral500)
            }
        }
    }

    // MARK: - 笔记

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Kicker(text: "笔记")
            TextField("这句哪里不懂…", text: $noteText, axis: .vertical)
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
            quotedText: sentence,
            body: body
        ))
        try? context.save()
        noteSaved = true
    }

    private func prepare() async {
        guard annotated == nil else { return }
        let source = sentence
        annotated = await Task.detached(priority: .userInitiated) {
            // 句子可能已经带注音（青空文庫），带了就别重复标
            source.contains("{") ? source : RubyAnnotator.annotate(source)
        }.value
    }
}

/// 把 `Translation` 框架包一层。
///
/// 编译期和运行期都要防守：框架本身是 iOS 17.4 引入的，
/// 但**编程式**的 `translationTask` 要 iOS 18。低于这个版本就明说不支持，
/// 而不是给一个转圈转到死的界面。
private struct TranslationTask: ViewModifier {
    let text: String
    @Binding var translated: String?
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            // 只捕获 Sendable 的局部量。整个 View 层默认隔离在 MainActor，
            // 而 `session.translate` 是 @concurrent 的 —— 闭包必须显式脱离主 actor，
            // 结果再跳回来写状态。
            let source = text
            let output = $translated
            let failure = $errorMessage
            content.translationTask(
                source: Locale.Language(identifier: "ja"),
                target: Locale.Language(identifier: "zh-Hans")
            ) { @concurrent session in
                let outcome: Result<String, any Error>
                do {
                    outcome = .success(try await session.translate(source).targetText)
                } catch {
                    outcome = .failure(error)
                }
                await MainActor.run {
                    switch outcome {
                    case .success(let value):
                        output.wrappedValue = value
                    case .failure(let error):
                        failure.wrappedValue =
                            "翻译不可用：\(error.localizedDescription)\n"
                            + "首次使用需要在「设置 › 通用 › 翻译」里下载日语和中文语言包。"
                    }
                }
            }
        } else {
            content.task { errorMessage = "句子翻译需要 iOS 18 或更高版本。" }
        }
        #else
        content.task { errorMessage = "当前平台不支持翻译。" }
        #endif
    }
}
