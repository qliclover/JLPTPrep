// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JLPTCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JLPTCore", targets: ["JLPTCore"]),
        .library(name: "JLPTContent", targets: ["JLPTContent"]),
        .library(name: "JLPTJapanese", targets: ["JLPTJapanese"]),
    ],
    targets: [
        // 纯逻辑：SRS 调度、队列、计分。不依赖任何 Apple 框架。
        .target(name: "JLPTCore"),
        // 日语文本处理：分词、运行时振假名。给阅读器用，内容包不需要它。
        .target(name: "JLPTJapanese", dependencies: ["JLPTCore"]),
        // 持久化与内容导入：SwiftData 实体、种子包解析、内容更新管线。
        .target(name: "JLPTContent", dependencies: ["JLPTCore", "JLPTJapanese"]),
        .testTarget(name: "JLPTCoreTests", dependencies: ["JLPTCore"]),
        .testTarget(
            name: "JLPTContentTests",
            dependencies: ["JLPTContent"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "JLPTJapaneseTests",
            dependencies: ["JLPTJapanese", "JLPTContent"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
