import AVFoundation
import Combine
import SwiftUI

/// The phone call with Muse (v2.2.0): a full-screen call UI — pure
/// black, everything Liquid Glass (status pill, glass-ring companion,
/// glass caption/notice cards, floating glass control capsule with the
/// red-tinted end button inside).
///
/// Transports: with a Gemini key (admin build / grandfathered) or a
/// backend-minted Live token (normal build, v3.0.0) the call runs on
/// the Gemini Live API (GeminiLiveEngine — real-time spoken answers,
/// barge-in included). In Apple-KI mode, with the OpenAI-compatible
/// provider, or when Live fails, the SAME screen runs the standard
/// pipeline (PipelineVoiceEngine: speech recognition → the normal chat
/// send queue → the reply read aloud). Either way, everything said
/// lands in the active conversation as plain chat messages.
struct CallView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = CallController()

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 0) {
                companionBlock
                    .padding(.top, 30)

                statusPill
                    .padding(.top, 16)

                Text(controller.transportTimerText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.top, 8)

                captionArea
                    .padding(.top, 22)

                Spacer()

                if let banner = controller.banner {
                    Text(banner)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(
                            .regular.tint(Palette.glassTint),
                            in: Capsule()
                        )
                        .padding(.bottom, 12)
                }

                if controller.isSpeakingAloud {
                    Button {
                        controller.stopSpeakingNow()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Stopp")
                        }
                        .hairlineCapsule()
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }

                controlCapsule
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear {
#if QA
            // QA screenshot mode (-QACallPreview): render the surface
            // only — never start a real call in CI (no microphone
            // prompt, no network).
            if ProcessInfo.processInfo.arguments.contains("-QACallPreview") {
                return
            }
#endif
            controller.start(store: store) { dismiss() }
        }
        .onDisappear {
            controller.teardown()
        }
    }

    // MARK: Top area — companion, name, status

    private var companionBlock: some View {
        VStack(spacing: 14) {
            ZStack {
                // Neutral glass disc halo behind the companion.
                Circle()
                    .glassEffect(
                        .regular.tint(Palette.glassTint),
                        in: Circle()
                    )
                    .frame(width: 172, height: 172)
                if controller.isListeningActivity {
                    PulseRings(diameter: 172)
                }
                CompanionGlow(character: store.companion, size: 118)
            }
            Text(store.companion.displayName)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.ink)
        }
    }

    private var statusPill: some View {
        Text(controller.statusText)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassEffect(
                .regular.tint(Palette.glassTint),
                in: Capsule()
            )
    }

    // MARK: Caption / notice (glass cards)

    private var captionArea: some View {
        VStack {
            if let note = controller.note {
                VStack(spacing: 12) {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    if controller.noteNeedsSettings {
                        Button {
                            VoicePermissions.openAppSettings()
                        } label: {
                            Text("Einstellungen öffnen")
                                .accentCapsule()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 18)
            } else if !controller.caption.isEmpty {
                Text(controller.caption)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .glassCard(cornerRadius: 18)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .top)
    }

    // MARK: Controls — floating glass capsule

    private var controlCapsule: some View {
        HStack(spacing: 18) {
            controlButton(
                systemImage: controller.isMuted ? "mic.slash.fill" : "mic.fill",
                label: "Stumm",
                isActive: controller.isMuted
            ) {
                controller.toggleMute()
            }

            controlButton(
                systemImage: controller.speakerOn ? "speaker.wave.2.fill" : "ear.fill",
                label: controller.speakerOn ? "Lautspr." : "Hörer",
                isActive: controller.speakerOn
            ) {
                controller.toggleSpeaker()
            }

            controlButton(
                systemImage: "keyboard",
                label: "Tastatur",
                isActive: false
            ) {
                controller.endCall()
            }

            // End call: red-TINTED glass (keeps its red inside the
            // glass system, like the brief demands).
            VStack(spacing: 4) {
                Button {
                    controller.endCall()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 54, height: 54)
                        .glassEffect(
                            .regular.tint(Color.red.opacity(0.5)).interactive(),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Auflegen")
                Text("Auflegen")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(
            .regular.tint(Palette.glassTint),
            in: Capsule()
        )
    }

    private func controlButton(systemImage: String,
                               label: String,
                               isActive: Bool,
                               action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isActive ? Palette.primaryText : Palette.ink)
                    .frame(width: 54, height: 54)
                    .background {
                        if isActive {
                            Circle().fill(Palette.primaryFill)
                        }
                    }
                    .glassEffect(
                        .regular.tint(Palette.glassTint).interactive(),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

// MARK: - Listening pulse rings

/// Two neutral rings expanding from the companion disc while the call
/// is listening — plain stroked circles, no blur, monochrome.
private struct PulseRings: View {
    let diameter: CGFloat
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .strokeBorder(Color.white.opacity(animate ? 0 : 0.32), lineWidth: 1.5)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(animate ? 1.4 : 1.0)
                    .animation(
                        .easeOut(duration: 1.9)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.95),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Call controller

/// Owns the call state machine: transport choice (Live vs. pipeline),
/// the Live retry cascade (configured model → native-audio fallback
/// model → pipeline), the one silent reconnect, the pipeline loop,
/// the call timer, and the audio-session route (speaker / earpiece).
@MainActor
final class CallController: ObservableObject {
    enum Activity {
        case connecting
        case listening
        case thinking
        case speaking
    }

    private enum Transport {
        case undecided
        case live
        case fallback
    }

    @Published private(set) var activity: Activity = .connecting
    @Published private(set) var caption = ""
    @Published private(set) var note: String?
    @Published private(set) var noteNeedsSettings = false
    @Published private(set) var banner: String?
    @Published private(set) var isSpeakingAloud = false
    @Published var isMuted = false
    @Published var speakerOn = true

    private var transport: Transport = .undecided
    @Published private(set) var transportName = ""
    @Published private(set) var elapsedSeconds = 0
    private var timerTask: Task<Void, Never>?

    private weak var store: AppStore?
    private var dismissAction: (() -> Void)?
    private var callActive = false
    private var generation = 0

    private let liveEngine = GeminiLiveEngine()
    private let pipeline = PipelineVoiceEngine()
    private var cancellables = Set<AnyCancellable>()

    // Live retry cascade state
    private var currentLiveModel = ""
    private var triedLiveFallbackModel = false
    private var reconnectAttempted = false

    // Fallback loop state
    private var awaitingReply = false
    private var baselineAssistantCount = 0

    /// Fallback read-aloud switch (persisted; the pipeline honors the
    /// stored value — with it off, replies show as caption text and
    /// the loop re-listens as soon as a reply lands).
    private var autoSpeak: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "call.autoSpeak") == nil { return true }
            return defaults.bool(forKey: "call.autoSpeak")
        }
        set { UserDefaults.standard.set(newValue, forKey: "call.autoSpeak") }
    }

    // MARK: Derived UI state

    var statusText: String {
        if note != nil { return "Hinweis" }
        switch activity {
        case .connecting: return "Verbinde …"
        case .listening: return isMuted ? "Mikrofon aus" : "Hört zu …"
        case .thinking: return "Denkt nach …"
        case .speaking: return "Spricht …"
        }
    }

    var transportTimerText: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        let time = String(format: "%02d:%02d", minutes, seconds)
        return transportName.isEmpty ? time : "\(transportName) · \(time)"
    }

    var isListeningActivity: Bool {
        activity == .listening && !isMuted && note == nil
    }

    // MARK: Start

    func start(store: AppStore, dismiss: @escaping () -> Void) {
        guard !callActive else { return }
        self.store = store
        dismissAction = dismiss
        callActive = true
        generation += 1
        reconnectAttempted = false
        triedLiveFallbackModel = false

        applyAudioSession()
        observeLiveSpeaking()
        observeStoreMessages()

        let gen = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            let micOK = await VoicePermissions.requestMicrophone()
            guard self.callActive, self.generation == gen else { return }
            guard micOK else {
                self.note = "Ohne Mikrofon kann Nova dich nicht hören. Erlaube den Zugriff in den iPhone-Einstellungen — dann klappt auch das Telefonieren."
                self.noteNeedsSettings = true
                return
            }
            self.beginTransports()
        }
    }

    private func beginTransports() {
        guard let store else { return }
        if store.hasKey {
            // Own key (admin build — or a key stored by an older
            // version): direct Live for Gemini, pipeline otherwise.
            if store.engineMode == .apiKey, store.provider == .gemini {
                startLive(model: store.liveModel())
            } else {
                startFallback()
            }
        } else if store.proxyEligible {
            // Nova v3.0.0: no key on this install — the call runs on
            // a short-lived Live token minted by the backend.
            startLiveViaProxy(model: store.liveModel())
        } else {
            startFallback()
        }
    }

    // MARK: Live transport

    /// How the current Live session authenticates — the retry
    /// cascade needs to know: a key can simply reconnect, an
    /// ephemeral token is single-use and must be re-minted first.
    private enum LiveAuth {
        case key
        case proxyToken(String)
    }

    private var liveAuth: LiveAuth?

    private func startLive(model: String) {
        liveAuth = .key
        beginLive(model: model)
    }

    /// Fetches a fresh ephemeral token from the backend, then starts
    /// Live with it. Any failure lands in the pipeline fallback —
    /// the same graceful path as a failed direct setup.
    private func startLiveViaProxy(model: String) {
        guard callActive, let store else { return }
        transport = .live
        activity = .connecting
        let gen = generation
        let installID = store.installID
        Task { @MainActor [weak self] in
            let token = await BackendAI.liveToken(installID: installID)
            guard let self, self.callActive, self.generation == gen else { return }
            guard let token else {
                self.startFallback()
                return
            }
            self.liveAuth = .proxyToken(token)
            self.beginLive(model: model)
        }
    }

    /// Re-runs a Live attempt (fallback model / the one reconnect)
    /// through whichever auth path the session started with.
    private func retryLive(model: String) {
        if case .proxyToken = liveAuth {
            startLiveViaProxy(model: model)
        } else {
            startLive(model: model)
        }
    }

    private func beginLive(model: String) {
        guard callActive, let store, let liveAuth else { return }
        transport = .live
        currentLiveModel = model
        activity = .connecting

        liveEngine.onConnected = { [weak self] in
            guard let self, self.callActive else { return }
            self.transportName = "Live"
            self.activity = .listening
            self.startTimerIfNeeded()
        }
        liveEngine.onSetupFailure = { [weak self] _ in
            guard let self, self.callActive else { return }
            if !self.triedLiveFallbackModel,
               model != APIProvider.fallbackGeminiLiveModel {
                self.triedLiveFallbackModel = true
                self.retryLive(model: APIProvider.fallbackGeminiLiveModel)
            } else {
                self.showBanner("Live nicht verfügbar — Standard-Modus")
                self.startFallback()
            }
        }
        liveEngine.onEnded = { [weak self] in
            guard let self, self.callActive else { return }
            if !self.reconnectAttempted {
                self.reconnectAttempted = true
                self.retryLive(model: self.currentLiveModel)
            } else {
                self.endCallWithNote("Die Verbindung ist abgebrochen — der Anruf wird beendet.")
            }
        }
        liveEngine.onUserTranscript = { [weak self] text in
            self?.store?.appendCallTranscript(role: .user, text: text)
        }
        liveEngine.onAssistantTranscript = { [weak self] text in
            self?.store?.appendCallTranscript(role: .assistant, text: text)
        }
        liveEngine.onUserCaption = { [weak self] text in
            guard let self, self.callActive else { return }
            self.caption = text
        }
        liveEngine.onAssistantCaption = { [weak self] text in
            guard let self, self.callActive else { return }
            self.caption = text
        }
        liveEngine.onInterrupted = { [weak self] in
            guard let self, self.callActive else { return }
            if self.activity == .speaking {
                self.activity = .listening
            }
        }

        let instruction = Persona.systemPrompt(profile: store.profile)
            + " Du bist gerade in einem Live-Telefonat: Antworte auf Deutsch, kurz und gesprächig — ein bis drei Sätze, wie in einem echten Gespräch."
        switch liveAuth {
        case .key:
            liveEngine.start(apiKey: store.activeKey, model: model, systemInstruction: instruction)
        case .proxyToken(let token):
            liveEngine.startWithToken(token, model: model, systemInstruction: instruction)
        }
    }

    private func observeLiveSpeaking() {
        liveEngine.$isModelSpeaking
            .sink { [weak self] speaking in
                Task { @MainActor [weak self] in
                    guard let self, self.callActive, self.transport == .live else { return }
                    self.activity = speaking ? .speaking : .listening
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Fallback transport (pipeline loop)

    private func startFallback() {
        guard callActive else { return }
        transport = .fallback
        liveEngine.stop()
        activity = .connecting

        let gen = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            let speechOK = await VoicePermissions.requestSpeechRecognition()
            guard self.callActive, self.generation == gen else { return }
            guard speechOK else {
                self.note = "Im Standard-Modus brauche ich die Spracherkennung, um dich zu verstehen. Erlaube sie in den iPhone-Einstellungen."
                self.noteNeedsSettings = true
                return
            }
            guard self.pipeline.recognitionAvailable else {
                self.note = "Die Spracherkennung ist auf diesem iPhone gerade nicht verfügbar (kein Netz und kein lokales Modell). Versuch es später nochmal."
                return
            }
            self.transportName = "Standard-Modus"
            self.startTimerIfNeeded()
            self.beginListeningTurn()
        }
    }

    private func beginListeningTurn() {
        guard callActive, transport == .fallback, note == nil else { return }
        activity = .listening
        guard !isMuted else { return }

        let gen = generation
        pipeline.startListening(
            onFinal: { [weak self] text in
                guard let self, self.callActive, self.generation == gen else { return }
                self.sendFallback(text)
            },
            onEmpty: { [weak self] in
                guard let self, self.callActive, self.generation == gen else { return }
                self.caption = "Ich hab nichts verstanden …"
                self.beginListeningTurn()
            },
            onUnavailable: { [weak self] in
                guard let self, self.callActive, self.generation == gen else { return }
                self.note = "Die Spracherkennung ist gerade nicht verfügbar. Versuch es in einem Moment nochmal."
            }
        )
    }

    private func sendFallback(_ text: String) {
        guard let store, callActive else { return }
        caption = text
        activity = .thinking
        baselineAssistantCount = store.messages.filter { $0.role == .assistant }.count
        awaitingReply = true
        store.sendUserMessage(text)
    }

    private func observeStoreMessages() {
        store?.$messages
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.checkForReply()
                }
            }
            .store(in: &cancellables)
    }

    private func checkForReply() {
        guard callActive, transport == .fallback, awaitingReply, let store else { return }
        let assistants = store.messages.filter { $0.role == .assistant }
        guard assistants.count > baselineAssistantCount else { return }
        awaitingReply = false
        let reply = assistants[baselineAssistantCount].text
        Haptics.light()
        handleFallbackReply(reply)
    }

    private func handleFallbackReply(_ reply: String) {
        let gen = generation
        if CallErrorNotes.isErrorNote(reply) {
            caption = ""
            if autoSpeak {
                speakLine("Das hat leider nicht geklappt.", gen: gen)
            } else {
                beginListeningTurn()
            }
            return
        }
        caption = reply
        if autoSpeak {
            speakLine(reply, gen: gen)
        } else {
            beginListeningTurn()
        }
    }

    private func speakLine(_ text: String, gen: Int) {
        activity = .speaking
        isSpeakingAloud = true
        pipeline.speak(text) { [weak self] in
            guard let self else { return }
            self.isSpeakingAloud = false
            guard self.callActive, self.generation == gen else { return }
            self.beginListeningTurn()
        }
    }

    func stopSpeakingNow() {
        pipeline.stopSpeaking()
    }

    // MARK: Controls

    func toggleMute() {
        isMuted.toggle()
        switch transport {
        case .live:
            liveEngine.setMuted(isMuted)
        case .fallback:
            if isMuted {
                pipeline.stopListening(deliver: false)
            } else if activity == .listening, !pipeline.isListening {
                beginListeningTurn()
            }
        case .undecided:
            break
        }
    }

    func toggleSpeaker() {
        speakerOn.toggle()
        applyAudioSession()
    }

    /// Hangs up (also the "Tastatur" button: leaves the call for the
    /// chat, where the exchange is logged as normal messages).
    func endCall() {
        teardown()
        dismissAction?()
    }

    private func endCallWithNote(_ text: String) {
        note = text
        noteNeedsSettings = false
        let gen = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard let self, self.callActive, self.generation == gen else { return }
            self.endCall()
        }
    }

    /// Full cleanup; safe to call twice (end button + onDisappear).
    func teardown() {
        guard callActive else { return }
        callActive = false
        generation += 1
        timerTask?.cancel()
        timerTask = nil
        liveEngine.stop()
        pipeline.teardown()
        cancellables.removeAll()
        deactivateAudioSession()
    }

    // MARK: Helpers

    private func showBanner(_ text: String) {
        banner = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self, self.banner == text else { return }
            self.banner = nil
        }
    }

    private func startTimerIfNeeded() {
        guard timerTask == nil else { return }
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.callActive else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    private func applyAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
        try? session.overrideOutputAudioPort(speakerOn ? .speaker : .none)
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(.none)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
