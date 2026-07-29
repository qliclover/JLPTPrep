#if DEBUG
import Foundation

/// 用启动参数直达某一屏，供生成 App Store 截图用。
///
///     xcrun simctl launch <device> com.qianli.JLPTPrep -screenshot reader
///
/// 为什么不用点坐标驱动模拟器：坐标依赖窗口位置和缩放，机型一换就全废，
/// 而且中间任何一次点空了后面全错位。启动参数是确定性的 —— 同一条命令
/// 永远落在同一屏，截图可以随时重跑。
///
/// 整个文件在 `#if DEBUG` 内，Release 构建里不存在。
enum ScreenshotMode: String {
    /// 首页：今日队列、连续天数、活跃格子
    case home
    /// 复习卡（选择题）
    case study
    /// 书架
    case shelf
    /// 阅读器（横排）
    case reader
    /// 阅读器（竖排）
    case readerVertical
    /// 词包管理
    case packs
    /// 笔记
    case notes
    /// 点词后的详情面板（含朗读入口）
    case wordDetail
    /// 错题本
    case trouble
    /// 备份
    case backup
    /// 真题列表
    case exams
    /// 做真题
    case examRunner

    /// 本次启动指定的屏，没指定就是 nil（正常启动）。
    static let current: ScreenshotMode? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-screenshot"),
              index + 1 < arguments.count
        else { return nil }
        return ScreenshotMode(rawValue: arguments[index + 1])
    }()

    /// 这一屏落在哪个底栏 tab 下。
    var tab: RootView.Tab {
        switch self {
        case .home, .study: .study
        case .shelf, .reader, .readerVertical, .notes, .wordDetail: .shelf
        case .packs, .trouble, .backup, .exams, .examRunner: .settings
        }
    }

    var opensReader: Bool { self == .reader || self == .readerVertical || self == .wordDetail }
}
#endif
