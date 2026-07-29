import Foundation
import AVFoundation

/// 日语朗读。用系统自带的语音合成，**离线、免费、不需要随包任何音频**。
///
/// 设计要点：
///
/// - **喂假名，不喂汉字。** 「乾く」直接给合成器可能读成 かんく；词库里存着 かわく，
///   给读音就不会错。多音词（行く いく/ゆく）、人名地名上差别最明显。
///   调用方负责挑好文本，这里不做猜测。
/// - **优先用高质量语音。** 系统装机自带紧凑版，用户若在「设置 › 辅助功能 › 朗读内容」
///   里下过增强或高级版，自动改用那一个。没下也能出声。
/// - **播放类别用 `.playback`。** 用户是主动点了喇叭才发声的，静音键不该把它挡掉 ——
///   这和背景音乐、提示音的语义不同。用 `.duckOthers` 压低而不是掐断别人的音频。
@MainActor
@Observable
final class Speaker {
    @ObservationIgnored static let shared = Speaker()

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let coordinator = Coordinator()

    /// 这台设备上最好的日语语音。取不到说明系统没有日语语音，界面应隐藏入口。
    @ObservationIgnored private let voice: AVSpeechSynthesisVoice?

    private init() {
        voice = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "ja-JP" }
            // quality: default(1) < enhanced(2) < premium(3)
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "ja-JP")
        synthesizer.delegate = coordinator
    }

    var isAvailable: Bool { voice != nil }

    /// 当前正在读的文本，nil 表示没在读。界面据此把喇叭点亮。
    private(set) var speaking: String?

    /// 朗读一段日语。
    ///
    /// - Parameter text: **假名优先**。调用方应传读音而不是汉字表记。
    func speak(_ text: String) {
        guard let voice, !text.isEmpty else { return }

        // 再点一次正在读的词 = 停下来
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            if speaking == text { speaking = nil; return }
        }

        activateSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // 默认 0.5 对母语者合适，对学习者偏快 —— 单词要听清每个拍子（尤其促音和长音）
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0

        speaking = text
        coordinator.onFinish = { [weak self] in
            self?.speaking = nil
            self?.deactivateSession()
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speaking = nil
        deactivateSession()
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func deactivateSession() {
        // 通知别人可以把音量恢复回去
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// 合成器的回调不保证在主线程上，所以委托对象整体 `nonisolated`，
    /// 拿到回调后再显式跳回主 actor 改状态。
    ///
    /// 这一条是有教训的：调色板那个 `UIColor` 闭包就是因为被默认推断成 MainActor、
    /// 却被 UIKit 从渲染线程调用，在真机上直接 `EXC_BREAKPOINT`。
    private final class Coordinator: NSObject, AVSpeechSynthesizerDelegate {
        /// 只在主 actor 上读写。
        @MainActor var onFinish: (() -> Void)?

        nonisolated func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            didFinish utterance: AVSpeechUtterance
        ) {
            Task { @MainActor in onFinish?() }
        }

        nonisolated func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            didCancel utterance: AVSpeechUtterance
        ) {
            Task { @MainActor in onFinish?() }
        }
    }
}

#if DEBUG
extension Speaker {
    /// `-verifySpeech` 启动时跑一遍：列出这台设备上的日语语音、实际合成一次。
    ///
    /// 词详情面板要点词才能进，模拟器上点不了 —— 这个探针绕过界面直接验合成路径，
    /// 确认语音存在、选中的是最高质量的那个、合成不崩、回调能回到主 actor。
    static func runProbeIfRequested() {
        guard CommandLine.arguments.contains("-verifySpeech") else { return }

        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ja-JP" }
        NSLog("[SpeechProbe] 系统日语语音 %d 个", all.count)
        for v in all {
            let q = ["", "紧凑", "增强", "高级"][min(v.quality.rawValue, 3)]
            NSLog("[SpeechProbe]   %@ · %@ · %@", v.name, q, v.identifier)
        }
        guard shared.isAvailable else {
            NSLog("[SpeechProbe] ✗ 没有日语语音，界面会隐藏朗读入口")
            return
        }
        // 「乾く」的正确读音。喂汉字的话合成器可能读成 かんく —— 这正是要传假名的原因
        shared.speak("かわく")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            NSLog("[SpeechProbe] ✓ 合成完成，speaking=%@",
                  shared.speaking.map { "\"\($0)\"" } ?? "nil（已回调复位）")
        }
    }
}
#endif
