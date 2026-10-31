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
/// Playback smoothness (v2.2.1): the server delivers its audio in many
/// small, irregularly timed parts. Scheduling each part directly onto
/// the player starved it between parts — the call stuttered. Incoming
/// PCM now lands in a jitter buffer first: playback of a turn only
/// starts once ~0.4 s is buffered, and the player is fed consolidated
/// ~0.3 s buffers chained through its completion handler, so the
/// queue stays ahead of the playhead for the whole turn.
///
/// Threading: all state lives on the main queue (socket callbacks hop
/// there). The audio tap only checks the lock-protected gate and
/// copies its buffer; conversion + base64 + socket send run on a
/// dedicated serial uplink queue — nothing heavy on the realtime
/// thread, and no lock is ever held during a network send. JSON is
/// built/parsed with JSONSerialization and typed locals — no fragile
/// Decodable chains.
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

    // Jitter buffer for the model voice (main queue only). Raw PCM16
    // 24 kHz bytes accumulate in `jitterData`; `pumpPlayback()` cuts
    // them into consolidated buffers for the player. Playback of a
    // turn is primed only after `primeBytes` (~0.4 s) has arrived, so
    // network jitter cannot starve the player mid-turn.
    private var jitterData = Data()
    private var scheduledBuffers = 0
    private var playbackPrimed = false
    private var turnAudioEnded = false
    private static let primeBytes = 19_200   // 0.40 s @ 24 kHz Int16 mono
    private static let chunkBytes = 14_400   // 0.30 s @ 24 kHz Int16 mono

    // Uplink: conversion + send run on this serial queue, never on
    // the audio tap's realtime thread. The converter is used ONLY on
    // this queue (AVAudioConverter is not thread-safe).
    private let uplinkQueue = DispatchQueue(label: "de.mochi.live.uplink", qos: .userInitiated)
    private var uplinkConverter: AVAudioConverter?
    private var uplinkTargetFormat: AVAudioFormat?

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
            finishAudioTurn()
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

    // MARK: Audio out (model voice, PCM16 24 kHz, jitter-buffered)

    /// One raw audio part from the server. Parts are small and arrive
    /// at network pace — they are NEVER scheduled directly; they only
    /// feed the jitter buffer, and `pumpPlayback()` decides when the
    /// player gets its next consolidated buffer.
    private func playAudioChunk(_ data: Data) {
        guard playbackFormat != nil, data.count >= 2 else { return }
        jitterData.append(data)
        pumpPlayback()
    }

    /// The server closed the current turn: whatever is still buffered
    /// (less than a full chunk) is flushed to the player as the final
    /// buffer, and once the queue has drained the next turn primes
    /// from scratch — so a fresh turn gets the full jitter cushion
    /// again instead of starting dry.
    private func finishAudioTurn() {
        turnAudioEnded = true
        pumpPlayback()
        if jitterData.isEmpty, scheduledBuffers == 0 {
            // A turn with no audio at all must not leak its state
            // into the next turn.
            turnAudioEnded = false
            playbackPrimed = false
            isModelSpeaking = false
        }
    }

    /// Feeds the player from the jitter buffer (main queue only).
    /// - Before priming: waits until ~0.4 s is buffered (or the turn
    ///   already ended — a very short answer plays with what it has).
    /// - While primed: cuts ~0.3 s buffers as long as enough data is
    ///   there; at turn end schedules the remainder as one last
    ///   buffer. Buffer completions re-enter here, which chains the
    ///   scheduling and detects the drained queue.
    private func pumpPlayback() {
        if !playbackPrimed {
            let hasCushion = jitterData.count >= Self.primeBytes
            let shortTurn = turnAudioEnded && !jitterData.isEmpty
            guard hasCushion || shortTurn else { return }
            playbackPrimed = true
            isModelSpeaking = true
        }
        while jitterData.count >= Self.chunkBytes {
            let chunk = jitterData.prefix(Self.chunkBytes)
            jitterData.removeFirst(Self.chunkBytes)
            schedulePCM(Data(chunk))
        }
        if turnAudioEnded, !jitterData.isEmpty {
            let rest = jitterData
            jitterData.removeAll()
            schedulePCM(rest)
        }
    }

    /// Builds ONE AVAudioPCMBuffer (24 kHz Int16 mono — the format the
    /// player was connected with, so the system mixer resamples to
    /// the hardware rate exactly once) and schedules it. The frame
    /// count is integer-exact: odd trailing bytes are dropped.
    private func schedulePCM(_ data: Data) {
        guard let format = playbackFormat else { return }
        let frameCount = data.count / 2
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
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
        scheduledBuffers += 1
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.scheduledBuffers = max(0, self.scheduledBuffers - 1)
                if self.scheduledBuffers == 0, self.jitterData.isEmpty {
                    // Queue fully drained — after a real underrun
                    // (mid-turn network stall) AND at a clean turn
                    // end alike, the next audio primes from scratch
                    // instead of starting dry and stuttering again.
                    self.turnAudioEnded = false
                    self.playbackPrimed = false
                    self.isModelSpeaking = false
                } else {
                    self.pumpPlayback()
                }
            }
        }
    }

    /// Barge-in: drop everything buffered and queued so the model
    /// stops NOW; the next turn primes again from an empty buffer.
    private func flushPlayback() {
        jitterData.removeAll()
        scheduledBuffers = 0
        playbackPrimed = false
        turnAudioEnded = false
        playerNode.stop()
        isModelSpeaking = false
        if audioEngine.isRunning {
            playerNode.play()
        }
    }

    /// Full playback reset (stop/teardown paths).
    private func resetPlaybackState() {
        jitterData.removeAll()
        scheduledBuffers = 0
        playbackPrimed = false
        turnAudioEnded = false
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
        // Connect once — on a reconnect the existing connection (same
        // 24 kHz format) is still in place and must not be re-made.
        if let playbackFormat,
           engine.outputConnectionPoints(for: playerNode, outputBus: 0).isEmpty {
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
        uplinkConverter = converter
        uplinkTargetFormat = targetFormat

        gate.setOpen(true)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            // Realtime thread: check the gate and copy the buffer —
            // NOTHING else. The tap's buffer is only valid for the
            // duration of this call, so the copy is the one piece of
            // work that must happen here; conversion, base64 and the
            // socket send all run on the serial uplink queue.
            guard let self, self.gate.shouldStream,
                  let copy = Self.copyPCMBuffer(buffer) else { return }
            self.uplinkQueue.async { [weak self] in
                self?.convertAndSend(copy)
            }
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
        resetPlaybackState()
    }

    /// Deep-copies a tap buffer so it can outlive the tap callback.
    /// Plain memcpy per channel over the buffer lists — the copy has
    /// the identical format and frame length.
    private static func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(
                pcmFormat: buffer.format,
                frameCapacity: buffer.frameLength
              ) else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeAudioBufferListPointer(buffer.audioBufferList)
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<min(source.count, target.count) {
            target[index].mDataByteSize = source[index].mDataByteSize
            if let from = source[index].mData, let to = target[index].mData {
                memcpy(to, from, Int(source[index].mDataByteSize))
            }
        }
        return copy
    }

    /// Converts one mic buffer to PCM16 16 kHz mono and streams it as
    /// a `realtimeInput` audio frame (base64). Runs ONLY on the uplink
    /// queue — the converter and the socket send never touch the
    /// realtime audio thread, and no lock is held while sending.
    private func convertAndSend(_ buffer: AVAudioPCMBuffer) {
        guard let converter = uplinkConverter,
              let targetFormat = uplinkTargetFormat else { return }
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
