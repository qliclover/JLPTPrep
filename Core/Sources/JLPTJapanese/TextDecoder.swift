import Foundation

/// 猜文本文件的编码并解码。
///
/// 日文文本文件的编码是个真问题：网上流传的旧文件、青空文庫的下载包大量是
/// **Shift_JIS**，也有 EUC-JP 和 ISO-2022-JP。猜错不会报错，只会得到一屏乱码。
public enum TextDecoder {

    public struct DecodedText: Equatable, Sendable {
        public let text: String
        public let encoding: String.Encoding

        public var encodingName: String {
            switch encoding {
            case .utf8: "UTF-8"
            case .shiftJIS: "Shift_JIS"
            case .japaneseEUC: "EUC-JP"
            case .iso2022JP: "ISO-2022-JP"
            case .utf16LittleEndian: "UTF-16LE"
            case .utf16BigEndian: "UTF-16BE"
            default: "未知"
            }
        }
    }

    /// 解码顺序是有讲究的，见各步注释。
    public static func decode(_ data: Data) -> DecodedText? {
        guard !data.isEmpty else { return nil }

        // 1. 有 BOM 就没什么好猜的。
        if let decoded = decodeUsingBOM(data) { return decoded }

        // 2. ISO-2022-JP 是 7-bit 编码，靠转义序列切换字符集，特征极其明显。
        //    必须在 UTF-8 之前判 —— 它的字节全在 ASCII 范围内，会被 UTF-8 成功解码成一堆转义垃圾。
        if containsISO2022Escape(data), let text = String(data: data, encoding: .iso2022JP) {
            return DecodedText(text: text, encoding: .iso2022JP)
        }

        // 3. UTF-8 严格解码。`String(data:encoding:.utf8)` 遇到非法字节序列返回 nil，
        //    而 Shift_JIS / EUC-JP 的日文字节几乎必然含非法 UTF-8 序列，
        //    所以「能按 UTF-8 解出来」本身就是很强的证据。
        if let text = String(data: data, encoding: .utf8) {
            return DecodedText(text: text, encoding: .utf8)
        }

        // 4. 剩下的日文传统编码没有自校验能力，互相都能「解码成功」，只能打分挑最像日语的。
        let candidates: [String.Encoding] = [.shiftJIS, .japaneseEUC, .iso2022JP]
        var best: (DecodedText, Double)?
        for encoding in candidates {
            guard let text = String(data: data, encoding: encoding), !text.isEmpty else { continue }
            let score = japaneseness(of: text)
            if best == nil || score > best!.1 {
                best = (DecodedText(text: text, encoding: encoding), score)
            }
        }
        return best?.0
    }

    // MARK: - BOM

    private static func decodeUsingBOM(_ data: Data) -> DecodedText? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
                .map { DecodedText(text: $0, encoding: .utf8) }
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
                .map { DecodedText(text: $0, encoding: .utf16LittleEndian) }
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
                .map { DecodedText(text: $0, encoding: .utf16BigEndian) }
        }
        return nil
    }

    /// ISO-2022-JP 用 `ESC $ B` / `ESC ( B` 之类的序列切换字符集。
    private static func containsISO2022Escape(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(4096))
        for (index, byte) in bytes.enumerated() where byte == 0x1B {
            guard index + 2 < bytes.count else { break }
            let next = bytes[index + 1]
            if next == 0x24 || next == 0x28 { return true }  // '$' 或 '('
        }
        return false
    }

    // MARK: - 打分

    /// 「这段文本有多像日语」。用错编码解出来的乱码会大量落进「奇怪」那一档。
    static func japaneseness(of text: String) -> Double {
        var good = 0
        var bad = 0
        var total = 0

        for scalar in text.unicodeScalars.prefix(4000) {
            total += 1
            let v = Int(scalar.value)
            switch v {
            case 0x3040...0x30FF,          // 假名
                 0x4E00...0x9FAF,          // 常用汉字
                 0x3000...0x303F,          // 日文标点 、。「」
                 0x20...0x7E,              // ASCII 可见字符
                 0x09, 0x0A, 0x0D,         // 制表、换行
                 0xFF01...0xFF5E:          // 全角 ASCII
                good += 1
            case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F:  // 控制字符：正常文本里不该有
                bad += 2
            case 0xE000...0xF8FF:          // 私用区：乱码重灾区
                bad += 2
            default:
                break
            }
        }
        guard total > 0 else { return 0 }
        return (Double(good) - Double(bad)) / Double(total)
    }
}
