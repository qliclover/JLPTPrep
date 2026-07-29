import Foundation
import PDFKit
import Vision
import AppKit

/// 把一场 JLPT 真题解析成结构化题库。
///
/// **处理单位是文件夹，不是文件。** 目录结构本身带着元数据：
///
///     N4历年真题合集/2021年12月N4/
///       ├── 2021年12月N4真题.pdf     题目
///       ├── 2021年12月N4答案.pdf     答案 —— 常常是独立的一份
///       └── 2021年12月N4音频.mp3     听力
///
/// 早先按单文件处理时，「解析出 53 道题却 0 个答案」的卷子全是这个原因：
/// 答案压根不在那个 PDF 里。有一年的答案甚至是张 JPG。
///
/// 走 OCR 而不抽文字层，是因为这批 PDF 里带文字层的那些抽出来也是乱码 ——
/// 内嵌子集化字体缺 ToUnicode 表，PDFKit 只能按字形编号猜。
///
/// 用法：ParseExam <年份文件夹> [输出目录]

// MARK: - OCR

struct Block {
    let text: String
    let x: Double
    let y: Double
    let confidence: Float
}

let renderScale: CGFloat = 3

func ocr(cgImage: CGImage) -> [Block] {
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["ja-JP", "zh-Hans"]
    request.recognitionLevel = .accurate
    // 关掉语言纠正：它会把假名「改」成更常见的词，而选项之间的区别
    // 恰恰是长短音、清浊这一两个字符 —— 纠正等于毁掉题目。
    request.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
    return (request.results ?? []).compactMap { obs in
        guard let c = obs.topCandidates(1).first else { return nil }
        return Block(text: c.string, x: obs.boundingBox.minX,
                     y: 1 - obs.boundingBox.maxY, confidence: c.confidence)
    }
}

func render(_ page: PDFPage) -> CGImage? {
    let bounds = page.bounds(for: .mediaBox)
    let size = CGSize(width: bounds.width * renderScale, height: bounds.height * renderScale)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.scaleBy(x: renderScale, y: renderScale)
        page.draw(with: .mediaBox, to: ctx)
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.cgImage
}

/// 把一份文件（PDF 或图片）OCR 成逐页的文字块。
func pages(of url: URL) -> [[Block]] {
    let ext = url.pathExtension.lowercased()
    if ["jpg", "jpeg", "png", "heic"].contains(ext) {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return [] }
        return [ocr(cgImage: cg)]
    }
    guard let doc = PDFDocument(url: url) else { return [] }
    return (0..<doc.pageCount).compactMap { i in
        guard let page = doc.page(at: i), let cg = render(page) else { return nil }
        return ocr(cgImage: cg)
    }
}

/// 按行归组、行内按 x 排序。行高容差 0.010：同行四个选项 y 差最多 0.003，
/// 相邻行间距约 0.023。
func rows(from blocks: [Block]) -> [[Block]] {
    var result: [[Block]] = []
    for block in blocks.sorted(by: { $0.y < $1.y }) {
        if var last = result.last, let anchor = last.first, abs(block.y - anchor.y) < 0.010 {
            last.append(block)
            result[result.count - 1] = last.sorted { $0.x < $1.x }
        } else {
            result.append([block])
        }
    }
    return result
}

// MARK: - 正则

func regex(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
let questionHead = regex(#"^\s*[（(]\s*([0-9０-９]{1,2})\s*[）)]\s*(.*)$"#)
let optionHead   = regex(#"^\s*([1-4１-４])\s*[.．、,，]\s*(.*)$"#)
let sectionHead  = regex(#"^\s*(?:もんだい|問題|問\s*題)\s*([0-9０-９]{1,2})"#)

/// 从「もんだい3」「問題12」里取大题号。
///
/// OCR 常把大题头和紧跟的题号粘在一起 ——「もんだい3」+「21」→「もんだい321」。
/// 所以两位数解析出来大于 12 时退回只取一位。JLPT 一个科目最多 6 个大题，
/// 12 这个上限已经很宽松了。
func sectionNumber(_ text: String) -> Int? {
    guard let g = match(sectionHead, text), let n = toInt(g[0]) else { return nil }
    if n <= 12 { return n }
    guard let first = g[0].first, let single = toInt(String(first)), single <= 12 else { return nil }
    return single
}
let bareAnswer   = regex(#"^\s*([1-4])\s*$"#)
/// 听力题的题号是「1ばん」「12ばん」，不是「（1）」——
/// 早先只认括号形式，整个聴解 科目 28 道题一道都没收进来。
let banHead = regex(#"^\s*([0-9０-９]{1,2})\s*ばん"#)
/// 官方原版的编号：题号和选项都是**裸数字**，没有括号也没有点。
///
///     26 わたしはやまださんをかいものにさそいました。
///     1 わたしはやまださんに「…」と言いました。
///
/// 中文引进版重排成了「（26）」和「1.」，所以两种都得认。
/// 裸数字本身没有任何标点特征，只能靠状态来分辨是题号还是选项 ——
/// 见 `parseQuestions` 里的说明。
let bareLead = regex(#"^\s*([0-9０-９]{1,2})\s*(\S.*)?$"#)

func match(_ re: NSRegularExpression, _ s: String) -> [String]? {
    guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    return (1..<m.numberOfRanges).map { i in
        Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
    }
}

func toInt(_ s: String) -> Int? {
    Int(String(s.map { ch in
        guard let v = ch.unicodeScalars.first?.value, (0xFF10...0xFF19).contains(v) else { return ch }
        return Character(UnicodeScalar(v - 0xFF10 + 0x30)!)
    }))
}

/// 把挤在一个文字块里的多个选项切开。
///
/// 短选项（读音、单词）排在同一行时，Vision 会把整行当成一个识别结果返回：
///
///     "つづんで2 すずんで 3 つつんで 4 すすんで"
///
/// 于是只认出第一个，剩下三个连同答案一起丢掉 —— 实测一份卷子里
/// 42 道题栽在这上面。所以拿到选项正文后要再扫一遍，看里面有没有
/// 后续的选项号。
///
/// 判定条件严格：数字必须是 2/3/4 且**按序出现**，后面不能紧跟另一个数字
/// （否则「10分」「2015年」这类正文里的数字会被误切）。
func splitInlineOptions(_ body: String, startingAt first: Int) -> [String] {
    var parts: [String] = []
    var current = ""
    var expected = first + 1
    var index = body.startIndex

    while index < body.endIndex {
        let ch = body[index]
        let next = body.index(after: index)
        if let digit = ch.wholeNumberValue, digit == expected, expected <= 4 {
            // 后面紧跟数字的话这是个多位数，不是选项号
            let followedByDigit = next < body.endIndex && body[next].isNumber
            if !followedByDigit {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                expected += 1
                index = next
                continue
            }
        }
        current.append(ch)
        index = next
    }
    parts.append(current.trimmingCharacters(in: .whitespaces))
    return parts.filter { !$0.isEmpty }
}

// MARK: - 模型

/// 科目。JLPT 一场考试分几个科目，**每个科目的题号各自从 1 开始** ——
/// 所以一道题必须靠「科目 + 大题 + 题号」三元组才能唯一标识。
/// 早先只用题号，导致一份卷子里三道「第 1 题」共用同一个答案。
enum Subject: String, Codable {
    case vocabulary = "文字・語彙"
    case grammar = "文法・読解"
    case listening = "聴解"
    case unknown = "未分类"
}

struct Question: Codable {
    var subject: Subject
    var section: Int
    var number: Int
    var stem: String
    var options: [String]
    var answer: Int?
    var warnings: [String]
    /// 一道题的唯一标识。
    ///
    /// **只用「科目 + 题号」，不含大题号。** JLPT 的题号在一个科目内是连续的
    /// （文字・語彙 从 1 排到 35，横跨所有大题），所以大题号对身份没有贡献；
    /// 而它恰恰是 OCR 里最不可靠的信号 —— 会被页码、解析里的引用、
    /// 甚至粘连的题号污染。把它从标识里去掉，答案配对就不再受它拖累。
    var id: String { "\(subject.rawValue)-\(number)" }
}

struct Exam: Codable {
    var level: String
    var session: String
    var sourceFiles: [String]
    var hasAudio: Bool
    /// 可信集：四个选项齐全、配上了答案、没有任何警告。
    ///
    /// 只有这一批能进 App。存疑的放在 `rejected` 里备查，但不参与做题 ——
    /// 一道答案错了的练习题比没有这道题有害：你做对了却被判错，
    /// 学到的是错的东西。
    var questions: [Question]
    /// 被筛掉的，连同筛掉的原因。
    var rejected: [Question]
    /// 答案页里读到的原始序列，按出现次序。
    ///
    /// 即使自动对齐失败也照样输出 —— 这是人工核对时唯一能用的原始材料。
    /// 丢掉它等于让人重新去翻 PDF。
    var rawAnswers: [RawAnswer]
    var issues: [String]
}

struct RawAnswer: Codable {
    var number: Int
    var answer: Int
}

// MARK: - 文件归类

func role(of name: String) -> String {
    if name.contains("答题卡") || name.contains("答題卡") { return "skip" }
    if name.contains("答案") || name.contains("解析") { return "answers" }
    if name.contains("原文") { return "transcript" }
    return "questions"
}

// MARK: - 题目解析

func parseQuestions(_ files: [URL]) -> ([Question], [String]) {
    var questions: [Question] = []
    var issues: [String] = []
    // 卷子总是从文字・語彙 开始
    var subject: Subject = .vocabulary
    var section = 0
    var pending: Question?

    func flush() {
        guard var q = pending else { return }
        if q.options.count != 4 { q.warnings.append("只解析到 \(q.options.count) 个选项") }
        if q.stem.isEmpty && q.subject != .listening { q.warnings.append("题干为空") }
        for i in q.options.indices {
            for j in (i + 1)..<q.options.count
            where !q.options[i].isEmpty && q.options[i] == q.options[j] {
                q.warnings.append("第 \(i + 1) 项和第 \(j + 1) 项相同，必是识别错误")
            }
        }
        if q.options.contains(where: { $0.contains("じや") || $0.contains("つて") || $0.contains("しよ") }) {
            q.warnings.append("疑似小写假名误识别，需核对")
        }
        // 四个选项长度悬殊 = 它们来自不同的题。
        //
        // 真题里同一道题的四个选项形式总是齐整的：要么都是读音（三五个假名），
        // 要么都是整句。混着出现只可能是解析时把别的题的选项收了进来。
        // 实测这一条能揪出「选项串题」——那是可信集里唯一漏网的错误类型。
        let lengths = q.options.filter { !$0.isEmpty }.map(\.count)
        if let shortest = lengths.min(), let longest = lengths.max(),
           shortest > 0, longest >= shortest * 3, longest - shortest >= 6 {
            q.warnings.append("选项长度悬殊（\(shortest)–\(longest) 字），疑似串了别题的选项")
        }
        questions.append(q)
        pending = nil
    }

    for url in files {
        for page in pages(of: url) {
            let grid = rows(from: page)
            let head = grid.prefix(3).flatMap { $0 }.map(\.text).joined()
            // 一旦翻到答案／解析／原文，题目就结束了
            if head.contains("答案") || head.contains("解析") || head.contains("原文") { break }
            // 聴解 是唯一能靠页眉可靠识别的科目 —— 它单独起一页。
            // 文字語彙 和 文法読解 的页眉是「言語知識（文字・語彙・文法）・読解」，
            // 一行里同时含「文字」和「文法」，根本区分不了。那两个科目靠
            // 「大题号回到 1」来分界，见下面。
            // 必须是**整行只有「聴解」**才算科目标题。
            // 封面的考试结构表里也写着「聴解」，早先只判 contains，
            // 结果整份卷子从第 2 页起就被标成听力了。
            let firstLine = (grid.first ?? []).map(\.text).joined().trimmingCharacters(in: .whitespaces)
            if firstLine.count <= 6, firstLine.contains("聴解"), subject != .listening {
                flush(); subject = .listening; section = 0
            }

            for (rowIndex, row) in grid.enumerated() {
                // 一行里出现几个「裸数字开头」的块。
                //
                // 短选项题的四个选项挤在同一行（「1 りょうかん 2 りょうがん」+
                // 「3りよかん」+「4 りょがん」），而题干独占一行。这个计数是
                // 区分「题号」和「选项号」的关键 —— 两者在裸数字格式下
                // 长得一模一样，正则和位置都分不开。
                func leadingNumbers(_ r: [Block]) -> Int {
                    r.count { b in
                        guard let g = match(bareLead, b.text.trimmingCharacters(in: .whitespaces)),
                              let n = toInt(g[0]) else { return false }
                        return (1...4).contains(n)
                    }
                }
                let numbersHere = leadingNumbers(row)
                let nextRowIsOptions = rowIndex + 1 < grid.count && leadingNumbers(grid[rowIndex + 1]) >= 2

                for block in row {
                    let text = block.text.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { continue }

                    // 大题头。三重约束才认：必须在左边距、编号在 1...12、
                    // 且必须比当前大题大。不加约束的话页码和解析里引用的
                    // 「問題3」都会被当成大题 —— 实测能凭空造出 42 个大题。
                    if block.x < 0.30, let n = sectionNumber(text) {
                        // 大题号回到 1 = 换科目了。JLPT 每个科目的大题和题号
                        // 都各自从 1 开始，这个重置比任何页眉文字都可靠。
                        if n == 1, section > 1, subject != .listening {
                            flush()
                            subject = subject == .vocabulary ? .grammar : .listening
                            section = 1
                            break
                        }
                        guard n > section else { continue }
                        flush()
                        section = n
                        break
                    }

                    // 选项。以 OCR 的序号为准 —— 短选项排四列、长选项竖着堆，
                    // 拿列位置定序号会把后者的四个选项覆盖成一个。
                    if pending != nil, let g = match(optionHead, text),
                       let number = toInt(g[0]), (1...4).contains(number) {
                        let index = number - 1
                        let pieces = splitInlineOptions(g[1].trimmingCharacters(in: .whitespaces),
                                                        startingAt: number)
                        for (offset, piece) in pieces.enumerated() {
                            let slot = index + offset
                            guard slot < 4 else { break }
                            while pending!.options.count <= slot { pending!.options.append("") }
                            if !pending!.options[slot].isEmpty {
                                pending!.warnings.append("第 \(slot + 1) 项出现了两次")
                            }
                            pending!.options[slot] = piece
                        }
                        continue
                    }

                    if let g = match(questionHead, text), let n = toInt(g[0]), section > 0 {
                        flush()
                        pending = Question(
                            subject: subject, section: section, number: n,
                            stem: g[1].trimmingCharacters(in: .whitespaces),
                            options: [], answer: nil, warnings: []
                        )
                        continue
                    }

                    // 裸数字编号（官方原版格式）。
                    //
                    // 题号和选项都在同一个左边距上，位置区分不了。唯一可靠的
                    // 特征是**顺序**：选项永远按 1、2、3、4 依次出现，题号单调递增。
                    // 所以「下一个该来的选项号」优先于「可能的新题号」。
                    if block.x < 0.22, let g = match(bareLead, text), let n = toInt(g[0]),
                       match(questionHead, text) == nil {
                        let body = g.count > 1 ? g[1].trimmingCharacters(in: .whitespaces) : ""
                        // 正在收选项，且这个数字正好是下一个该来的
                        //
                        // 这里有个已知的失败：裸数字格式下题号和选项号无法区分，
                        // 所以下一题的题干会被吞成上一题的选项。试过用「本行编号个数」
                        // 和「下一行是否成排选项」来判别，实测反而更差（19 → 17）——
                        // 长句选项题一行一个编号，那条规则会把它们全判成题干。
                        if var q = pending, q.options.count < 4,
                           n == q.options.count + 1, !body.isEmpty {
                            for piece in splitInlineOptions(body, startingAt: n) where q.options.count < 4 {
                                q.options.append(piece)
                            }
                            pending = q
                            continue
                        }
                        // 否则看是不是新题号：必须比当前题号大，且在合理范围内
                        if n > (pending?.number ?? 0), n <= 45, section > 0 {
                            flush()
                            pending = Question(subject: subject, section: section, number: n,
                                               stem: body, options: [], answer: nil, warnings: [])
                            continue
                        }
                    }

                    // 听力题：「1ばん」。题干在音频里，纸面上只有选项，
                    // 所以 stem 留空是正常的，不算缺陷。
                    if subject == .listening, let g = match(banHead, text), let n = toInt(g[0]) {
                        flush()
                        pending = Question(
                            subject: .listening, section: max(section, 1), number: n,
                            stem: "", options: [], answer: nil, warnings: []
                        )
                        continue
                    }

                    if block.confidence < 0.3 { continue }
                    if pending != nil, pending!.options.isEmpty, block.x < 0.25 {
                        pending!.stem += text
                    }
                }
            }
        }
    }
    flush()
    if section == 0 { issues.append("一个大题头都没识别到，这份的版式可能不受支持") }
    return (questions, issues)
}

// MARK: - 答案解析

/// 答案页是网格：一行题号「（1）（2）（3）」，紧邻的下一行是对应数字，靠 x 对齐。
/// 页上按「問題1 / 問題2」分块，所以要连科目和大题一起记下来 ——
/// 只按题号存的话，一份卷子里三道「第 1 题」会共用同一个答案。
/// 答案页是网格：一行题号「（1）（2）（3）」，紧邻的下一行是对应数字，靠 x 对齐。
///
/// **按出现次序返回，不带科目标签。** 因为答案页的页眉是
/// 「参考答案 言語知識（文字・語彙・文法）・読解・聴解」—— 一行里同时含三个科目名，
/// 靠文字判断科目必然出错（实测会把整份答案都归到听力）。
///
/// 而答案页的排列顺序和试卷完全一致，所以按次序对齐比按标签匹配可靠得多，
/// 还自带校验：数量对不上就说明有一边解析漏了。
func parseAnswers(_ files: [URL]) -> [(number: Int, answer: Int)] {
    var result: [(number: Int, answer: Int)] = []
    for url in files {
        for page in pages(of: url) {
            let grid = rows(from: page)
            for (i, row) in grid.enumerated() {
                let labels = row.compactMap { b -> (Int, Double)? in
                    guard let g = match(questionHead, b.text.trimmingCharacters(in: .whitespaces)),
                          let n = toInt(g[0]) else { return nil }
                    return (n, b.x)
                }
                guard labels.count >= 2, i + 1 < grid.count else { continue }
                let values = grid[i + 1].compactMap { b -> (Int, Double)? in
                    guard let g = match(bareAnswer, b.text.trimmingCharacters(in: .whitespaces)),
                          let v = Int(g[0]) else { return nil }
                    return (v, b.x)
                }
                for (number, lx) in labels.sorted(by: { $0.1 < $1.1 }) {
                    guard let best = values.min(by: { abs($0.1 - lx) < abs($1.1 - lx) }),
                          abs(best.1 - lx) < 0.04 else { continue }
                    result.append((number, best.0))
                }
            }
        }
    }
    return result
}

/// 从纯文本答案文件里读答案。
///
/// 有些年份的答案是 .txt，格式干净，完全不用 OCR：
///
///     文字词汇
///     问题一23424/3411
///     问题二3/12432
///     文法
///     12331/22314/34134
///
/// 数字就是答案，按题号顺序排；`/` 是原文的折行标记，无意义。
/// 科目名单独成行（那一行不含数字）。这种来源比 OCR 答案页可靠一个量级。
func parseTextAnswers(_ url: URL) -> [(number: Int, answer: Int)] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    // 这批文件多是 GBK 系编码
    let text = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: String.Encoding(rawValue:
            CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
        ?? ""
    guard !text.isEmpty else { return [] }

    var result: [(number: Int, answer: Int)] = []
    var counter = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        // 不含数字的行是科目名，题号从头开始
        if !trimmed.contains(where: \.isNumber) { counter = 0; continue }
        // 去掉「问题一」这样的前缀，剩下的每个 1-4 都是一个答案
        let body = trimmed.replacingOccurrences(
            of: #"^问题[一二三四五六七八九十]"#, with: "", options: .regularExpression
        )
        for ch in body where ("1"..."4").contains(String(ch)) {
            counter += 1
            result.append((counter, ch.wholeNumberValue ?? 1))
        }
    }
    return result
}

// MARK: - 主流程

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("用法：ParseExam <年份文件夹> [输出目录]\n".utf8))
    exit(1)
}
let folder = URL(fileURLWithPath: args[1])
let fm = FileManager.default
let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []

// 等级从路径里取：.../N4历年真题合集/2021年12月N4/
let level = folder.pathComponents.reversed().compactMap { part -> String? in
    for candidate in ["N1", "N2", "N3", "N4", "N5"] where part.contains(candidate) { return candidate }
    return nil
}.first ?? "未知"
let session = folder.lastPathComponent

var questionFiles: [URL] = [], answerFiles: [URL] = [], textAnswerFiles: [URL] = []
var hasAudio = false
for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let ext = url.pathExtension.lowercased()
    if ["mp3", "m4a", "wav"].contains(ext) { hasAudio = true; continue }
    if ext == "txt", role(of: url.deletingPathExtension().lastPathComponent) == "answers" {
        textAnswerFiles.append(url); continue
    }
    guard ["pdf", "jpg", "jpeg", "png"].contains(ext) else { continue }
    switch role(of: url.deletingPathExtension().lastPathComponent) {
    case "questions": questionFiles.append(url)
    case "answers": answerFiles.append(url)
    default: break
    }
}
// 一份文件都没归到题目：多半是「真题+答案」合订本，被名字里的「答案」抢走了
if questionFiles.isEmpty { questionFiles = answerFiles }
// 没有独立答案文件时，答案就在题目那份里
if answerFiles.isEmpty { answerFiles = questionFiles }

FileHandle.standardError.write(
    Data("  \(level) \(session)：题目 \(questionFiles.count) 份 · 答案 \(answerFiles.count) 份\n".utf8)
)

var (questions, issues) = parseQuestions(questionFiles)
// 纯文本答案优先 —— 它不经过 OCR，没有识别误差。
let textAnswers = textAnswerFiles.flatMap(parseTextAnswers)
let answers = textAnswers.isEmpty ? parseAnswers(answerFiles) : textAnswers
if !textAnswers.isEmpty {
    FileHandle.standardError.write(Data("    （用了纯文本答案，\(textAnswers.count) 个）\n".utf8))
}

// 按「题号段 + 题号」对齐。
//
// 两侧都按题号分段（题号回到 1 或变小 = 新科目），段与段对应，段内按题号精确匹配。
//
// **不按顺序对齐**：题目侧总会漏掉几道（OCR 漏行是物理限制），
// 按顺序的话漏一道之后全部错位。按题号则只影响漏掉的那几道。
// 这一条是拿 2010 年那份有确凿 txt 答案的卷子验证出来的。
func segment<T>(_ items: [T], number: (T) -> Int) -> [[T]] {
    var runs: [[T]] = []
    var previous = Int.max
    for item in items {
        let n = number(item)
        if n <= previous { runs.append([]) }
        runs[runs.count - 1].append(item)
        previous = n
    }
    return runs
}

let questionRuns = segment(Array(questions.indices), number: { questions[$0].number })
let answerRuns = segment(answers, number: { $0.number })

// 段数不等时按较少的一侧对齐前几段 —— 后面对不上的那些宁可不给答案。
for (qRun, aRun) in zip(questionRuns, answerRuns) {
    let byNumber = Dictionary(aRun.map { ($0.number, $0.answer) }, uniquingKeysWith: { a, _ in a })
    for index in qRun {
        questions[index].answer = byNumber[questions[index].number]
    }
}
if questionRuns.count != answerRuns.count {
    issues.append("题目 \(questionRuns.count) 段、答案 \(answerRuns.count) 段，只对齐了前 \(min(questionRuns.count, answerRuns.count)) 段")
}

for i in questions.indices where questions[i].answer == nil {
    questions[i].warnings.append("没有答案")
}

// 分流
let trusted = questions.filter { $0.warnings.isEmpty && $0.options.count == 4
                                 && $0.options.allSatisfy { !$0.isEmpty } && $0.answer != nil }
let rejected = questions.filter { q in !trusted.contains { $0.id == q.id && $0.stem == q.stem } }

// 校验：每个大题的题号必须连续。不连续说明漏题或者串了大题 ——
// 这类错误不会让任何单道题看起来有问题，只能靠整体检查发现。
var grouped: [String: [Int]] = [:]
for q in questions { grouped["\(q.subject.rawValue) 大题\(q.section)", default: []].append(q.number) }
for (key, numbers) in grouped.sorted(by: { $0.key < $1.key }) {
    let unique = Set(numbers)
    if unique.count != numbers.count { issues.append("\(key)：题号有重复") }
    if let lo = unique.min(), let hi = unique.max(), hi - lo + 1 != unique.count {
        issues.append("\(key)：题号 \(lo)–\(hi) 不连续，缺 \(hi - lo + 1 - unique.count) 道")
    }
}

let exam = Exam(
    level: level, session: session,
    sourceFiles: (questionFiles + answerFiles).map(\.lastPathComponent),
    hasAudio: hasAudio,
    questions: trusted, rejected: rejected,
    rawAnswers: answers.map { RawAnswer(number: $0.number, answer: $0.answer) },
    issues: issues
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let data = try! encoder.encode(exam)

if args.count > 2 {
    let out = URL(fileURLWithPath: args[2]).appendingPathComponent("\(level)-\(session).json")
    try? data.write(to: out)
} else {
    FileHandle.standardOutput.write(data)
}

FileHandle.standardError.write(Data("""
    → 解析 \(questions.count) 题 · **可信 \(trusted.count)** · 存疑 \(rejected.count)

""".utf8))
