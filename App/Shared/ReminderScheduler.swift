import Foundation
import SwiftData
import UserNotifications
import JLPTCore
import JLPTContent

/// 每日复习提醒。
///
/// 间隔重复系统算出「这张卡明天该复习」，却没有任何机制告诉你 —— 你得自己记得
/// 打开 App，而记性正是这套系统要替你管的东西。这是提醒存在的全部理由。
///
/// 两个设计决定：
///
/// - **通知里写具体数字**（「明天 23 张 · 约 4 分钟」），不写「该复习了」。
///   空口号会被划掉，具体数字不会 —— 因为它告诉你代价有多小。
/// - **提前排好未来 7 天**，每天一条，内容各不相同。iOS 的日历触发器只能重复
///   同一份内容，做不到「每天数字不一样」；所以改成一次排 7 条独立通知，
///   每次打开 App 重排一遍。7 天足够覆盖一次正常的使用间隔。
@MainActor
enum ReminderScheduler {

    /// 通知标识前缀。重排时按它清掉旧的，不碰别人的通知。
    private static let prefix = "jlpt.daily."
    /// 一次排多少天。
    private static let horizon = 7

    // MARK: - 授权

    /// 请求通知权限。用户拒绝过就不再打扰，直接返回当前状态。
    @discardableResult
    static func requestAuthorization() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return settings.authorizationStatus
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await center.notificationSettings().authorizationStatus
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - 排程

    /// 按当前队列重排未来几天的提醒。
    ///
    /// - Parameters:
    ///   - hour/minute: 用户选的提醒时刻。
    ///   - enabled: 关掉时只清不排。
    ///
    /// 每次打开 App、每次学完、每次改设置都应该调一次 —— 数字会变。
    static func reschedule(
        enabled: Bool,
        hour: Int,
        minute: Int,
        in context: ModelContext,
        session: ReviewSession,
        levels: Set<JLPTLevel>?,
        packIDs: Set<String>?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let center = UNUserNotificationCenter.current()
        await clearPending(center)
        guard enabled else { return }

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let loads: [ReviewSession.DayLoad]
        do {
            loads = try session.forecast(
                days: horizon, in: context, now: now, levels: levels, packIDs: packIDs
            )
        } catch {
            return
        }

        for item in ReminderPlanner.plan(
            loads: loads, hour: hour, minute: minute, now: now, calendar: calendar
        ) {
            let content = UNMutableNotificationContent()
            content.title = "日本語"
            content.body = item.body
            content.sound = .default
            content.badge = NSNumber(value: item.total)

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: item.fireDate
                ),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "\(prefix)\(item.offset)", content: content, trigger: trigger
            )
            try? await center.add(request)
        }
    }

    private static func clearPending(_ center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    /// 关掉提醒时顺手把角标清掉。
    static func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    #if DEBUG
    /// `-verifyReminders` 启动时把排程计划打出来。
    ///
    /// 模拟器没法用命令行授予通知权限，所以端到端的「真的响了」验不了。
    /// 但真正容易写错的是日期换算和文案，这两样不依赖权限 —— 这个探针只验它们。
    static func runProbeIfRequested(in context: ModelContext) {
        guard CommandLine.arguments.contains("-verifyReminders") else { return }

        let session = ReviewSession(queueConfig: DailyQueueConfig(newCardsPerDay: 15))
        guard let loads = try? session.forecast(days: horizon, in: context) else {
            NSLog("[ReminderProbe] ✗ 预测失败")
            return
        }
        let items = ReminderPlanner.plan(loads: loads, hour: 20, minute: 0, now: Date())

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        NSLog("[ReminderProbe] 预测 %d 天，排出 %d 条通知", loads.count, items.count)
        for item in items {
            NSLog("[ReminderProbe]   %@  %@", formatter.string(from: item.fireDate), item.body)
        }
        let skipped = loads.count - items.count
        if skipped > 0 {
            NSLog("[ReminderProbe]   （跳过 %d 天：没有待办，或时刻已过）", skipped)
        }
    }
    #endif
}
