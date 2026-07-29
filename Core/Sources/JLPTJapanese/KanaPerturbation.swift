import Foundation

/// 生成「像但不对」的假名读音，用作选择题的干扰项。
///
/// 随机挑三个别的词当选项，题目就白送分了 —— 学习者一眼就能排除。
/// JLPT 真题的干扰项是有固定套路的，全都围绕日语里最容易混的几组音：
/// 清浊、长短、促音有无、拗音有无。这里就按这些套路造。
public enum KanaPerturbation {

    /// 扰动的种类。按「容易混淆的程度」排序，优先用靠前的。
    public enum Kind: String, CaseIterable, Sendable {
        /// か ↔ が：清音浊音互换，最常考
        case voicing
        /// がっこう ↔ がこう：促音增删
        case gemination
        /// こうこう ↔ ここう：长音增删
        case longVowel
        /// きゃ ↔ きや：拗音增删
        case palatalization
        /// たべる → たべら：同辅音换元音
        case vowelShift
    }

    /// 给 `reading` 造出若干个似是而非的读音。
    ///
    /// - Parameter avoiding: 不能与之相同的读音（正确答案、这个词的其他读法、已用过的干扰项）。
    public static func distractors(
        for reading: String,
        count: Int,
        avoiding: Set<String> = []
    ) -> [String] {
        guard !reading.isEmpty, count > 0 else { return [] }

        var forbidden = avoiding
        forbidden.insert(reading)

        var results: [String] = []
        // 按扰动种类的优先级依次尝试，同一种类内按位置从后往前 ——
        // 词尾的差异比词首更难察觉，是更好的干扰项。
        for kind in Kind.allCases {
            for candidate in candidates(for: reading, kind: kind) {
                guard results.count < count else { return results }
                guard !forbidden.contains(candidate) else { continue }
                forbidden.insert(candidate)
                results.append(candidate)
            }
        }
        return results
    }

    /// 某一种扰动能产生的全部候选。
    public static func candidates(for reading: String, kind: Kind) -> [String] {
        let characters = Array(reading)
        var results: [String] = []

        switch kind {
        case .voicing:
            for index in characters.indices.reversed() {
                if let flipped = toggleVoicing(characters[index]) {
                    var copy = characters
                    copy[index] = flipped
                    results.append(String(copy))
                }
            }

        case .gemination:
            // 去掉已有的促音
            for index in characters.indices.reversed() where characters[index] == "っ" {
                var copy = characters
                copy.remove(at: index)
                results.append(String(copy))
            }
            // 在能接促音的位置插入。促音只出现在 か/さ/た/ぱ 行之前。
            for index in 1..<max(characters.count, 1) where canFollowGemination(characters[index]) {
                guard characters[index - 1] != "っ" else { continue }
                var copy = characters
                copy.insert("っ", at: index)
                results.append(String(copy))
            }

        case .longVowel:
            // 删掉长音
            for index in characters.indices.reversed() where index > 0 && isLongVowelMark(characters[index], after: characters[index - 1]) {
                var copy = characters
                copy.remove(at: index)
                results.append(String(copy))
            }
            // 加上长音
            for index in characters.indices.reversed() {
                guard let mark = longVowelMark(for: characters[index]) else { continue }
                if index + 1 < characters.count, characters[index + 1] == mark { continue }
                var copy = characters
                copy.insert(mark, at: index + 1)
                results.append(String(copy))
            }

        case .palatalization:
            for index in characters.indices.reversed() where isSmallYa(characters[index]) {
                var copy = characters
                copy[index] = large(characters[index]) ?? characters[index]
                results.append(String(copy))
            }

        case .vowelShift:
            for index in characters.indices.reversed() {
                for shifted in sameConsonantRow(characters[index]) {
                    var copy = characters
                    copy[index] = shifted
                    results.append(String(copy))
                }
            }
        }
        return results
    }

    // MARK: - 字符表

    private static let voicingPairs: [Character: Character] = [
        "か": "が", "き": "ぎ", "く": "ぐ", "け": "げ", "こ": "ご",
        "さ": "ざ", "し": "じ", "す": "ず", "せ": "ぜ", "そ": "ぞ",
        "た": "だ", "ち": "ぢ", "つ": "づ", "て": "で", "と": "ど",
        "は": "ば", "ひ": "び", "ふ": "ぶ", "へ": "べ", "ほ": "ぼ",
    ]

    private static let unvoicingPairs: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (clear, voiced) in voicingPairs { map[voiced] = clear }
        // 半浊音也算「像」：はし / ばし / ぱし 三者极易混
        for (clear, _) in voicingPairs where "はひふへほ".contains(clear) {
            map[semiVoiced(clear)!] = clear
        }
        return map
    }()

    private static func semiVoiced(_ character: Character) -> Character? {
        switch character {
        case "は": "ぱ"
        case "ひ": "ぴ"
        case "ふ": "ぷ"
        case "へ": "ぺ"
        case "ほ": "ぽ"
        default: nil
        }
    }

    static func toggleVoicing(_ character: Character) -> Character? {
        voicingPairs[character] ?? unvoicingPairs[character]
    }

    /// 促音只能出现在这些行的假名之前。
    private static func canFollowGemination(_ character: Character) -> Bool {
        "かきくけこさしすせそたちつてとぱぴぷぺぽ".contains(character)
    }

    /// 这个假名后面跟哪个假名算长音。
    private static func longVowelMark(for character: Character) -> Character? {
        switch vowel(of: character) {
        case 0: "あ"
        case 1: "い"
        case 2: "う"
        case 3: "い"   // え段的长音写作「えい」，如「せんせい」
        case 4: "う"   // お段的长音写作「おう」，如「がっこう」
        default: nil
        }
    }

    private static func isLongVowelMark(_ character: Character, after previous: Character) -> Bool {
        longVowelMark(for: previous) == character
    }

    private static func isSmallYa(_ character: Character) -> Bool {
        "ゃゅょ".contains(character)
    }

    private static func large(_ character: Character) -> Character? {
        switch character {
        case "ゃ": "や"
        case "ゅ": "ゆ"
        case "ょ": "よ"
        default: nil
        }
    }

    // 五十音图，用来做元音替换
    private static let rows: [[Character]] = [
        ["あ", "い", "う", "え", "お"],
        ["か", "き", "く", "け", "こ"],
        ["が", "ぎ", "ぐ", "げ", "ご"],
        ["さ", "し", "す", "せ", "そ"],
        ["ざ", "じ", "ず", "ぜ", "ぞ"],
        ["た", "ち", "つ", "て", "と"],
        ["だ", "ぢ", "づ", "で", "ど"],
        ["な", "に", "ぬ", "ね", "の"],
        ["は", "ひ", "ふ", "へ", "ほ"],
        ["ば", "び", "ぶ", "べ", "ぼ"],
        ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"],
        ["ま", "み", "む", "め", "も"],
        ["ら", "り", "る", "れ", "ろ"],
    ]

    /// 这个假名在五十音图里的元音位置（あ=0…お=4）。
    static func vowel(of character: Character) -> Int? {
        for row in rows {
            if let index = row.firstIndex(of: character) { return index }
        }
        switch character {
        case "や": return 0
        case "ゆ": return 2
        case "よ": return 4
        default: return nil
        }
    }

    /// 同一行里的其他假名（换元音）。
    static func sameConsonantRow(_ character: Character) -> [Character] {
        for row in rows where row.contains(character) {
            return row.filter { $0 != character }
        }
        return []
    }
}
