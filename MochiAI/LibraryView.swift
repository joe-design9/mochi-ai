import SwiftUI

/// Library tab: companion picker, saved items, profile, and the KI
/// settings — a mode switch (API-Key vs. Apple KI on-device) at the top;
/// in API-Key mode the provider picker with per-provider key (Keychain),
/// API address and model fields plus a "Verbindung testen" button; in
/// Apple-KI mode the FoundationModels availability status.
struct LibraryView: View {
    @EnvironmentObject private var store: AppStore

    @State private var keyDraft = ""
    @State private var baseURLDraft = ""
    @State private var modelDraft = ""
    @State private var savedFlash = false

    @State private var isTesting = false
    @State private var testResult: TestResult?

    /// Drafts are loaded ONCE (not on every tab re-appearance — that used
    /// to silently wipe unsaved edits and test results).
    @State private var didLoadDrafts = false

    /// Shared focus for all settings text fields — drives the keyboard
    /// toolbar ("Fertig") so the keyboard can always be dismissed.
    @FocusState private var isFieldFocused: Bool

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenTitle(text: "Bibliothek")

                companionSection
                savedSection
                profileSection
                settingsSection
                resetSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { isFieldFocused = false }
                    .font(.body.weight(.semibold))
                    .tint(Palette.accent)
            }
        }
        .onAppear {
            if !didLoadDrafts {
                loadDrafts()
                didLoadDrafts = true
            }
        }
        .onChange(of: store.provider) { _, _ in
            loadDrafts()
            testResult = nil
        }
        // Any edit that diverges from the stored values invalidates the
        // "Gespeichert ✓" flash and a stale test result — the UI must
        // never claim a state that is no longer true.
        .onChange(of: keyDraft) { _, newValue in
            if newValue != store.key(for: store.provider) {
                savedFlash = false
                testResult = nil
            }
        }
        .onChange(of: baseURLDraft) { _, newValue in
            if newValue != store.baseURL(for: store.provider) {
                savedFlash = false
                testResult = nil
            }
        }
        .onChange(of: modelDraft) { _, newValue in
            if newValue != store.model(for: store.provider) {
                savedFlash = false
                testResult = nil
            }
        }
    }

    // MARK: Begleiter

    private var companionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "Begleiter")
            Card {
                HStack(spacing: 8) {
                    ForEach(CompanionID.allCases) { companion in
                        let selected = store.companion == companion
                        Button {
                            store.companion = companion
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    CompanionView(character: companion, size: 54)
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(Palette.accent)
                                            .background(Circle().fill(Palette.card))
                                            .offset(x: 3, y: -3)
                                    }
                                }
                                Text(companion.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selected ? Palette.ink : Palette.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selected ? Palette.subtleFill : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(selected ? Palette.accent : Palette.hairline,
                                                  lineWidth: selected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Dein Begleiter sitzt im Chat neben meinen Antworten — und hüpft, wenn ich antworte.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    // MARK: Gespeichert

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "Gespeichert")
            if store.savedItems.isEmpty {
                Card {
                    Text("Noch nichts gespeichert. Tippe im Feed oder bei den Ideen auf ein Lesezeichen — dann landet es hier.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                }
            } else {
                ForEach(store.savedItems) { item in
                    Card(cornerRadius: 16) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.kind.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.0)
                                    .foregroundStyle(Palette.accent)
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.ink)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.secondaryText)
                                }
                            }
                            Spacer()
                            Button {
                                store.removeSaved(id: item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Profil

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "Dein Profil")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    if let profile = store.profile {
                        profileRow(label: "Name", value: profile.name)
                        profileRow(label: "Entspannung", value: profile.relax)
                        profileRow(label: "Hobby", value: profile.hobby)
                        profileRow(label: "Teleport-Ziel", value: profile.teleport)
                    } else {
                        Text("Noch kein Profil angelegt.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
        }
    }

    private func profileRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Spacer()
        }
    }

    // MARK: Einstellungen

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "Einstellungen")
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "KI-Modus")
                    Picker("KI-Modus", selection: engineModeBinding) {
                        ForEach(EngineMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if store.engineMode == .appleIntelligence {
                        appleModeSection
                    } else {
                    FieldLabel(text: "Anbieter")
                    Picker("Anbieter", selection: providerBinding) {
                        ForEach(APIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.accent)
                    .labelsHidden()

                    FieldLabel(text: "API Key")
                    SecureField("Key einfügen", text: $keyDraft)
                        .focused($isFieldFocused)
                        .appField()
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(store.provider.keyHint)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)

                    FieldLabel(text: "API-Adresse")
                    TextField(store.provider.baseURLPlaceholder, text: $baseURLDraft)
                        .focused($isFieldFocused)
                        .appField()
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    FieldLabel(text: "Modell")
                    TextField(store.provider.modelPlaceholder, text: $modelDraft)
                        .focused($isFieldFocused)
                        .appField()
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack(spacing: 10) {
                        Button {
                            store.setKey(keyDraft, for: store.provider)
                            store.setBaseURL(baseURLDraft, for: store.provider)
                            store.setModel(modelDraft, for: store.provider)
                            loadDrafts()
                            savedFlash = true
                            isFieldFocused = false
                        } label: {
                            Text(savedFlash ? "Gespeichert ✓" : "Speichern")
                                .accentCapsule()
                        }
                        .buttonStyle(.plain)

                        if store.hasKey {
                            Button(role: .destructive) {
                                keyDraft = ""
                                store.setKey("", for: store.provider)
                                savedFlash = false
                                testResult = nil
                                isFieldFocused = false
                            } label: {
                                Text("Key löschen")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.danger)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(Palette.subtleFill))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    Divider().overlay(Palette.hairline)

                    // Connection self-test — uses the values currently in
                    // the fields, so mistakes show up before saving.
                    Button {
                        runConnectionTest()
                    } label: {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(isTesting ? "Teste Verbindung …" : "Verbindung testen")
                        }
                        .hairlineCapsule()
                    }
                    .buttonStyle(.plain)
                    .disabled(isTesting)

                    if let testResult {
                        testResultView(testResult)
                    }

                    Text("Jeder Anbieter behält seinen eigenen Key — Wechseln löscht nichts.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                    }

                    Divider().overlay(Palette.hairline)
                    Text("Aktive Engine: \(store.engineCaption)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
        }
    }

    // MARK: Apple-KI mode

    /// Shown instead of the provider fields in Apple-KI mode: live
    /// availability of the on-device model plus the privacy one-liner.
    private var appleModeSection: some View {
        let availability = store.appleAvailability
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: availability.isAvailable
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(availability.isAvailable ? Palette.success : Palette.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text(availability.statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if !availability.isAvailable {
                        Text(availability.reasonText)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
            Text("Lokal auf deinem iPhone — kein Key, keine Cloud.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    private var engineModeBinding: Binding<EngineMode> {
        Binding(
            get: { store.engineMode },
            set: { store.engineMode = $0 }
        )
    }

    @ViewBuilder
    private func testResultView(_ result: TestResult) -> some View {
        switch result {
        case .success(let reply):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success)
                Text("Verbindung OK — der Anbieter antwortet: „\(reply)“")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink)
            }
        case .failure(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Das meldet der Anbieter:")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
    }

    private func runConnectionTest() {
        isFieldFocused = false
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            testResult = .failure("Kein API-Key eingetragen — füge oben zuerst einen Key ein.")
            return
        }
        var base = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = store.provider.defaultBaseURL }
        var model = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty { model = store.provider.defaultModel }

        let config = EngineConfig(
            provider: store.provider,
            key: key,
            baseURL: base,
            model: model,
            profile: store.profile
        )
        isTesting = true
        testResult = nil
        Task {
            let result = await APIClient.testConnection(config: config)
            isTesting = false
            switch result {
            case .success(let reply): testResult = .success(reply)
            case .failure(let failure): testResult = .failure(failure.message)
            }
        }
    }

    private var providerBinding: Binding<APIProvider> {
        Binding(
            get: { store.provider },
            set: { store.provider = $0 }
        )
    }

    // MARK: Reset & About

    private var resetSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Neu starten")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text("Setzt dein Profil zurück und startet das Onboarding neu. Gespeicherte Inhalte, Ideen und Ziele bleiben erhalten.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
                Button("Onboarding zurücksetzen") {
                    store.resetOnboarding()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.danger)
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutSection: some View {
        Card {
            HStack(spacing: 14) {
                CompanionGlow(character: store.companion, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Muse")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Muse — deine persönliche KI. Läuft lokal auf deinem iPhone, keine Cloud nötig.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                    Text("Version \(AppInfo.version)")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
                Spacer()
            }
        }
    }

    // MARK: Helpers

    private func loadDrafts() {
        keyDraft = store.key(for: store.provider)
        baseURLDraft = store.baseURL(for: store.provider)
        modelDraft = store.model(for: store.provider)
        savedFlash = false
    }
}
