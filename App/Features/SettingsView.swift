import SwiftUI
import SwiftData
import JLPTCore
import JLPTContent

/// 「7. 设置」。自绘滑杆与开关 —— 系统控件的白色大圆角卡片和语义绿
/// 都不在这套设计语言里（不用大圆角，也没有语义色）。
struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(SettingKey.newCardsPerDay) private var newCardsPerDay = 15
    @AppStorage(SettingKey.maxReviewsPerDay) private var maxReviewsPerDay = 200
    @AppStorage(SettingKey.showFurigana) private var showFurigana = true
    @AppStorage(SettingKey.readerVertical) private var readerVertical = false
    @AppStorage(SettingKey.targetLevel) private var targetLevelRaw = "N4"
    @AppStorage(SettingKey.reviewMode) private var reviewMode = "flip"
    @AppStorage(SettingKey.remindersOn) private var remindersOn = false
    @AppStorage(SettingKey.reminderHour) private var reminderHour = 20
    @AppStorage(SettingKey.reminderMinute) private var reminderMinute = 0

    @State private var showingPacks = false
    @State private var showingAbout = false
    @State private var enabledSummary = ""
    @State private var troubleSummary = ""
    @State private var examSummary = ""
    @State private var notificationDenied = false
    @State private var showingTrouble = false
    @State private var showingBackup = false
    @State private var showingExams = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text("设置")
                    .font(.classicalHeading(26))
                    .foregroundStyle(Theme.Palette.text)
                    .padding(.top, Theme.Space.s4)

                reviewStyle
                dailyQuota
                reminder
                review
                reading
                library
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, Theme.Space.s8)
        }
        .background(Theme.Palette.bg)
        .sheet(isPresented: $showingPacks, onDismiss: refresh) { PackLibraryView() }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .fullScreenCover(isPresented: $showingBackup, onDismiss: refresh) { BackupView() }
        .fullScreenCover(isPresented: $showingExams, onDismiss: refresh) { ExamListView() }
        .fullScreenCover(isPresented: $showingTrouble, onDismiss: refresh) {
            TroubleView(
                scope: (JLPTLevel(rawValue: targetLevelRaw) ?? .n4).cumulativeScope,
                packIDs: (try? PackLibrary().enabledPackIDs(in: context)) ?? [],
                newCardsPerDay: newCardsPerDay,
                maxReviewsPerDay: maxReviewsPerDay
            )
        }
        .task {
            refresh()
            notificationDenied = await ReminderScheduler.authorizationStatus() == .denied
            #if DEBUG
            if ScreenshotMode.current == .packs { showingPacks = true }
            if ScreenshotMode.current == .trouble { showingTrouble = true }
            if ScreenshotMode.current == .backup { showingBackup = true }
            if ScreenshotMode.current == .exams || ScreenshotMode.current == .examRunner {
                // 截图/验证模式：直接把真实题库导进来
                importBundledExamsForScreenshot()
                showingExams = true
            }
            #endif
        }
        .onChange(of: targetLevelRaw) { refresh() }
        // 开关一开就要权限；用户在系统弹窗里点了不允许，这里立刻把开关拨回去，
        // 而不是留一个「开着但不会响」的假象。
        .onChange(of: remindersOn) { _, on in
            Task {
                if on {
                    let status = await ReminderScheduler.requestAuthorization()
                    notificationDenied = status == .denied
                    if notificationDenied { remindersOn = false; return }
                } else {
                    ReminderScheduler.clearBadge()
                }
                await applyReminders()
            }
        }
        .onChange(of: reminderHour) { Task { await applyReminders() } }
        .onChange(of: reminderMinute) { Task { await applyReminders() } }
        .onChange(of: newCardsPerDay) { Task { await applyReminders() } }
    }

    // MARK: - 复习方式

    private var reviewStyle: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Kicker(text: "复习方式")
            HStack(spacing: 0) {
                modeSegment("翻卡自评", value: "flip")
                modeSegment("选择题", value: "quiz")
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.divider, lineWidth: Theme.hairline)
            )
            Text(reviewMode == "quiz"
                 ? "从四个近似选项里选 —— 干扰项按清浊、长短、促音这些真题套路生成。答对三次才算过，一次蒙对不作数。"
                 : "看词、翻面、自己判断记没记住。速度快，但「我觉得我记得」和考场上选对是两回事。")
                .font(.classicalBody(12))
                .lineSpacing(4)
                .foregroundStyle(Theme.Palette.neutral600)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeSegment(_ label: String, value: String) -> some View {
        let selected = reviewMode == value
        return Button { reviewMode = value } label: {
            Text(label)
                .font(.classicalBody(14))
                .foregroundStyle(selected ? Theme.Palette.accent700 : Theme.Palette.neutral600)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.s2)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .strokeBorder(selected ? Theme.Palette.accent : .clear, lineWidth: Theme.hairline)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 每日额度

    private var dailyQuota: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Kicker(text: "每日额度")

            quotaRow("新词上限", value: $newCardsPerDay, range: 0...60, step: 5)
            quotaRow("复习上限", value: $maxReviewsPerDay, range: 20...500, step: 20)

            Text("新词上限决定每天引进多少生面孔；复习上限是断更之后的护栏，免得回来时被两百多张卡按住。")
                .font(.classicalBody(12))
                .lineSpacing(4)
                .foregroundStyle(Theme.Palette.neutral600)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func quotaRow(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.classicalBody(14))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.classicalHeading(26, liningFigures: true))
                    .foregroundStyle(Theme.Palette.text)
            }
            HairlineSlider(value: value, range: range, step: step)
        }
    }

    // MARK: - 阅读

    private var reading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: "阅读")
                .padding(.bottom, Theme.Space.s3)
            toggleRow("显示振假名", isOn: $showFurigana)
            Hairline()
            toggleRow("默认竖排", isOn: $readerVertical)
        }
    }

    // MARK: - 提醒

    private var reminder: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: "提醒")
                .padding(.bottom, Theme.Space.s3)

            toggleRow("每日提醒", isOn: $remindersOn)

            if remindersOn {
                Hairline()
                HStack {
                    Text("提醒时间")
                        .font(.classicalBody(14))
                        .foregroundStyle(Theme.Palette.text)
                    Spacer()
                    // 系统的 DatePicker 轮盘和这套设计不搭，用两个自绘步进器
                    HStack(spacing: Theme.Space.s1) {
                        Stepper2(value: $reminderHour, range: 0...23, format: "%02d")
                        Text(":")
                            .font(.classicalHeading(16, liningFigures: true))
                            .foregroundStyle(Theme.Palette.neutral600)
                        Stepper2(value: $reminderMinute, range: 0...59, step: 5, format: "%02d")
                    }
                }
                .padding(.vertical, Theme.Space.s3)

                Hairline()
                Text(reminderNote)
                    .font(.classicalBody(12))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.Palette.neutral600)
                    .padding(.vertical, Theme.Space.s3)
            }
        }
    }

    /// 提醒状态的说明文字。权限被拒时要说清楚去哪儿开，而不是静默失效。
    private var reminderNote: String {
        switch notificationDenied {
        case true:
            "系统里关掉了这个 App 的通知权限。\n去「设置 › 通知 › 日本語」重新打开。"
        case false:
            "提前排好未来 7 天，每天写清那天有多少张。\n没有待办的日子不推。"
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.classicalBody(14))
                .foregroundStyle(Theme.Palette.text)
            Spacer()
            CapsuleToggle(isOn: isOn)
        }
        .padding(.vertical, Theme.Space.s3)
        .contentShape(.rect)
        .onTapGesture { isOn.wrappedValue.toggle() }
    }

    // MARK: - 复盘

    private var review: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: "复盘")
                .padding(.bottom, Theme.Space.s3)

            Button { showingTrouble = true } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("错题本")
                            .font(.classicalBody(14))
                            .foregroundStyle(Theme.Palette.text)
                        Text(troubleSummary)
                            .font(.classicalBody(11))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.neutral600)
                    }
                    Spacer()
                    Text("›")
                        .font(.classicalHeading(18))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .padding(.vertical, Theme.Space.s3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Hairline()

            Button { showingExams = true } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("真题")
                            .font(.classicalBody(14))
                            .foregroundStyle(Theme.Palette.text)
                        Text(examSummary)
                            .font(.classicalBody(11))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.neutral600)
                    }
                    Spacer()
                    Text("›")
                        .font(.classicalHeading(18))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .padding(.vertical, Theme.Space.s3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Hairline()

            Button { showingBackup = true } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("备份")
                            .font(.classicalBody(14))
                            .foregroundStyle(Theme.Palette.text)
                        Text("导出一份进度文件，换设备或重装能接着用")
                            .font(.classicalBody(11))
                            .foregroundStyle(Theme.Palette.neutral600)
                    }
                    Spacer()
                    Text("›")
                        .font(.classicalHeading(18))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .padding(.vertical, Theme.Space.s3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Hairline()
        }
    }

    // MARK: - 词库

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: "词库")
                .padding(.bottom, Theme.Space.s3)

            Button { showingPacks = true } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("等级词库 · N5–N1")
                            .font(.classicalBody(14))
                            .foregroundStyle(Theme.Palette.text)
                        Text(enabledSummary)
                            .font(.classicalBody(11))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.neutral600)
                    }
                    Spacer()
                    Text("›")
                        .font(.classicalHeading(18))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .padding(.vertical, Theme.Space.s3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Hairline()

            HStack {
                Text("JMdict 词典")
                    .font(.classicalBody(14))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Text(
                    DictionaryStore.isAvailable
                        ? "已安装 · \(DictionaryStore.shared?.entryCount ?? 0) 条"
                        : "未安装"
                )
                .font(.classicalBody(11))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.neutral600)
            }
            .padding(.vertical, Theme.Space.s3)

            Hairline()

            Button { showingAbout = true } label: {
                HStack {
                    Text("关于 · 许可")
                        .font(.classicalBody(14))
                        .foregroundStyle(Theme.Palette.text)
                    Spacer()
                    Text("›")
                        .font(.classicalHeading(18))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .padding(.vertical, Theme.Space.s3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// 按当前设置重排提醒。
    ///
    /// 范围必须和首页队列完全一致 —— 通知里报 23 张、打开只有 8 张，
    /// 这个提醒就再也不会被信任了。
    private func applyReminders() async {
        let goal = JLPTLevel(rawValue: targetLevelRaw) ?? .n4
        let enabled = (try? PackLibrary().enabledPackIDs(in: context)) ?? []
        await ReminderScheduler.reschedule(
            enabled: remindersOn,
            hour: reminderHour,
            minute: reminderMinute,
            in: context,
            session: ReviewSession(queueConfig: DailyQueueConfig(
                newCardsPerDay: newCardsPerDay,
                maxReviewsPerDay: maxReviewsPerDay
            )),
            levels: goal.cumulativeScope,
            packIDs: enabled
        )
    }

    #if DEBUG
    /// 截图与验证用：把 `Docs/exams/` 下的题库文件读进来。
    /// 真机上这些文件不存在，只有开发机跑得到。
    private func importBundledExamsForScreenshot() {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .deletingLastPathComponent().deletingLastPathComponent()
        _ = dir
        let source = URL(fileURLWithPath: "/Users/qianli/JLPTPrep/Docs/exams")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: source, includingPropertiesForKeys: nil
        ) else { return }
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            _ = try? ExamImporter.import(data: data, into: context)
        }
    }
    #endif

    private func refresh() {
        let packs = (try? PackLibrary().packs(in: context).filter(\.enabled)) ?? []
        let names = packs
            .sorted { $0.level.difficulty < $1.level.difficulty }
            .map(\.level.rawValue)
        let goal = JLPTLevel(rawValue: targetLevelRaw) ?? .n4
        let enabledIDs = (try? PackLibrary().enabledPackIDs(in: context)) ?? []
        let spots = (try? ReviewSession().troubleSpots(
            in: context, levels: goal.cumulativeScope, packIDs: enabledIDs
        )) ?? []
        troubleSummary = spots.isEmpty
            ? "最近 60 天没有按过「忘了」"
            : "最近 60 天 \(spots.count) 个词反复错 · 最多错了 \(spots[0].againCount) 次"

        let exams = (try? context.fetch(FetchDescriptor<ExamEntity>())) ?? []
        let totalQuestions = exams.reduce(0) { $0 + $1.questions.count }
        let answered = exams.reduce(0) { $0 + $1.answeredCount }
        examSummary = exams.isEmpty
            ? "还没导入试卷"
            : "\(exams.count) 套 · \(totalQuestions) 题 · 做过 \(answered)"

        enabledSummary = names.isEmpty
            ? "目标 \(targetLevelRaw) · 还没启用任何包"
            : "目标 \(targetLevelRaw) · 已启用 \(names.joined(separator: " · ")) · \(packs.reduce(0) { $0 + $1.itemCount }) 词"
    }
}

/// 两键步进器。系统 `DatePicker` 的轮盘和这套设计不搭 ——
/// 它带自己的圆角、自己的高亮色、自己的字体，塞进来像贴了张别人家的贴纸。
///
/// 数字用 lining figures：Cormorant 默认是旧式数字，`20:05` 里的 0 只有 x-height，
/// 高低起伏，读起来像乱码。
private struct Stepper2: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let format: String

    var body: some View {
        HStack(spacing: 0) {
            key("−") { move(-step) }
            Text(String(format: format, value))
                .font(.classicalHeading(17, liningFigures: true))
                .foregroundStyle(Theme.Palette.text)
                .frame(minWidth: 30)
            key("+") { move(step) }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.Palette.neutral300, lineWidth: Theme.hairline)
        )
    }

    private func key(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.classicalHeading(15))
                .foregroundStyle(Theme.Palette.accent700)
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// 到头就绕回去 —— 时间是环形的，23 点再加一小时是 0 点，不是卡在 23。
    private func move(_ delta: Int) {
        let span = range.upperBound - range.lowerBound + 1
        value = (value - range.lowerBound + delta + span) % span + range.lowerBound
    }
}

/// 发丝滑杆：1px 轨 + 3pt 金色已填段 + 11pt 圆形把手（底色填充 + 1px 金描边）。
private struct HairlineSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    private var fraction: Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return Double(value - range.lowerBound) / span
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: Theme.hairline)
                Rectangle()
                    .fill(Theme.Palette.accent)
                    .frame(width: width * fraction, height: 3)
                Circle()
                    .fill(Theme.Palette.bg)
                    .overlay(Circle().strokeBorder(Theme.Palette.accent, lineWidth: Theme.hairline))
                    .frame(width: 11, height: 11)
                    .offset(x: max(0, width * fraction - 5.5))
            }
            .frame(height: 22)
            .contentShape(.rect)
            // 点轨道或拖动都直接改值
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        update(to: gesture.location.x / max(width, 1))
                    }
            )
            .animation(.easeOut(duration: 0.18), value: value)
        }
        .frame(height: 22)
    }

    private func update(to fraction: Double) {
        let span = Double(range.upperBound - range.lowerBound)
        let raw = Double(range.lowerBound) + min(max(fraction, 0), 1) * span
        // 吸附到步长
        let snapped = (raw / Double(step)).rounded() * Double(step)
        value = min(max(Int(snapped), range.lowerBound), range.upperBound)
    }
}

/// 44×24 胶囊开关。开 = 金描边 + accent-100 底 + 金色圆钮右移；关 = neutral-400。
private struct CapsuleToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.Palette.accent100 : Color.clear)
            .overlay(
                Capsule().strokeBorder(
                    isOn ? Theme.Palette.accent : Theme.Palette.neutral400,
                    lineWidth: Theme.hairline
                )
            )
            .overlay(alignment: .leading) {
                Circle()
                    .fill(isOn ? Theme.Palette.accent : Theme.Palette.neutral400)
                    .frame(width: 18, height: 18)
                    .offset(x: isOn ? 23 : 3)
            }
            .frame(width: 44, height: 24)
            .animation(.easeOut(duration: 0.2), value: isOn)
    }
}
