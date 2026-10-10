import AVFoundation
import Foundation
import Combine

/// 听书高亮：第几章 + 章内字符区间
struct SpeechHighlight: Equatable {
    let chapterIndex: Int
    let range: NSRange
}

/// 系统语音合成封装：逐句朗读、播放/暂停、上下句、定时停止。
///
/// 设计要点：
/// - 每句一个 AVSpeechUtterance，朗读结束回调后推进下一句，读完一章通过 `onChapterFinish` 通知外部；
/// - 高亮直接等于当前 utterance 的章节内区间，交给阅读器映射到当前页；
/// - AVSpeechSynthesizer 的 delegate 回调不在主线程，所有 @Published 更新都要包回主线程。
final class SpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentSentenceIndex = 0
    @Published private(set) var highlight: SpeechHighlight?
    /// 定时关闭剩余秒数（nil = 未开启）
    @Published var sleepRemainingSeconds: Int?

    /// 一章读完后请求下一章；外部返回下一章文本（nil = 没有更多章节，停止）
    var onChapterFinish: ((Int) -> String?)?

    private let synthesizer = AVSpeechSynthesizer()
    private var sentenceRanges: [NSRange] = []
    private var chapterText = ""
    private var chapterIndex = 0
    private var rate: Float = 0.5
    private var pitch: Float = 1.0
    private var sleepTimer: Timer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - 句子切分

    /// 按常见中文/英文句末标点与换行切句，返回每句在文本中的区间
    static func sentenceRanges(in text: String) -> [NSRange] {
        let pattern = #"[^。！？!?；;\n]*[。！？!?；;]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.map(\.range).filter { $0.length > 0 }
    }

    // MARK: - 控制

    /// 从指定章节开始朗读
    func start(chapter: Int, text: String, rate: Float, pitch: Float) {
        configureAudioSession()
        stopInternal()

        self.chapterIndex = chapter
        self.chapterText = text
        self.rate = rate
        self.pitch = pitch
        sentenceRanges = Self.sentenceRanges(in: text)

        guard !sentenceRanges.isEmpty else {
            isSpeaking = false
            return
        }
        speakSentence(0)
    }

    func togglePlayPause() {
        if isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
        } else if isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
        }
    }

    func previousSentence() {
        stopSpeakingThenSpeak(max(currentSentenceIndex - 1, 0))
    }

    func nextSentence() {
        stopSpeakingThenSpeak(currentSentenceIndex + 1)
    }

    func stop() {
        stopInternal()
        highlight = nil
        cancelSleepTimer()
    }

    /// 更新语速/语调：对下一句生效（正在读的句子不打断）
    func updateRate(_ value: Float) { rate = value }
    func updatePitch(_ value: Float) { pitch = value }

    // MARK: - 定时停止

    func scheduleSleepTimer(minutes: Int) {
        cancelSleepTimer()
        sleepRemainingSeconds = minutes * 60
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            DispatchQueue.main.async {
                guard let remaining = self.sleepRemainingSeconds else {
                    timer.invalidate()
                    return
                }
                if remaining <= 1 {
                    self.stopInternal()
                    self.highlight = nil
                    self.sleepRemainingSeconds = nil
                    timer.invalidate()
                } else {
                    self.sleepRemainingSeconds = remaining - 1
                }
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepRemainingSeconds = nil
    }

    // MARK: - 私有

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    private func stopInternal() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        currentSentenceIndex = 0
    }

    private func stopSpeakingThenSpeak(_ index: Int) {
        synthesizer.stopSpeaking(at: .immediate)
        speakSentence(index)
    }

    private func speakSentence(_ index: Int) {
        guard sentenceRanges.indices.contains(index) else {
            // 本章读完 → 请求下一章；外部给不出文本就整体停止
            let next = chapterIndex + 1
            let nextText = onChapterFinish?(next)
            if let nextText {
                start(chapter: next, text: nextText, rate: rate, pitch: pitch)
            } else {
                stopInternal()
                highlight = nil
            }
            return
        }

        currentSentenceIndex = index
        let range = sentenceRanges[index]
        highlight = SpeechHighlight(chapterIndex: chapterIndex, range: range)

        let utterance = AVSpeechUtterance(string: (chapterText as NSString).substring(with: range))
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)

        isSpeaking = true
        isPaused = false
    }

    // MARK: - AVSpeechSynthesizerDelegate（回调不在主线程）

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.isSpeaking, !self.isPaused else { return }
            self.speakSentence(self.currentSentenceIndex + 1)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // 用户主动切换句子时触发，无需处理
    }
}
