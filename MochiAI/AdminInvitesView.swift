import SwiftUI
import UIKit

#if ADMIN_BUILD
/// ADMIN BUILD ONLY — the Invite-Codes section in the Bibliothek.
///
/// Joel hands Muse out personally: this section creates fresh MA
/// codes on the server (create_invite RPC), lists every code with
/// its live server state (list_invites RPC — offen / eingelöst),
/// copies a code on tap and shares it via the system sheet. What
/// stands here is the server truth, refreshed on appear and after
/// every creation; a failed load shows a retry state, never stale
/// silence.
///
/// The whole file is ADMIN_BUILD-gated: in the normal build it
/// compiles to nothing and the section simply does not exist.
struct AdminInvitesSection: View {
    private enum LoadState {
        case loading
        case loaded
        case failed(String)
    }

    @State private var rows: [InviteCodeRow] = []
    @State private var loadState: LoadState = .loading
    @State private var isCreating = false
    @State private var createError: String?
    @State private var copiedCode: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "Invite-Codes")
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Erstelle Codes und gib sie an Leute weiter, die Nova nutzen sollen. Jeder Code aktiviert genau eine Installation — was hier steht, ist der Stand auf dem Server.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)

                    Button {
                        Task { await createCode() }
                    } label: {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Palette.primaryText)
                            }
                            Text(isCreating ? "Erstelle …" : "Neuen Code erstellen")
                        }
                        .accentBlock()
                    }
                    .buttonStyle(.plain)
                    .disabled(isCreating)

                    if let createError {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Palette.danger)
                            Text(createError)
                                .font(.footnote)
                                .foregroundStyle(Palette.ink)
                        }
                    }

                    Divider().overlay(Palette.hairline)

                    listContent
                }
            }
        }
        .task { await load() }
    }

    // MARK: List states

    @ViewBuilder
    private var listContent: some View {
        switch loadState {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Lade Codes …")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                }
                Button {
                    Task { await load() }
                } label: {
                    Text("Erneut versuchen")
                        .hairlineCapsule()
                }
                .buttonStyle(.plain)
            }
        case .loaded:
            if rows.isEmpty {
                Text("Noch keine Codes erstellt. Der erste wartet oben auf dich.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            } else {
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        codeRow(row)
                    }
                }
            }
        }
    }

    private func codeRow(_ row: InviteCodeRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                UIPasteboard.general.string = row.code
                copiedCode = row.code
                Haptics.selection()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.code)
                        .font(.subheadline.weight(.semibold).monospaced())
                        .foregroundStyle(Palette.ink)
                    Text(subtitle(for: row))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                    if copiedCode == row.code {
                        Text("Kopiert ✓")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            statusChip(row)
            ShareLink(
                item: "Dein Nova-Invite-Code: \(row.code) — einfach beim ersten Start der App eingeben."
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Code teilen")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 16)
    }

    private func statusChip(_ row: InviteCodeRow) -> some View {
        Text(row.used ? "Eingelöst" : "Offen")
            .font(.caption2.weight(.bold))
            .foregroundStyle(row.used ? Palette.secondaryText : Palette.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassCapsuleBackground()
    }

    private func subtitle(for row: InviteCodeRow) -> String {
        if let usedAt = row.usedAt, row.used {
            return "Eingelöst am \(Self.dateFormatter.string(from: usedAt))"
        }
        return "Erstellt am \(Self.dateFormatter.string(from: row.createdAt))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        return formatter
    }()

    // MARK: Backend

    private func load() async {
        #if QA
        // QA screenshot seed (QAAdmin configuration only): two
        // local sample codes — one open, one used — so the capture
        // shows the section's real layout with zero network. The
        // codes are real-format MA codes (InviteCode.seededCode).
        if ProcessInfo.processInfo.arguments.contains("-QAAdminInvites") {
            rows = [
                InviteCodeRow(
                    code: InviteCode.seededCode(0),
                    used: false,
                    createdAt: Date().addingTimeInterval(-2 * 86_400),
                    usedAt: nil
                ),
                InviteCodeRow(
                    code: InviteCode.seededCode(1),
                    used: true,
                    createdAt: Date().addingTimeInterval(-5 * 86_400),
                    usedAt: Date().addingTimeInterval(-86_400)
                ),
            ]
            loadState = .loaded
            return
        }
        #endif
        loadState = .loading
        do {
            rows = try await InviteBackend.listInvites()
            loadState = .loaded
        } catch let error as InviteBackendError {
            loadState = .failed(error.german)
        } catch {
            loadState = .failed(InviteBackendError.offline.german)
        }
    }

    private func createCode() async {
        guard !isCreating else { return }
        isCreating = true
        createError = nil
        let code = InviteCode.generate()
        do {
            let inserted = try await InviteBackend.createInvite(code: code)
            isCreating = false
            if inserted {
                Haptics.light()
                copiedCode = nil
                // Reload from the server so the list stays the truth.
                await load()
            } else {
                createError = "Der Code konnte nicht erstellt werden (er existiert schon). Versuch es einfach noch einmal."
            }
        } catch let error as InviteBackendError {
            isCreating = false
            createError = error.german
        } catch {
            isCreating = false
            createError = InviteBackendError.offline.german
        }
    }
}
#endif
