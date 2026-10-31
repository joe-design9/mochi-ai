import AVFoundation
import Combine
import Foundation
import Speech
import UIKit

// MARK: - Permissions

/// Mic + speech-recognition permission requests for the call mode.
/// Both transports need the microphone; the fallback pipeline also
/// needs speech recognition (Live transcribes on Google's side).
enum VoicePermissions {
    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    static var microphoneGranted: Bool {
        AVAudioApplication.recordPermission == .granted
    }

    static func requestSpeechRecognition() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static var speechRecognitionGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Error-note detection

/// The chat engines turn failures into friendly in-chat notes instead
/// of throwing — in the call, those notes must NOT be read aloud
/// verbatim; the caller speaks one short line instead ("Das hat leider
/// nicht geklappt."). Detection works on the notes' known openings
/// (APIClient in ChatEngine.swift, AppleIntelligenceEngine, and the
/// empty-answer note in GeminiAPI).
enum CallErrorNotes {
    private static let prefixes = [
        "Da klemmt gerade was bei Google:",
        "Der Anbieter meldet:",
        "Apple KI ist auf diesem iPhone gerade nicht verfügbar.",
        "Apple KI hat gerade keine Antwort parat",
        "Apple KI hat diese Anfrage aus Sicherheitsgründen abgelehnt",
        "Diese Unterhaltung ist für das Geräte-Modell zu lang geworden.",
        "Mit Apple KI ist gerade etwas schiefgelaufen",
        "Unerwartetes Antwortformat",
    ]

    static func isErrorNote(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefixes.contains { trimmed.hasPrefix($0) }
    }
}

// MARK: - Fallback pipeline (recognizer → chat engine → synthesizer)

/// The standard-mode call pipeline used when Gemini Live is not the
/// active transport (Apple-KI mode, OpenAI-compatible provider, or a
/// failed Live setup): SFSpeechRecognizer transcribes the user,
/// AppStore's normal send queue produces the reply, and
/// AVSpeechSynthesizer reads it aloud. One listen-turn at a time; the
/// call controller drives the loop.
@MainActor
final class PipelineVoiceEngine: NSObject, ObservableObject {
    @Published private(set) var partialTranscript = ""
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false

    // Recognition
    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTask: Task<Void, Never>?
    private var finalHandler: ((String) -> Void)?
    private var emptyHandler: (() -> Void)?
    private var unavailableHandler: (() -> Void)?

    // Synthesis
    private let synthesizer = AVSpeechSynthesizer()
    private var speakCompletion: (() -> Void)?

    override init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de_DE"))
            ?? SFSpeechRecognizer(locale: Locale.current)
        super.init()
        synthesizer.delegate = self
    }

    /// True when a recognizer exists and is currently available
    /// (on-device model present or server recognition reachable).
    var recognitionAvailable: Bool {
        guard let recognizer else { return false }
        return recognizer.isAvailable
    }

    // MARK: Listening

    /// Starts one recognition turn. `onFinal` fires exactly once with
    /// the recognized text (also when the turn ends via the silence
    /// timer or a recognition error after partial speech); `onEmpty`
    /// fires when nothing was understood; `onUnavailable` when the
    /// recognizer can't run at all.
    func startListening(onFinal: @escaping (String) -> Void,
                        onEmpty: @escaping () -> Void,
                        onUnavailable: @escaping () -> Void) {
        stopListening(deliver: false)
        guard let recognizer, recognizer.isAvailable else {
            onUnavailable()
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        finalHandler = onFinal
        emptyHandler = onEmpty
        unavailableHandler = onUnavailable
        partialTranscript = ""

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            recognitionRequest = nil
            onUnavailable()
            return
        }
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognition(result: result, error: error)
            }
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard isListening else { return }
        if let result {
            let text = result.bestTranscription.formattedString
            if !text.isEmpty {
                partialTranscript = text
                resetSilenceTimer()
            }
            if result.isFinal {
                finishListening(with: text)
                return
            }
        }
        if error != nil {
            // A recognition error after some speech still yields the
            // partial text; with no text at all it counts as "empty".
            let text = partialTranscript
            finishListening(with: text)
        }
    }

    /// Auto-stop: ~1.5 s without a new partial result ends the turn
    /// (only arms once the user actually said something).
    private func resetSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled, self.isListening else { return }
            let text = self.partialTranscript
            if !text.isEmpty {
                self.finishListening(with: text)
            }
        }
    }

    private func finishListening(with text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = finalHandler
        let empty = emptyHandler
        stopListening(deliver: false)
        if trimmed.isEmpty {
            empty?()
        } else {
            final?(trimmed)
        }
    }

    /// Stops the current recognition turn. With `deliver == true` a
    /// non-empty partial transcript is handed to the final handler
    /// (manual stop); otherwise the turn is discarded silently.
    func stopListening(deliver: Bool) {
        silenceTask?.cancel()
        silenceTask = nil
        let pendingText = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = finalHandler
        finalHandler = nil
        emptyHandler = nil
        unavailableHandler = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false

        if deliver, !pendingText.isEmpty {
            final?(pendingText)
        }
    }

    // MARK: Speaking

    /// Speaks a reply with the best available German voice.
    /// `onDone` fires exactly once (finished, cancelled or failed).
    /// A still-pending previous utterance is superseded WITHOUT firing
    /// its completion — the new utterance takes over the loop.
    func speak(_ text: String, onDone: @escaping () -> Void) {
        cancelCurrentSpeech(fireCompletion: false)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onDone()
            return
        }
        speakCompletion = onDone
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.bestGermanVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// User-facing stop (the call's "Stopp" button): ends the current
    /// utterance AND fires its completion so the call loop moves on
    /// to listening.
    func stopSpeaking() {
        cancelCurrentSpeech(fireCompletion: true)
    }

    private func cancelCurrentSpeech(fireCompletion: Bool) {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        let completion = speakCompletion
        speakCompletion = nil
        if fireCompletion {
            completion?()
        }
    }

    /// Picks the highest-quality German voice: premium/enhanced
    /// de-DE first, then any de-DE, then any German voice.
    private static func bestGermanVoice() -> AVSpeechSynthesisVoice? {
        let german = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("de")
        }
        let exact = german.filter { $0.language == "de-DE" }
        let pool = exact.isEmpty ? german : exact
        if let premium = pool.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = pool.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return pool.first ?? AVSpeechSynthesisVoice(language: "de-DE")
    }

    // MARK: Teardown

    func teardown() {
        stopListening(deliver: false)
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        speakCompletion = nil
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension PipelineVoiceEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            let completion = self.speakCompletion
            self.speakCompletion = nil
            completion?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            let completion = self.speakCompletion
            self.speakCompletion = nil
            completion?()
        }
    }
}
