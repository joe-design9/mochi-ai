import SwiftUI

/// Library tab: saved items, profile, and settings — provider picker with
/// per-provider key (Keychain), API address and model fields.
struct LibraryView: View {
    @EnvironmentObject private var store: AppStore

    @State private var keyDraft = ""
    @State private var baseURLDraft = ""
    @State private var modelDraft = ""
    @State private var savedFlash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionTitle(text: "Bibliothek")

                savedSection
                profileSection
                settingsSection
                resetSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 120)
        }
        .onAppear { loadDrafts() }
        .onChange(of: store.provider) { _, _ in
            loadDrafts()
        }
    }

    // MARK: Gespeichert

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Gespeichert")
            if store.savedItems.isEmpty {
                GlassCard {
                    Text("Noch nichts gespeichert. Tippe im Feed oder bei den Ideen auf ein Lesezeichen — dann landet es hier.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
            } else {
                ForEach(store.savedItems) { item in
                    GlassCard(cornerRadius: 20) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.kind.uppercased())
                                    .font(.caption2.weight(.black))
                                    .tracking(1.0)
                                    .foregroundStyle(Palette.accentText)
                                Text(item.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            Spacer()
                            Button {
                                store.removeSaved(id: item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.5))
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
            sectionHeader("Dein Profil")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    if let profile = store.profile {
                        profileRow(label: "Name", value: profile.name)
                        profileRow(label: "Entspannung", value: profile.relax)
                        profileRow(label: "Hobby", value: profile.hobby)
                        profileRow(label: "Teleport-Ziel", value: profile.teleport)
                    } else {
                        Text("Noch kein Profil angelegt.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
        }
    }

    private func profileRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
        }
    }

    // MARK: Einstellungen

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Einstellungen")
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "ANBIETER")
                    Picker("Anbieter", selection: providerBinding) {
                        ForEach(APIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.accentText)
                    .labelsHidden()

                    FieldLabel(text: "API KEY")
                    SecureField("Key einfügen", text: $keyDraft)
                        .glassField()
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(store.provider.keyHint)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.65))

                    FieldLabel(text: "API-ADRESSE")
                    TextField(store.provider.baseURLPlaceholder, text: $baseURLDraft)
                        .glassField()
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    FieldLabel(text: "MODELL")
                    TextField(store.provider.modelPlaceholder, text: $modelDraft)
                        .glassField()
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack(spacing: 10) {
                        Button {
                            store.setKey(keyDraft, for: store.provider)
                            store.setBaseURL(baseURLDraft, for: store.provider)
                            store.setModel(modelDraft, for: store.provider)
                            loadDrafts()
                            savedFlash = true
                        } label: {
                            Text(savedFlash ? "Gespeichert ✓" : "Speichern")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color(red: 0.55, green: 0.38, blue: 0.95)))
                        }
                        .buttonStyle(.plain)

                        if store.hasKey {
                            Button(role: .destructive) {
                                keyDraft = ""
                                store.setKey("", for: store.provider)
                                savedFlash = false
                            } label: {
                                Text("Key löschen")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(Color.white.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    Divider().overlay(Color.white.opacity(0.15))
                    Text("Aktive Engine: \(store.engineCaption)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Jeder Anbieter behält seinen eigenen Key — Wechseln löscht nichts.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                }
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
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Neu starten")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Setzt dein Profil zurück und startet das Onboarding neu. Gespeicherte Inhalte, Ideen und Ziele bleiben erhalten.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                Button("Onboarding zurücksetzen") {
                    store.resetOnboarding()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(red: 1.0, green: 0.60, blue: 0.60))
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutSection: some View {
        GlassCard {
            HStack(spacing: 14) {
                OrbView(size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Muse")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Muse — deine persönliche KI. Läuft lokal auf deinem iPhone, keine Cloud nötig.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
            }
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.title3, design: .default).weight(.black))
            .foregroundStyle(.white)
    }

    private func loadDrafts() {
        keyDraft = store.key(for: store.provider)
        baseURLDraft = store.baseURL(for: store.provider)
        modelDraft = store.model(for: store.provider)
        savedFlash = false
    }
}
