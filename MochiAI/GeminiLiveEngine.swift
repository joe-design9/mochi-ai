import AVFoundation
import Combine
import Foundation

/// Gemini Live transport for the phone-call mode (BidiGenerateContent
/// over a WebSocket): the mic streams up as PCM16 mono 16 kHz, the
/// model's spoken answer streams back as PCM16 24 kHz and is scheduled
/// into an AVAudioPlayerNode for gapless playback. Barge-in works via
/// the server's `interrupted` signal, which flushes the player
/// immediately. Server-side transcriptions of both sides are collected
/// per turn so the controller can write the call into the chat log.
///
/// Threading: all state lives on the main queue (socket callbacks hop
/// there); the audio tap only touches the lock-protected gate and the
/// socket box. JSON is built/parsed with JSONSerialization and typed
/// locals — no fragile Decodable chains.
final class GeminiLiveEngine: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isModelSpeaking = false

    // Controller callbacks (all fired on the main queue).
    var onConnected: (() -> Void)?
    var onSetupFailure: ((String) -> Void)?
    /// Socket ended AFTER a successful setup (goAway, close, error).
    var onEnded: (() -> Void)?
    var onUserTranscript: ((String) -> Void)?
    var onAssistantTranscript: ((String) -> Void)?
    var onUserCaption: ((String) -> Void)?
    var onAssistantCaption: ((String) -> Void)?
    var onInterrupted: (() -> Void)?

    private enum Phase {
        case idle
        case connecting
        case connected
        case closed
    }

    private var phase: Phase = .idle
    private var intentionalStop = false

    // Socket
    private var session: URLSession?
    private var socketTask: URLSessionWebSocketTask?
    private var setupTimeoutItem: DispatchWorkItem?

    // Audio
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playbackFormat: AVAudioFormat?
    private var pendingBuffers = 0

    /// Lock-protected flags read by the audio tap thread.
    private final class AudioGate {
        private let lock = NSLock()
        private var openFlag = false
        private var mutedFlag = false

        func setOpen(_ value: Bool) {
            lock.lock(); openFlag = value; lock.unlock()
        }

        func setMuted(_ value: Bool) {
            lock.lock(); mutedFlag = value; lock.unlock()
        }

        var shouldStream: Bool {
            lock.lock()
            defer { lock.unlock() }
            return openFlag && !mutedFlag
        }
    }

    private let gate = AudioGate()

    // Per-turn transcript accumulators.
    private var pendingUserTranscript = ""
    private var pendingAssistantTranscript = ""

    // MARK: Lifecycle

    func start(apiKey: String, model: String, systemInstruction: String) {
        stop()
        intentionalStop = false
        phase = .connecting
        pendingUserTranscript = ""
        pendingAssistantTranscript = ""

        var components = URLComponents()
        components.scheme = "wss"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            phase = .closed
            onSetupFailure?("Live-Adresse ungültig")
            return
        }

        let session = URLSession(configuration: .default)
        self.session = session
        let task = session.webSocketTask(with: url)
        socketTask = task
        task.resume()

        sendSetup(model: model, systemInstruction: systemInstruction)

        // Setup must complete quickly — otherwise the model name is
        // wrong or the service is unreachable, and the controller
        // falls back instead of letting the call ring forever.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .connecting else { return }
            self.failSetup("Live-Dienst antwortet nicht")
        }
        setupTimeoutItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)

        receiveNext()
    }

    func stop() {
        intentionalStop = true
        phase = .closed
        setupTimeoutItem?.cancel()
        setupTimeoutItem = nil
        gate.setOpen(false)
        stopAudio()
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        session?.invalidateAndCancel()
        session = nil
        if isConnected { isConnected = false }
        if isModelSpeaking { isModelSpeaking = false }
    }

    func setMuted(_ muted: Bool) {
        gate.setMuted(muted)
    }

    // MARK: Setup frame

    private func sendSetup(model: String, systemInstruction: String) {
        let voiceConfig: [String: Any] = [
            "prebuiltVoiceConfig": ["voiceName": "Kore"],
        ]
        let speechConfig: [String: Any] = [
            "voiceConfig": voiceConfig,
            "languageCode": "de-DE",
        ]
        let generationConfig: [String: Any] = [
            "responseModalities": ["AUDIO"],
            "speechConfig": speechConfig,
        ]
        let setup: [String: Any] = [
            "model": "models/\(model)",
            "generationConfig": generationConfig,
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "inputAudioTranscription": [String: Any](),
            "outputAudioTranscription": [String: Any](),
        ]
        sendJSON(["setup": setup]) { [weak self] error in
            guard let self, error != nil, self.phase == .connecting else { return }
            self.failSetup("Live-Setup konnte nicht gesendet werden")
        }
    }

    private func sendJSON(_ object: [String: Any], completion: ((Error?) -> Void)? = nil) {
        guard let task = socketTask,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            completion?(nil)
            return
        }
        task.send(.string(string)) { error in
            completion?(error)
        }
    }

    // MARK: Receive loop

    private func receiveNext() {
        guard let task = socketTask else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let text: String?
                switch message {
                case .string(let string):
                    text = string
                case .data(let data):
                    text = String(data: data, encoding: .utf8)
                @unknown default:
                    text = nil
                }
                DispatchQueue.main.async {
                    if let text {
                        self.handleMessage(text)
                    }
                    if self.phase == .connecting || self.phase == .connected {
                        self.receiveNext()
                    }
                }
            case .failure:
                DispatchQueue.main.async {
                    self.handleSocketClosed()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data),
              let dict = raw as? [String: Any] else { return }

        if dict["setupComplete"] != nil {
            handleSetupComplete()
            return
        }

        if let errorDict = dict["error"] as? [String: Any] {
            let message = (errorDict["message"] as? String) ?? "Live-Fehler"
            if phase == .connected {
                endFromServer()
            } else if phase == .connecting {
                failSetup(message)
            }
            return
        }

        if dict["goAway"] != nil {
            if phase == .connected {
                endFromServer()
            }
            return
        }

        guard let content = dict["serverContent"] as? [String: Any] else { return }

        if let transcription = content["inputTranscription"] as? [String: Any],
           let piece = transcription["text"] as? String, !piece.isEmpty {
            pendingUserTranscript += piece
            onUserCaption?(pendingUserTranscript)
        }

        if let transcription = content["outputTranscription"] as? [String: Any],
           let piece = transcription["text"] as? String, !piece.isEmpty {
            pendingAssistantTranscript += piece
            onAssistantCaption?(pendingAssistantTranscript)
        }

        if (content["interrupted"] as? Bool) == true {
            flushPlayback()
            onInterrupted?()
        }

        if let turn = content["modelTurn"] as? [String: Any],
           let parts = turn["parts"] as? [[String: Any]] {
            for part in parts {
                if let inline = part["inlineData"] as? [String: Any],
                   let base64 = inline["data"] as? String,
                   let audio = Data(base64Encoded: base64) {
                    playAudioChunk(audio)
                }
            }
        }

        if (content["turnComplete"] as? Bool) == true {
            let userText = pendingUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            let assistantText = pendingAssistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingUserTranscript = ""
            pendingAssistantTranscript = ""
            if !userText.isEmpty {
                onUserTranscript?(userText)
            }
            if !assistantText.isEmpty {
                onAssistantTranscript?(assistantText)
            }
        }
    }

    private func handleSetupComplete() {
        guard phase == .connecting else { return }
        phase = .connected
        setupTimeoutItem?.cancel()
        setupTimeoutItem = nil
        startAudio()
        isConnected = true
        onConnected?()
    }

    private func failSetup(_ message: String) {
        guard phase == .connecting else { return }
        phase = .closed
        setupTimeoutItem?.cancel()
        setupTimeoutItem = nil
        gate.setOpen(false)
        stopAudio()
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        session?.invalidateAndCancel()
        session = nil
        onSetupFailure?(message)
    }

    /// The server ended a live call (goAway / error frame post-setup).
    private func endFromServer() {
        guard phase == .connected else { return }
        phase = .closed
        gate.setOpen(false)
        stopAudio()
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
        isModelSpeaking = false
        if !intentionalStop {
            onEnded?()
        }
    }

    private func handleSocketClosed() {
        guard !intentionalStop else { return }
        switch phase {
        case .connecting:
            failSetup("Verbindung zum Live-Dienst fehlgeschlagen")
        case .connected:
            endFromServer()
        case .idle, .closed:
            break
        }
    }

    // MARK: Audio out (model voice, PCM16 24 kHz)

    private func playAudioChunk(_ data: Data) {
        guard let format = playbackFormat, data.count >= 2 else { return }
        let frameCount = data.count / 2
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        if let channel = buffer.int16ChannelData?[0] {
            data.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    memcpy(channel, base, frameCount * 2)
                }
            }
        }
        pendingBuffers += 1
        isModelSpeaking = true
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingBuffers = max(0, self.pendingBuffers - 1)
                if self.pendingBuffers == 0 {
                    self.isModelSpeaking = false
                }
            }
        }
    }

    /// Barge-in: drop everything queued so the model stops NOW.
    private func flushPlayback() {
        playerNode.stop()
        pendingBuffers = 0
        isModelSpeaking = false
        if audioEngine.isRunning {
            playerNode.play()
        }
    }

    // MARK: Audio graph (mic in + model out)

    private func startAudio() {
        playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: true
        )

        let engine = audioEngine
        if !engine.attachedNodes.contains(playerNode) {
            engine.attach(playerNode)
        }
        if let playbackFormat {
            engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            return
        }

        gate.setOpen(true)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            // Audio thread: only the gate, the converter and the
            // socket send are touched here.
            guard let self, self.gate.shouldStream else { return }
            self.convertAndSend(buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            engine.prepare()
            try engine.start()
            playerNode.play()
        } catch {
            gate.setOpen(false)
        }
    }

    private func stopAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        pendingBuffers = 0
    }

    /// Converts one mic buffer to PCM16 16 kHz mono and streams it as
    /// a `realtimeInput` audio frame (base64).
    private func convertAndSend(_ buffer: AVAudioPCMBuffer,
                                converter: AVAudioConverter,
                                targetFormat: AVAudioFormat) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var conversionError: NSError?
        var provided = false
        let status = converter.convert(to: out, error: &conversionError) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0,
              let channel = out.int16ChannelData?[0] else { return }
        let data = Data(bytes: channel, count: Int(out.frameLength) * 2)
        let frame: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": data.base64EncodedString(),
                ],
            ],
        ]
        guard let task = socketTask,
              let jsonData = try? JSONSerialization.data(withJSONObject: frame),
              let string = String(data: jsonData, encoding: .utf8) else { return }
        task.send(.string(string)) { _ in }
    }
}
