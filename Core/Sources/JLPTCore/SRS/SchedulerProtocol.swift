import Foundation

/// 调度器接口。v1 用 `SM2Scheduler`，将来换 FSRS 只要再实现一次这个协议，
/// 上层（复习流、队列构建、统计）完全不用改。
public protocol SchedulerProtocol: Sendable {
    /// 给一张卡打分后，算出它的新状态。必须是纯函数：不改入参、不读系统时钟。
    func schedule(state: SRSState, rating: Rating, now: Date) -> SRSState
}
