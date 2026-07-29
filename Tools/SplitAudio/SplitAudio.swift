import Foundation
import AVFoundation
import Speech

/// 把 JLPT 听力录音按题定位，输出每道题的起止时间。
///
/// **不切文件，只算时间点。** App 播放原文件的一个区间就行 —— 切成几十个小文件
/// 既要重新编码，又要多占一份存储（一份 N4 听力 35 MB）。
///
/// 定位用**静音 + 语音识别两个信号**，因为单用哪个都不行：
///
/// - **只用静音**：5 秒阈值下切出 37 段而实际 28 题 —— 大题说明和例题之间
///   也有长停顿，静音分不清「题间」和「段落间」。
/// - **只用识别**：离线识别对整段音频只返回第一个停顿前的片段
///   （实测 60 秒片段只出一句话），扫完四十分钟要两百多次调用。
///
/// 合起来就通了：静音给出候选边界，只在每个边界后识别六秒，
/// 听到「にばん」就确认这是第 2 题。识别次数降到几十次，
/// 而且每次都是短促干净的音频，正是离线识别最擅长的输入。
///
/// 用法：SplitAudio <音频> [输出.json]

// MARK: - 音量包络

/// 20ms 一个分析窗：够短，能分辨语句间的停顿；再短只是徒增计算。
let windowSeconds = 0.02

struct Envelope {
    var rms: [Float]
    var duration: Double
}

func envelope(of url: URL) throws -> Envelope {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let frameCount = AVAudioFrameCount(format.sampleRate * windowSeconds)
    var result: [Float] = []
    while file.framePosition < file.length {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { break }
        try file.read(into: buffer, frameCount: frameCount)
        guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += channel[i] * channel[i] }
        result.append((sum / Float(buffer.frameLength)).squareRoot())
    }
    return Envelope(rms: result, duration: Double(file.length) / format.sampleRate)
}

/// 静音段的结束时刻 —— 那是下一段语音的起点，也就是候选的题目边界。
///
/// 阈值取整段 RMS 的百分位而不是固定值：不同年份的录音电平差很多，
/// 固定阈值在某些文件上会把整段判成静音。
func silenceEnds(in envelope: Envelope, minLength: Double = 1.2) -> [Double] {
    let sorted = envelope.rms.sorted()
    guard !sorted.isEmpty else { return [] }
    let threshold = max(sorted[Int(Double(sorted.count) * 0.10)] * 1.5, 1e-5)

    var result: [Double] = []
    var runStart: Int?
    for (index, value) in envelope.rms.enumerated() {
        if value <= threshold {
            if runStart == nil { runStart = index }
        } else if let start = runStart {
            if Double(index - start) * windowSeconds >= minLength {
                result.append(Double(index) * windowSeconds)
            }
            runStart = nil
        }
    }
    return result
}

// MARK: - 题号识别

/// 日语数词到数字。录音里念的是读音，不是阿拉伯数字。
/// 长的排前面 —— 否则「じゅうに」会被「じゅう」抢先匹配掉。
let numberWords: [(String, Int)] = [
    ("にじゅうはち", 28), ("にじゅうなな", 27), ("にじゅうろく", 26), ("にじゅうご", 25),
    ("にじゅうよん", 24), ("にじゅうさん", 23), ("にじゅうに", 22), ("にじゅういち", 21),
    ("にじゅう", 20), ("じゅうきゅう", 19), ("じゅうはち", 18), ("じゅうなな", 17),
    ("じゅうしち", 17), ("じゅうろく", 16), ("じゅうご", 15), ("じゅうよん", 14),
    ("じゅうし", 14), ("じゅうさん", 13), ("じゅうに", 12), ("じゅういち", 11),
    ("じゅう", 10), ("きゅう", 9), ("はち", 8), ("なな", 7), ("しち", 7),
    ("ろく", 6), ("ご", 5), ("よん", 4), ("さん", 3), ("いち", 1), ("に", 2),
]

/// 从识别结果里找题号播报。识别可能写成汉字「23番」也可能写成假名。
func questionNumber(in text: String) -> Int? {
    guard text.contains("ばん") || text.contains("番") else { return nil }
    if let range = text.range(of: #"([0-9]{1,2})\s*番"#, options: .regularExpression) {
        let digits = text[range].filter(\.isNumber)
        if let n = Int(String(digits)), (1...40).contains(n) { return n }
    }
    guard let banRange = text.range(of: "ばん") ?? text.range(of: "番") else { return nil }
    let head = String(text[text.startIndex..<banRange.lowerBound])
    for (word, value) in numberWords where head.hasSuffix(word) { return value }
    return nil
}

// MARK: - 主流程

@main
struct SplitAudio {

    /// 截一小段音频到临时文件。识别接口只吃文件。
    static func extract(_ url: URL, from start: Double, length: Double, index: Int) -> URL? {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-\(index).m4a")
        try? FileManager.default.removeItem(at: out)
        export.outputURL = out
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        let sem = DispatchSemaphore(value: 0)
        export.exportAsynchronously { sem.signal() }
        sem.wait()
        return export.status == .completed ? out : nil
    }

    static func recognize(_ url: URL) async -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")),
              recognizer.isAvailable else { return "" }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        return await withCheckedContinuation { continuation in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if error != nil { resumed = true; continuation.resume(returning: ""); return }
                guard let result, result.isFinal else { return }
                resumed = true
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("用法：SplitAudio <音频> [输出.json]\n".utf8))
            exit(1)
        }
        let url = URL(fileURLWithPath: args[1])

        let authSem = DispatchSemaphore(value: 0)
        SFSpeechRecognizer.requestAuthorization { _ in authSem.signal() }
        authSem.wait()

        guard let env = try? envelope(of: url) else {
            FileHandle.standardError.write(Data("  读不了这个音频\n".utf8)); exit(1)
        }
        let candidates = silenceEnds(in: env)
        FileHandle.standardError.write(Data(String(
            format: "  时长 %.1f 分钟 · %d 个候选边界\n", env.duration / 60, candidates.count
        ).utf8))

        // 每个候选边界后识别 6 秒 ——「にばん」这种播报只有一两秒，
        // 6 秒足够；再长会带进后面的对话，反而干扰匹配。
        var marks: [(number: Int, time: Double)] = []
        for (index, time) in candidates.enumerated() {
            guard let clip = extract(url, from: time, length: 6, index: index) else { continue }
            let text = await recognize(clip)
            try? FileManager.default.removeItem(at: clip)
            if let n = questionNumber(in: text) {
                marks.append((n, time))
                FileHandle.standardError.write(Data(
                    "    \(n) 番  \(Int(time))s  「\(text.prefix(20))」\n".utf8
                ))
            }
        }

        // 清洗。
        //
        // **题号在每个大题开头会回到 1** —— 和试卷上的题号一样。
        // 所以不能简单要求递增（那会把第二个大题起的所有题全丢掉，
        // 实测只剩 8 道）。规则是：要么比上一个大，要么正好是 1（新大题）。
        //
        // 另外识别偶尔会在对话里听出「三番」这类词，用「必须递增或重置为 1」
        // 也能把它们滤掉。
        var clean: [(section: Int, number: Int, time: Double)] = []
        var section = 1
        for mark in marks.sorted(by: { $0.time < $1.time }) {
            if let last = clean.last {
                if mark.number == 1, last.number > 1 {
                    section += 1                      // 新大题
                } else if mark.number <= last.number {
                    continue                          // 对话里的杂音
                }
                // 同一个播报被相邻候选边界重复识别到
                if mark.time - last.time < 8 { continue }
            }
            clean.append((section, mark.number, mark.time))
        }

        print("  定位到 \(clean.count) 道题")
        var lastSection = 0
        for mark in clean {
            if mark.section != lastSection {
                print("  ── 大题 \(mark.section) ──")
                lastSection = mark.section
            }
            print("    \(mark.number) 番  \(Int(mark.time))s")
        }

        if args.count > 2 {
            struct Segment: Codable {
                var section: Int; var number: Int; var start: Double; var end: Double
            }
            let segments = clean.enumerated().map { index, mark in
                Segment(section: mark.section, number: mark.number, start: mark.time,
                        end: index + 1 < clean.count ? clean[index + 1].time : env.duration)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(segments).write(to: URL(fileURLWithPath: args[2]))
            FileHandle.standardError.write(Data("  已写出 \(segments.count) 个片段\n".utf8))
        }
    }
}
