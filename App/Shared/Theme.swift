import SwiftUI
import CoreText

/// Classical 设计系统的全部 token。
///
/// 数值全部来自 `design_handoff_jlpt_classical/design-system/styles.css` 的 `:root`。
/// **视图里不要散写 hex 和魔数**，一律走这里 —— 设计要调色调间距时只改一个地方。
enum Theme {

    // MARK: - 颜色
    //
    // 深色值是设计稿在 README 里给的覆盖值（styles.css 没有预置深色）。

    enum Palette {
        static let bg = adaptive(light: 0xF3F2F2, dark: 0x1B1A18)
        static let surface = adaptive(light: 0xEAE9E9, dark: 0x252320)
        static let text = adaptive(light: 0x201F1D, dark: 0xECE9E4)
        /// 金。**只作描边、细线、下划线、小标签，不做大面积填充。**
        /// 深底上要提亮一档到 accent-400，否则压不住。
        static let accent = adaptive(light: 0xB68235, dark: 0xE1AD66)
        /// 所有 1px hairline。
        static let divider = Color(.sRGB, white: 0, opacity: 0)  // 占位，见下方计算属性

        static let neutral100 = adaptive(light: 0xF8F4F4, dark: 0x2D2B2B)
        static let neutral200 = adaptive(light: 0xEAE7E7, dark: 0x3A3835)
        static let neutral300 = adaptive(light: 0xD7D3D3, dark: 0x4A4744)
        static let neutral400 = adaptive(light: 0xBAB6B6, dark: 0x6B6763)
        static let neutral500 = adaptive(light: 0x9B9797, dark: 0x8A8681)
        static let neutral600 = adaptive(light: 0x7D7979, dark: 0xA29D98)
        static let neutral700 = adaptive(light: 0x605D5D, dark: 0xC2BDB7)
        static let neutral800 = adaptive(light: 0x444141, dark: 0xD8D3CD)
        static let neutral900 = adaptive(light: 0x2D2B2B, dark: 0xECE9E4)

        static let accent100 = adaptive(light: 0xFFF3E4, dark: 0x3A2A15)
        static let accent200 = adaptive(light: 0xFFE3BF, dark: 0x4B3719)
        static let accent300 = adaptive(light: 0xFACB8D, dark: 0x6B4E22)
        static let accent400 = adaptive(light: 0xE1AD66, dark: 0x8C6730)
        /// 正文尺寸的金字用它 —— `accent` 本体对比度只有 3:1，够图标和大字，不够正文。
        static let accent700 = adaptive(light: 0x7D5411, dark: 0xE1AD66)
        static let accent800 = adaptive(light: 0x5A3B0A, dark: 0xF0C88E)

        /// 必须是 `nonisolated`。
        ///
        /// 工程开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，写在 MainActor 上下文里的
        /// 闭包会被推断成主线程专属。但这个闭包的调用方是 UIKit —— SwiftUI 在
        /// `com.apple.SwiftUI.AsyncRenderer` 线程上解析颜色时会调它，于是 Swift 运行时
        /// 的隔离检查发现跑错了 actor，直接 `EXC_BREAKPOINT` 打死进程。
        ///
        /// 模拟器上复现不出来 —— 那条异步渲染路径只在真机走。这个 bug 是靠真机崩溃报告
        /// 里的 `dispatch_assert_queue_fail` 才定位到的。
        nonisolated private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
            })
        }
    }

    /// hairline 是文字色的低透明度版本，浅色 16%、深色 18%。
    ///
    /// `nonisolated` 的原因同 `Palette.adaptive`。
    nonisolated static var divider: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: 0xECE9E4).withAlphaComponent(0.18)
                : UIColor(hex: 0x201F1D).withAlphaComponent(0.16)
        })
    }

    // MARK: - 间距
    //
    // 密度 1.15×。设计稿明确要求用变量而不是随手取整。

    enum Space {
        static let s1: CGFloat = 4.6
        static let s2: CGFloat = 9.2
        static let s3: CGFloat = 13.8
        static let s4: CGFloat = 18.4
        static let s6: CGFloat = 27.6
        static let s8: CGFloat = 36.8
        /// 屏幕左右边距统一 space-4。
        static let screen: CGFloat = 18.4
    }

    enum Radius {
        static let sm: CGFloat = 2
        static let md: CGFloat = 4
        /// 只有底部弹层的顶角用它。
        static let lg: CGFloat = 7
    }

    /// hairline 的物理宽度。1px 而不是 1pt —— 设计要的是发丝线。
    static var hairline: CGFloat { 1 / UIScreen.main.scale }

    // MARK: - 字体
    //
    // 拉丁字体随包（OFL 许可），日文用系统的ヒラギノ明朝。
    //
    // 设计稿写的是 Noto Serif JP，这里换成 HiraMinProN：两者都是明朝体，
    // 视觉气质一致，但 Noto Serif JP 每个字重约 7MB，两个字重就是 14MB，
    // 而ヒラギノ明朝是 iOS 自带的日文衬线标准字体，质量更好且零体积。

    enum Fonts {
        static let heading = "CormorantGaramond-SemiBold"
        static let headingRegular = "CormorantGaramond-Regular"
        static let body = "Lora-Regular"
        static let bodySemibold = "Lora-SemiBold"
        static let japanese = "HiraMinProN-W3"
        static let japaneseMedium = "HiraMinProN-W6"

        /// 把字体切换成等宽等高数字（lining + tabular figures）。
        ///
        /// `.monospacedDigit()` 对系统字体有效，但对这种默认走旧式数字的衬线字体不够 ——
        /// 它只管等宽，管不了字形选的是 oldstyle 还是 lining。这里直接开 OpenType 特性。
        static func tabularLining(name: String, size: CGFloat) -> UIFont {
            let descriptor = UIFontDescriptor(name: name, size: size).addingAttributes([
                .featureSettings: [
                    [
                        UIFontDescriptor.FeatureKey.type: kNumberCaseType,
                        UIFontDescriptor.FeatureKey.selector: kUpperCaseNumbersSelector,
                    ],
                    [
                        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                    ],
                ],
            ])
            return UIFont(descriptor: descriptor, size: size)
        }

        /// App 启动时注册随包字体。用 CoreText 运行时注册而不是 Info.plist 的
        /// `UIAppFonts` —— 工程用的是 `GENERATE_INFOPLIST_FILE`，没有实体 plist 可写。
        static func register() {
            for name in ["CormorantGaramond", "Lora"] {
                guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                    print("[Theme] 找不到字体 \(name).ttf")
                    continue
                }
                var error: Unmanaged<CFError>?
                if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                    print("[Theme] 注册 \(name) 失败: \(error?.takeRetainedValue().localizedDescription ?? "")")
                }
            }
        }
    }
}

// MARK: - 字体便捷构造

extension Font {
    /// Cormorant Garamond。页面标题、大数字、Tab 文字、统计数字。
    /// 设计规则：**越大越轻** —— 展示级数字用 regular，界面标题上限是 semibold。
    ///
    /// - Parameter liningFigures: 需要显示数字时必须开。Cormorant 默认是**旧式数字**
    ///   （oldstyle：`1` 长得像小写 I，`0` 只有 x-height），排在正文里好看，
    ///   但设计要的是等宽等高的 tabular lining —— 计数和间隔预览不能跳动。
    static func classicalHeading(
        _ size: CGFloat,
        weight: Font.Weight = .semibold,
        liningFigures: Bool = false
    ) -> Font {
        // 可变字重字体在 iOS 上按具体实例名取用；取不到时退回系统衬线，
        // 保证排版不会因为字体缺失而整个垮掉。
        let name = weight == .semibold ? Theme.Fonts.heading : Theme.Fonts.headingRegular
        guard UIFont(name: name, size: size) != nil else {
            return .system(size: size, weight: weight, design: .serif)
        }
        guard liningFigures else { return .custom(name, size: size) }
        return Font(Theme.Fonts.tabularLining(name: name, size: size))
    }

    /// Lora。中文正文、说明文字、按钮文字。
    static func classicalBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight == .semibold ? Theme.Fonts.bodySemibold : Theme.Fonts.body
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    /// ヒラギノ明朝。所有日文：词条、例句、书名、正文。
    static func japanese(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight == .regular ? Theme.Fonts.japanese : Theme.Fonts.japaneseMedium
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - 组件

extension View {
    /// `.card` —— 透明底 + 1px hairline 边框 + radius-md + space-4 内边距。
    /// 设计明确要求**不填色**。
    func classicalCard(padding: CGFloat = Theme.Space.s4) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.divider, lineWidth: Theme.hairline)
            )
    }
}

/// kicker —— 小号大写标签，字距 .1em。
struct Kicker: View {
    let text: String
    var color: Color = Theme.Palette.accent
    var size: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.classicalBody(size))
            .tracking(size * 0.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// 1px 发丝线。
struct Hairline: View {
    var color: Color = Theme.divider
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: Theme.hairline)
    }
}

/// 进度线 —— 1px hairline 底线 + 上面一条 3pt 实色。
/// 设计明确：**不用圆头胶囊进度条**。
struct ClassicalProgress: View {
    let value: Double          // 0...1
    var tint: Color = Theme.Palette.accent
    var thickness: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: Theme.hairline)
                    .frame(maxHeight: .infinity, alignment: .center)
                Rectangle()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(value, 0), 1), height: thickness)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: thickness)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

/// 标签。三种变体对应设计里的 tag-accent / tag-neutral / tag-outline。
struct ClassicalTag: View {
    enum Style { case accent, neutral, outline }
    let text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .font(.classicalBody(11))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                        style == .outline ? Theme.Palette.accent : .clear,
                        lineWidth: Theme.hairline
                    )
            )
    }

    private var foreground: Color {
        switch style {
        case .accent: Theme.Palette.accent800
        case .neutral: Theme.Palette.neutral800
        case .outline: Theme.Palette.accent
        }
    }

    private var background: Color {
        switch style {
        case .accent: Theme.Palette.accent100
        case .neutral: Theme.Palette.neutral100
        case .outline: .clear
        }
    }
}

/// 按钮。primary = 金描边 + 透明底 + 金字；secondary = hairline 描边 + 文字色。
/// 设计明确：**描边不填色**。
struct ClassicalButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, emphasis }
    var kind: Kind = .primary
    var size: CGFloat = 15
    var verticalPadding: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.classicalBody(size))
            .foregroundStyle(kind == .secondary ? Theme.Palette.text : Theme.Palette.accent700)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, Theme.Space.s3)
            .background(fill(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(
                        kind == .secondary ? Theme.divider : Theme.Palette.accent,
                        lineWidth: Theme.hairline
                    )
            )
            .contentShape(.rect)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private func fill(pressed: Bool) -> Color {
        // 「记得」这一个键例外：底为最淡的金，以示默认动作。
        let base: Color = kind == .emphasis ? Theme.Palette.accent100 : .clear
        return pressed ? Theme.Palette.accent.opacity(0.22) : base
    }
}

private extension UIColor {
    /// `nonisolated`：调用方是 `Theme.Palette.adaptive` 里那个跑在渲染线程上的闭包。
    nonisolated convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
