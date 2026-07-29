import Foundation

/// 假名与汉字的字符判定，以及片假名 ↔ 平假名互转。
public enum Kana {
    /// 平假名区（含浊音、拗音小字）。
    public static func isHiragana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3041...0x309F).contains(Int(scalar.value))
    }

    /// 片假名区（含半角片假名）。
    public static func isKatakana(_ scalar: Unicode.Scalar) -> Bool {
        (0x30A0...0x30FF).contains(Int(scalar.value)) || (0xFF66...0xFF9F).contains(Int(scalar.value))
    }

    public static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        isHiragana(scalar) || isKatakana(scalar)
    }

    /// 需要注音的字：CJK 汉字，外加叠字符「々」和合字「〆」「ヶ」
    /// （「一ヶ月」的ヶ在字形上是片假名，但读作「か」，属于要注音的部分）。
    public static func isKanji(_ scalar: Unicode.Scalar) -> Bool {
        let v = Int(scalar.value)
        switch v {
        case 0x4E00...0x9FFF,   // CJK 统一汉字
             0x3400...0x4DBF,   // 扩展 A
             0xF900...0xFAFF:   // 兼容汉字
            return true
        case 0x3005, 0x3006, 0x30F6:  // 々 〆 ヶ
            return true
        default:
            return false
        }
    }

    public static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isKanji)
    }

    /// 片假名转平假名。注音一律用平假名，所以比对前要先归一化。
    /// 长音符「ー」原样保留 —— 它在平假名文本里也合法（コーヒー → こーひー）。
    public static func toHiragana(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let v = Int(scalar.value)
            // 0x30A1...0x30F6 是与平假名一一对应的区间，差值固定 0x60
            if (0x30A1...0x30F6).contains(v), let converted = Unicode.Scalar(v - 0x60) {
                out.append(converted)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// 把分词器给的罗马字转写变成平假名。
    ///
    /// `CFStringTokenizer` 只肯给罗马字（`kCFStringTokenizerAttributeLatinTranscription`），
    /// 拿不到假名读音，所以必须再过一道 `kCFStringTransformLatinHiragana`。
    /// 这一来一回是这条链路上最容易掉精度的地方 —— 长音的 `ō` 会变成什么、
    /// 促音和拨音怎么还原，都得靠实测，见 KanaTests。
    public static func hiragana(fromLatin latin: String) -> String? {
        let mutable = NSMutableString(string: latin)
        guard CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false) else { return nil }
        let result = mutable as String
        return result.isEmpty ? nil : result
    }
}
