#if DEBUG
import SwiftUI
import UIKit

/// 验证调色板闭包能在**非主线程**上安全求值。
///
/// 背景：真机上 SwiftUI 会在 `com.apple.SwiftUI.AsyncRenderer` 线程解析颜色。
/// 工程开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，`UIColor { traits in ... }`
/// 的闭包默认被推断成主线程专属，于是运行时隔离检查触发 `EXC_BREAKPOINT`，
/// 表现为「点什么都闪退」。模拟器不走那条异步渲染路径，所以复现不出来。
///
/// 这个探针把同样的事在后台线程做一遍：解析失败就崩（和线上一致），
/// 全部通过就打日志。用 `-verifyColorIsolation` 启动触发。
enum ColorIsolationProbe {

    static func runIfRequested() {
        guard CommandLine.arguments.contains("-verifyColorIsolation") else { return }

        // 故意不回主线程 —— 这正是崩溃现场的执行环境
        DispatchQueue.global(qos: .userInitiated).async {
            let traits = [
                UITraitCollection(userInterfaceStyle: .light),
                UITraitCollection(userInterfaceStyle: .dark),
            ]
            let palette: [(String, Color)] = [
                ("bg", Theme.Palette.bg),
                ("surface", Theme.Palette.surface),
                ("text", Theme.Palette.text),
                ("accent", Theme.Palette.accent),
                ("accent100", Theme.Palette.accent100),
                ("accent700", Theme.Palette.accent700),
                ("neutral500", Theme.Palette.neutral500),
                ("neutral600", Theme.Palette.neutral600),
                ("neutral700", Theme.Palette.neutral700),
                ("divider", Theme.divider),
            ]

            var resolved = 0
            for (name, color) in palette {
                for trait in traits {
                    // 这一行会走到 adaptive 里的闭包 —— 未修复时在这里陷阱
                    let ui = UIColor(color).resolvedColor(with: trait)
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                    guard a > 0 else {
                        NSLog("[ColorProbe] ✗ %@ 解析出全透明", name)
                        continue
                    }
                    resolved += 1
                }
            }
            NSLog("[ColorProbe] ✓ 后台线程解析 %d 项全部通过（%d 个颜色 × %d 种外观）",
                  resolved, palette.count, traits.count)
        }
    }
}
#endif
