import Foundation
import SwiftUI
import JLPTContent

/// 全 App 共享的 JMdict 实例。
///
/// 加载一次就够：`JMDictionary` 内部串行化查询，本身线程安全。
/// 词典文件是**可选**的 —— 没打包进去时 `shared` 为 nil，界面退化成
/// 只有词形分析没有释义，而不是崩溃或空白。
enum DictionaryStore {
    static let shared: JMDictionary? = {
        let dictionary = JMDictionary(bundle: .main)
        if dictionary == nil {
            print("[JLPTPrep] 未找到 jmdict.sqlite，释义功能不可用。运行 Tools/build_jmdict.py 生成。")
        }
        return dictionary
    }()

    static var isAvailable: Bool { shared != nil }
}
