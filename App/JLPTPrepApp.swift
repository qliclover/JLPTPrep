import SwiftUI
import SwiftData
import JLPTContent

@main
struct JLPTPrepApp: App {
    private let container: ModelContainer

    init() {
        SettingKey.registerDefaults()
        Theme.Fonts.register()
        #if DEBUG
        ColorIsolationProbe.runIfRequested()
        Speaker.runProbeIfRequested()
        #endif
        do {
            container = try JLPTStore.container()
        } catch {
            // 数据库建不起来就没有任何可做的事了，早崩早发现。
            fatalError("无法创建数据库：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

/// 用户可调的学习参数。放 UserDefaults 而不是数据库 —— 它们是设备偏好，
/// 将来上 iCloud 同步时也不该跟着走。
///
/// 这里只登记键名和默认值；视图里用 `@AppStorage(SettingKey.x, ...)` 订阅，
/// 静态的 `@AppStorage` 不会触发视图刷新，别在这儿存值。
enum SettingKey {
    static let newCardsPerDay = "newCardsPerDay"
    static let maxReviewsPerDay = "maxReviewsPerDay"
    static let showFurigana = "showFurigana"
    static let readerFontSize = "readerFontSize"
    static let didSeedSampleBook = "didSeedSampleBook"
    /// 备考目标等级。决定队列、统计、出题干扰项的范围（累积：考 N4 含 N5）。
    static let targetLevel = "targetLevel"
    /// 阅读器默认竖排。
    static let readerVertical = "readerVertical"
    /// 复习方式：翻卡自评 flip / 选择题 quiz。
    static let reviewMode = "reviewMode"
    /// 每日提醒开关。默认关 —— 通知权限得由用户主动开口要。
    static let remindersOn = "remindersOn"
    /// 提醒时刻。默认 20:00：晚饭后、睡前，两头都不挤。
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            newCardsPerDay: 15,
            maxReviewsPerDay: 200,
            showFurigana: true,
            targetLevel: "N4",
            readerVertical: false,
            reviewMode: "flip",
            readerFontSize: 19.0,
            remindersOn: false,
            reminderHour: 20,
            reminderMinute: 0,
        ])
    }
}
