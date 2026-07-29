import Foundation
import AVFoundation

/// 播放一段音频区间。听力题用。
///
/// 播的是**整份录音的一个片段**，不是切好的小文件 —— `Tools/SplitAudio` 只算
/// 时间点，音频保持原样。一份 N4 听力 35 MB，切成 28 个小文件既要重新编码
/// （损失音质），又要多占一倍存储。
///
/// 到点自动停：用 `boundaryTime` 观察器，比轮询精确，也不用维护定时器。
@MainActor
@Observable
final class SegmentPlayer {
    @ObservationIgnored static let shared = SegmentPlayer()

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var boundaryToken: Any?

    /// 正在播的片段标识（题目 UUID 字符串）。nil = 没在播。
    private(set) var playing: String?
    /// 播放进度 0...1。界面画进度条用。
    private(set) var progress: Double = 0
    @ObservationIgnored private var progressToken: Any?

    private init() {}

    func play(url: URL, from start: Double, to end: Double, id: String) {
        stop()
        guard end > start else { return }

        // 用户主动点了才发声，静音键不该挡掉；用 duckOthers 压低而不是掐断别人的音频
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        playing = id
        progress = 0

        player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) { [weak self] _ in
            guard let self, self.playing == id else { return }
            player.play()
        }

        // 到达片段末尾自动停
        boundaryToken = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: end, preferredTimescale: 600))],
            queue: .main
        ) { [weak self] in
            self?.stop()
        }

        progressToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            guard let self, self.playing == id else { return }
            let elapsed = CMTimeGetSeconds(time) - start
            self.progress = min(1, max(0, elapsed / (end - start)))
        }
    }

    func stop() {
        if let boundaryToken { player?.removeTimeObserver(boundaryToken) }
        if let progressToken { player?.removeTimeObserver(progressToken) }
        boundaryToken = nil
        progressToken = nil
        player?.pause()
        player = nil
        playing = nil
        progress = 0
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func isPlaying(_ id: String) -> Bool { playing == id }
}

/// 导入的听力音频存哪儿。
///
/// 放 Application Support 而不是 Documents —— 用户不该在「文件」App 里
/// 看到这些内部文件。按试卷 id 命名，一套一份。
enum ExamAudioStore {
    static var directory: URL {
        let base = URL.applicationSupportDirectory.appendingPathComponent("ExamAudio")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// 把用户选的音频拷进沙箱。返回存下来的文件名。
    ///
    /// 必须拷贝而不是记住原路径：文件选择器给的是沙箱外的临时授权，
    /// App 重启后就失效了。
    static func store(from source: URL, examID: String) throws -> String {
        let filename = "\(examID).\(source.pathExtension.isEmpty ? "mp3" : source.pathExtension)"
        let destination = url(for: filename)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        return filename
    }

    static func exists(_ filename: String?) -> Bool {
        guard let filename else { return false }
        return FileManager.default.fileExists(atPath: url(for: filename).path)
    }

    static func remove(_ filename: String?) {
        guard let filename else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}
