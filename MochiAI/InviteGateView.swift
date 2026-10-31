import SwiftUI

/// The invite gate — the FIRST screen of a fresh install of the
/// normal build (v2.4.0). Muse is built "für jeden", but access is
/// handed out personally: one MA code activates exactly one install.
///
/// Flow: the code's checksum is validated fully offline first
/// (InviteCode), then the redeem_invite RPC decides whether the
/// code exists and is still open. On success the store flips its
/// persisted activation flag and the root view moves on to the
/// onboarding — the gate never appears again on this install.
///
/// Failure honesty: a malformed code, a used/unknown code and a
/// connection problem are three DIFFERENT messages. Offline never
/// silently lets anyone in and never crashes — the same button is
/// the retry.
struct InviteGateView: View {
    @EnvironmentObject private var store: AppStore

    @State private var code = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                gateCard
                Text("Du hast noch keinen Code? Muse wird persönlich weitergegeben — frag einfach die Person, die dir von der App erzählt hat.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
    }

    // MARK: Header (mirrors the onboarding welcome)

    private var header: some View {
        VStack(spacing: 12) {
            CompanionGlow(character: store.companion, size: 96)
            Text("Hi, ich bin Muse")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.ink)
            Text("Deine persönliche KI — ich laufe direkt hier auf deinem iPhone. Damit wir loslegen können, aktiviere die App mit deinem Invite-Code.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Gate card

    private var gateCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                FieldLabel(text: "Invite-Code")
                TextField("MA-XXXXXX-XXXXXX", text: $code)
                    .focused($isFieldFocused)
                    .appField()
                    .font(.body.weight(.semibold).monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: code) { _, _ in
                        // Any edit clears the previous verdict — the
                        // UI must never argue with a stale error.
                        if errorText != nil { errorText = nil }
                    }
                    .onSubmit { activate() }

                if let errorText {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.danger)
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(Palette.ink)
                    }
                }

                Button {
                    activate()
                } label: {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Palette.primaryText)
                        }
                        Text(isBusy ? "Prüfe Code …" : "Aktivieren")
                    }
                    .accentBlock()
                }
                .buttonStyle(.plain)
                .disabled(isBusy || InviteCode.normalize(code).isEmpty)
                .opacity(InviteCode.normalize(code).isEmpty ? 0.45 : 1)
            }
        }
    }

    // MARK: Logic

    private func activate() {
        guard !isBusy else { return }
        let normalized = InviteCode.normalize(code)
        // Offline checksum first: typos are caught here, with no
        // network round-trip and no burned server state.
        guard InviteCode.isValid(normalized) else {
            errorText = "Der Code sieht nicht richtig aus — prüfe die Schreibweise. Das Format ist MA-XXXXXX-XXXXXX."
            return
        }
        isFieldFocused = false
        isBusy = true
        errorText = nil
        let installID = store.installID
        Task {
            do {
                let redeemed = try await InviteBackend.redeemInvite(
                    code: normalized,
                    installID: installID
                )
                isBusy = false
                if redeemed {
                    Haptics.light()
                    // RootView observes the flag and swaps this gate
                    // for the onboarding automatically.
                    store.markInviteActivated()
                } else {
                    errorText = "Dieser Code ist ungültig oder wurde schon eingelöst. Jeder Code aktiviert nur eine Installation."
                }
            } catch let error as InviteBackendError {
                isBusy = false
                errorText = error.german
            } catch {
                isBusy = false
                errorText = InviteBackendError.offline.german
            }
        }
    }
}
