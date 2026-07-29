import SwiftUI
import SwiftData
import JLPTCore
import JLPTContent

/// 「8. 等级词库」。选备考目标、导入 N5–N1 的词库包、启用/停用。
struct PackLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.targetLevel) private var targetLevelRaw = "N4"

    @Query(sort: \VocabPackEntity.levelRaw) private var storedPacks: [VocabPackEntity]

    @State private var packs: [VocabPackEntity] = []
    @State private var importing: JLPTLevel?
    @State private var importProgress: Double = 0
    @State private var report: (level: JLPTLevel, report: ImportReport)?
    @State private var errorText: String?

    private var goal: JLPTLevel { JLPTLevel(rawValue: targetLevelRaw) ?? .n4 }
    private var scope: Set<JLPTLevel> { goal.cumulativeScope }

    private var scopeLabel: String {
        JLPTLevel.allCases
            .filter { scope.contains($0) }
            .sorted { $0.difficulty < $1.difficulty }
            .map(\.rawValue)
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                    goalSection
                    packList
                    if let report {
                        reportCard(report)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.classicalBody(12))
                            .foregroundStyle(Theme.Palette.accent700)
                    }
                    footer
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, Theme.Space.s4)
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .task { packs = (try? PackLibrary().packs(in: context)) ?? [] }
        .onChange(of: storedPacks.count) { packs = (try? PackLibrary().packs(in: context)) ?? [] }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← 设置") { dismiss() }
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
                Spacer()
                Text("等级词库")
                    .font(.classicalHeading(19))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                // 右侧留白与左侧等宽，标题才真正居中
                Text("← 设置")
                    .font(.classicalBody(13))
                    .opacity(0)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
            Hairline()
        }
    }

    // MARK: - 备考目标

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Kicker(text: "备考目标")
            SegmentedLevels(selection: $targetLevelRaw)
            Text("考 \(goal.rawValue) 要连下面的等级一起背，所以范围是 \(scopeLabel)。超出范围的包不会进今天的队列。")
                .font(.classicalBody(12))
                .lineSpacing(4)
                .foregroundStyle(Theme.Palette.neutral600)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 词库包列表

    private var packList: some View {
        VStack(spacing: 0) {
            ForEach(packs) { pack in
                Hairline()
                packRow(pack)
                    .opacity(scope.contains(pack.level) ? 1 : 0.45)
                    .animation(.easeOut(duration: 0.2), value: scope)
            }
            Hairline()
        }
    }

    private func packRow(_ pack: VocabPackEntity) -> some View {
        let isImporting = importing == pack.level
        return VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s2) {
                Text(pack.level.rawValue)
                    .font(.classicalHeading(22, liningFigures: true))
                    .foregroundStyle(Theme.Palette.text)
                Text(name(for: pack.level))
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral700)
                Text(pack.imported ? "\(pack.itemCount) 词" : "\(referenceCount(pack.level)) 词")
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.neutral500)
                Spacer()
                actionButton(pack, isImporting: isImporting)
            }

            ClassicalProgress(
                value: isImporting ? importProgress : (pack.imported ? 1 : 0),
                tint: isImporting || pack.enabled ? Theme.Palette.accent : Theme.Palette.neutral400
            )

            HStack {
                Text(statusText(pack, isImporting: isImporting))
                    .font(.classicalBody(11))
                    .monospacedDigit()
                    .foregroundStyle(pack.enabled ? Theme.Palette.accent700 : Theme.Palette.neutral600)
                Spacer()
                Text(scope.contains(pack.level) ? "在备考范围内" : "超出当前目标")
                    .font(.classicalBody(11))
                    .foregroundStyle(Theme.Palette.neutral500)
            }
        }
        .padding(.vertical, Theme.Space.s3)
    }

    @ViewBuilder
    private func actionButton(_ pack: VocabPackEntity, isImporting: Bool) -> some View {
        if isImporting {
            Text("导入中")
                .font(.classicalBody(13))
                .foregroundStyle(Theme.Palette.neutral600)
        } else if !pack.imported {
            Button("导入") { runImport(pack) }
                .buttonStyle(ClassicalButtonStyle(size: 13, verticalPadding: 6))
        } else {
            Button(pack.enabled ? "停用" : "启用") { toggle(pack) }
                .buttonStyle(ClassicalButtonStyle(kind: .secondary, size: 13, verticalPadding: 6))
        }
    }

    private func statusText(_ pack: VocabPackEntity, isImporting: Bool) -> String {
        if isImporting { return "导入中 · \(Int(importProgress * 100))%" }
        if !pack.imported { return "未导入" }
        return pack.enabled ? "已启用" : "已导入 · 未启用"
    }

    private func name(for level: JLPTLevel) -> String {
        switch level {
        case .n5: "基础"
        case .n4: "初级"
        case .n3: "中级"
        case .n2: "中高级"
        case .n1: "高级"
        }
    }

    /// 未导入时显示的参考量。导入后换成包里的实际数。
    private func referenceCount(_ level: JLPTLevel) -> Int {
        switch level {
        case .n5: 717
        case .n4: 665
        case .n3: 2139
        case .n2: 1809
        case .n1: 2699
        }
    }

    // MARK: - 导入结果

    private func reportCard(_ value: (level: JLPTLevel, report: ImportReport)) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text("\(value.level.rawValue) 词库导入完成 · 新增 \(value.report.inserted) · 更新 \(value.report.updated) · 跳过 \(value.report.skipped ? value.report.unchanged : 0)")
                .font(.classicalBody(13))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.text)
            Text("导入只写内容表，不动已有进度；同一个包再导一次是空操作。")
                .font(.classicalBody(11))
                .foregroundStyle(Theme.Palette.neutral600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.s4)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.Palette.accent, lineWidth: Theme.hairline)
        )
        .transition(.opacity.combined(with: .offset(y: 10)))
    }

    private var footer: some View {
        let enabled = packs.filter(\.enabled)
        return Text("已启用 \(enabled.count) 个包，共 \(enabled.reduce(0) { $0 + $1.itemCount }) 词。停用某个包只是把它从队列里摘掉，进度会留着。")
            .font(.classicalBody(11))
            .lineSpacing(3)
            .monospacedDigit()
            .foregroundStyle(Theme.Palette.neutral500)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 动作

    private func runImport(_ pack: VocabPackEntity) {
        importing = pack.level
        importProgress = 0
        report = nil

        // 导入几千词要花点时间，放到下一个 runloop 让「导入中」先渲染出来。
        DispatchQueue.main.async {
            do {
                let result = try PackLibrary().import(
                    level: pack.level,
                    from: .main,
                    into: context,
                    progress: { value in
                        DispatchQueue.main.async {
                            withAnimation(.linear(duration: 0.2)) { importProgress = value }
                        }
                    }
                )
                importing = nil
                withAnimation(.easeOut(duration: 0.3)) { report = (pack.level, result) }
                packs = (try? PackLibrary().packs(in: context)) ?? []
            } catch {
                importing = nil
                errorText = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    private func toggle(_ pack: VocabPackEntity) {
        do {
            try PackLibrary().setEnabled(!pack.enabled, for: pack, in: context)
            packs = (try? PackLibrary().packs(in: context)) ?? []
        } catch {
            errorText = "保存失败：\(error.localizedDescription)"
        }
    }
}

/// 五格段控。选中格用 1px 金色内描边 + 金字，不填色。
private struct SegmentedLevels: View {
    @Binding var selection: String

    private let levels = JLPTLevel.allCases.sorted { $0.difficulty < $1.difficulty }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(levels, id: \.self) { level in
                let isSelected = level.rawValue == selection
                Button { selection = level.rawValue } label: {
                    Text(level.rawValue)
                        .font(.classicalHeading(15, liningFigures: true))
                        .foregroundStyle(isSelected ? Theme.Palette.accent700 : Theme.Palette.neutral600)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Space.s2)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .strokeBorder(
                                    isSelected ? Theme.Palette.accent : .clear,
                                    lineWidth: Theme.hairline
                                )
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.divider, lineWidth: Theme.hairline)
        )
    }
}
