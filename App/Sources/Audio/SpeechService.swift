import AVFoundation
import Observation
import B2FCore

/// Pronunciation audio: live playback with British/American voices and
/// 0.5×–1.5× speed, plus rendering to `.m4a` files for Anki export.
@MainActor
@Observable
final class SpeechService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: StudyLanguage, accent: EnglishAccent, speed: PlaybackSpeed) {
        guard !text.isEmpty else { return }
        configureSession()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        synthesizer.speak(Self.utterance(text, language: language, accent: accent, speed: speed))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated static func utterance(_ text: String, language: StudyLanguage, accent: EnglishAccent, speed: PlaybackSpeed) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        let code = language == .english ? accent.rawValue : language.speechLanguageCode
        utterance.voice = bestVoice(for: code)
        // AVSpeech's default rate (0.5) is natural speech; scale it and clamp to the API range.
        let rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed.rawValue)
        utterance.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.prefersAssistiveTechnologySettings = true
        return utterance
    }

    /// Prefers premium/enhanced voices when the user has downloaded them.
    nonisolated static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return voices.first { $0.quality == .premium } ?? voices.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

/// Renders speech to AAC files (one per card) so exported Anki decks carry audio.
final class AudioRenderer: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// Stable file name per text+voice so repeated exports reuse files.
    static func fileName(for text: String, voice: String) -> String {
        "b2f_" + SHA1.hexDigest(voice + "|" + text).prefix(16) + ".m4a"
    }

    func render(_ text: String, language: StudyLanguage, accent: EnglishAccent) async throws -> String {
        let utterance = SpeechService.utterance(text, language: language, accent: accent, speed: .normal)
        let name = Self.fileName(for: text, voice: utterance.voice?.identifier ?? language.rawValue)
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return name }

        let temp = url.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: temp)
        var file: AVAudioFile?
        var failure: Error?

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    // A zero-length buffer marks the end of synthesis.
                    if !finished { finished = true; continuation.resume() }
                    return
                }
                do {
                    if file == nil {
                        let settings: [String: Any] = [
                            AVFormatIDKey: kAudioFormatMPEG4AAC,
                            AVSampleRateKey: pcm.format.sampleRate,
                            AVNumberOfChannelsKey: pcm.format.channelCount,
                            AVEncoderBitRateKey: 64_000
                        ]
                        file = try AVAudioFile(forWriting: temp, settings: settings,
                                               commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
                    }
                    try file?.write(from: pcm)
                } catch {
                    failure = error
                    if !finished { finished = true; continuation.resume() }
                }
            }
        }
        file = nil // closes the file
        if let failure { throw failure }
        guard FileManager.default.fileExists(atPath: temp.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.moveItem(at: temp, to: url)
        return name
    }
}
