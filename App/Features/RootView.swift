import SwiftUI

struct RootView: View {
    enum Tab: String, CaseIterable {
        case study, shelf, settings

        var title: String {
            switch self {
            case .study: "学习"
            case .shelf: "书架"
            case .settings: "设置"
            }
        }
    }

    @State private var tab: Tab = .study
    /// 换 Tab 时内容整体淡出再淡入（150ms out / 180ms in），见设计稿的 `switchTo()`。
    @State private var contentOpacity: Double = 1

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .study: HomeView()
                case .shelf: BookshelfView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(contentOpacity)

            ClassicalTabBar(selection: tab, onSelect: switchTo)
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .onAppear { applyLaunchArguments() }
    }

    private func switchTo(_ next: Tab) {
        guard next != tab else { return }
        withAnimation(.easeOut(duration: 0.15)) { contentOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            tab = next
            withAnimation(.easeOut(duration: 0.18)) { contentOpacity = 1 }
        }
    }

    /// DEBUG 下允许用启动参数指定初始 tab：
    /// `xcrun simctl launch <device> <bundle> -startTab shelf`
    ///
    /// 这是给自动化验证和 UI 测试用的钩子，Release 构建里不存在。
    private func applyLaunchArguments() {
        #if DEBUG
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "-startTab"),
           index + 1 < arguments.count,
           let value = Tab(rawValue: arguments[index + 1]) {
            tab = value
        }
        // 截图模式自己知道该落在哪个 tab
        if let mode = ScreenshotMode.current {
            tab = mode.tab
        }
        #endif
    }
}

/// 自绘底栏。
///
/// 不用系统 `TabView` 的 `tabItem`：拿不到「选中项顶部金线滑过去」这个动画，
/// 而那条线是这套设计里导航的唯一视觉指示。
private struct ClassicalTabBar: View {
    let selection: RootView.Tab
    let onSelect: (RootView.Tab) -> Void

    private var selectedIndex: Int {
        RootView.Tab.allCases.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let itemWidth = geometry.size.width / CGFloat(RootView.Tab.allCases.count)
                ZStack(alignment: .topLeading) {
                    Hairline()
                    // 选中项顶部一条 2pt 金线，宽度 = 1/3 容器宽
                    Rectangle()
                        .fill(Theme.Palette.accent)
                        .frame(width: itemWidth, height: 2)
                        .offset(x: itemWidth * CGFloat(selectedIndex))
                        .animation(.easeOut(duration: 0.26), value: selectedIndex)
                }
            }
            .frame(height: 2)

            HStack(spacing: 0) {
                ForEach(RootView.Tab.allCases, id: \.self) { item in
                    Button { onSelect(item) } label: {
                        Text(item.title)
                            .font(.classicalHeading(16))
                            .foregroundStyle(
                                item == selection ? Theme.Palette.accent700 : Theme.Palette.neutral600
                            )
                            .frame(maxWidth: .infinity)
                            // 底栏总高 74pt，含 14pt 安全区留白
                            .padding(.vertical, 16)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Theme.Palette.bg)
    }
}
