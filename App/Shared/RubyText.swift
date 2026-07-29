import SwiftUI
import JLPTCore

/// 带振假名的日语文本（只读，不可点）。
/// 背单词卡片的例句用它；阅读器正文用 `TappableRubyText`。
///
/// 用自定义 `Layout` 而不是 `Text` 拼接：注音必须浮在对应汉字的正上方，
/// 这是 `Text` 的 attributed string 做不到的（`.baselineOffset` 只能整体位移）。
struct RubyText: View {
    let annotated: String
    var showFurigana: Bool = true
    var baseSize: CGFloat = 20
    var color: Color = Theme.Palette.text

    private var units: [RubyUnit] {
        FuriganaParser.parse(annotated).flatMap { segment -> [RubyUnit] in
            switch segment {
            case .plain(let text):
                // 拆成单字，日语本来就按字换行，这样布局器能在任意位置折行。
                text.map { RubyUnit(base: String($0), reading: nil) }
            case .ruby(let base, let reading):
                // 汉字词连同它的注音是一个不可分割的单位。
                [RubyUnit(base: base, reading: reading)]
            }
        }
    }

    var body: some View {
        RubyFlowLayout(lineSpacing: baseSize * 0.45) {
            ForEach(Array(units.enumerated()), id: \.offset) { _, unit in
                RubyUnitView(unit: unit, showFurigana: showFurigana, baseSize: baseSize, color: color)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        RubyText(annotated: "{毎朝|まいあさ}コーヒーを{飲|の}みます。")
        RubyText(annotated: "{毎朝|まいあさ}コーヒーを{飲|の}みます。", showFurigana: false)
        RubyText(annotated: "ちょっと{待|ま}ってください。", baseSize: 28)
    }
    .padding()
}
