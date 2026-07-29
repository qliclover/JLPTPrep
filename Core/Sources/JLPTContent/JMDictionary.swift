import Foundation
import SQLite3
import JLPTJapanese

/// 词典里的一条。
public struct DictionaryEntry: Equatable, Sendable, Identifiable {
    public var id: Int
    /// 汉字表记。纯假名词为 nil。
    public var kanji: String?
    public var reading: String
    /// JMdict 的原始词性代码（`v1`、`v5k`、`adj-i`…）。
    public var partsOfSpeech: [String]
    /// 英文释义。义项之间用 ` / ` 分隔。
    public var glossesEn: String
    /// JMdict 标记的常用词。查询结果里常用词排前面。
    public var isCommon: Bool

    public var headword: String { kanji ?? reading }

    /// 词性的中文说明。认不出的代码原样保留 —— 显示原始代码也比丢掉信息强。
    public var partOfSpeechLabelsZh: [String] {
        partsOfSpeech.map { JMDictionary.posLabelZh[$0] ?? $0 }
    }

    /// 从词性代码推断词类，用来给活用还原提供依据。
    public var wordClass: WordClass? {
        for code in partsOfSpeech {
            if code == "v1" || code == "v1-s" { return .ichidan }
            if code.hasPrefix("v5") { return .godan }
            if code.hasPrefix("vs") { return .suru }
            if code == "vk" { return .kuru }
            if code == "adj-i" { return .iAdjective }
            if code == "adj-na" { return .naAdjective }
        }
        return nil
    }
}

/// JMdict 查询。
///
/// 词典是**构建期**编译成 SQLite 的（见 `Tools/build_jmdict.py`），运行时只读不写 ——
/// 60MB 的 XML 在手机上解析要好几秒还吃内存，没有理由在运行时做。
///
/// 词典文件是可选的：拿不到就返回 nil，App 退化成只有词形分析没有释义，
/// 而不是启动失败。
public final class JMDictionary: @unchecked Sendable {
    private var handle: OpaquePointer?
    /// SQLite 句柄不是线程安全的，查询都串行化。
    /// 查一次是亚毫秒级，串行完全够用，不值得为它上连接池。
    private let lock = NSLock()

    public init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        handle = db
    }

    /// 从 App bundle 里加载。
    public convenience init?(bundle: Bundle, resource: String = "jmdict", extension ext: String = "sqlite") {
        guard let url = bundle.url(forResource: resource, withExtension: ext) else { return nil }
        self.init(url: url)
    }

    deinit {
        sqlite3_close(handle)
    }

    // MARK: - 查询

    /// 查一个词。表记和读音都能查（`食べる` 和 `たべる` 得到同一条）。
    public func lookup(_ key: String, limit: Int = 8) -> [DictionaryEntry] {
        guard !key.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        SELECT e.id, e.kanji, e.reading, e.pos, e.glosses, e.common
        FROM entry e JOIN lookup l ON e.id = l.entry_id
        WHERE l.key = ?
        ORDER BY e.common DESC, e.id ASC
        LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var results: [DictionaryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let pos = column(statement, 3) ?? ""
            results.append(DictionaryEntry(
                id: Int(sqlite3_column_int64(statement, 0)),
                kanji: column(statement, 1),
                reading: column(statement, 2) ?? "",
                partsOfSpeech: pos.isEmpty ? [] : pos.components(separatedBy: ","),
                glossesEn: column(statement, 4) ?? "",
                isCommon: sqlite3_column_int(statement, 5) == 1
            ))
        }
        return results
    }

    /// 这个词在词典里吗。用来给活用还原消歧 —— 比 `lookup` 便宜，不取整行。
    public func contains(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT 1 FROM lookup WHERE key = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK
        else { return false }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    public var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM entry", -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    // MARK: - 词性代码

    /// JMdict 词性代码 → 中文。只收对 N5/N4 阅读有意义的，其余原样显示代码。
    static let posLabelZh: [String: String] = [
        "n": "名词", "n-adv": "名词·副词", "n-t": "时间名词", "n-suf": "名词后缀", "n-pref": "名词前缀",
        "pn": "代词", "adj-i": "い形容词", "adj-ix": "い形容词（特殊）", "adj-na": "な形容词",
        "adj-no": "の形容词", "adj-pn": "连体词", "adj-t": "たる形容词",
        "adv": "副词", "adv-to": "と副词",
        "v1": "动词·二类", "v1-s": "动词·二类（特殊）",
        "v5u": "动词·一类", "v5k": "动词·一类", "v5g": "动词·一类", "v5s": "动词·一类",
        "v5t": "动词·一类", "v5n": "动词·一类", "v5b": "动词·一类", "v5m": "动词·一类",
        "v5r": "动词·一类", "v5r-i": "动词·一类（特殊）", "v5aru": "动词·一类（特殊）",
        "v5k-s": "动词·一类（行く型）", "v5u-s": "动词·一类（特殊）",
        "vk": "动词·三类（来る）", "vs": "サ变名词", "vs-i": "动词·三类（する）", "vs-s": "动词·三类（する）",
        "vt": "他动词", "vi": "自动词",
        "aux": "助动词", "aux-v": "助动词", "aux-adj": "助形容词",
        "prt": "助词", "conj": "接续词", "int": "感叹词", "exp": "惯用表达",
        "ctr": "量词", "suf": "后缀", "pref": "前缀", "num": "数词",
        "cop": "系动词", "unc": "未分类",
    ]
}

/// SQLite 要求告诉它字符串是否需要复制。Swift 里传进去的 String 是临时的，必须复制。
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
