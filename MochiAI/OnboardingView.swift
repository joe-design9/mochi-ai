import SwiftUI

/// First-launch flow: Muse (with the companion) introduces itself, asks four
/// questions one at a time (chips + free text), shows a "what I learned"
/// summary, and ends with an optional provider-connect step that can
/// always be skipped. Warm paper design — serif title, flat cards.
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore

    private struct Question {
        let title: String
        let placeholder: String
        let chips: [String]
    }

    private let questions: [Question] = [
        Question(title: "Wie heißt du?",
                 placeholder: "Dein Name",
                 chips: []),
        Question(title: "Wie entspannst du am liebsten nach einem vollen Tag?",
                 placeholder: "z. B. Serien, Zocken, Musik …",
                 chips: ["Serien schauen", "Zocken", "Musik hören", "Spazieren gehen"]),
        Question(title: "Welches Hobby lässt dich die Zeit vergessen?",
                 placeholder: "z. B. Gaming, Sport, Kochen …",
                 chips: ["Gaming", "Sport", "Kochen", "Musik machen"]),
        Question(title: "Wenn du dich jetzt irgendwohin teleportieren könntest — wohin?",
                 placeholder: "z. B. Tokio, ans Meer, nach Leonida …",
                 chips: ["Vice City", "Tokio", "Ans Meer", "In die Berge"]),
    ]

    /// 0–3 questions, 4 summary, 5 connect step.
    @State private var step = 0
    @State private var answers = ["", "", "", ""]
    @State private var connectProvider: APIProvider = .gemini
    @State private var keyDraft = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                if step < questions.count {
                    questionCard(questions[step], index: step)
                } else if step == questions.count {
                    summaryCard
                } else {
                    connectCard
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { isFieldFocused = false }
                    .font(.body.weight(.semibold))
                    .tint(Palette.accent)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            CompanionView(character: store.companion, size: 96)
            Text("Hi, ich bin Muse")
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(Palette.ink)
            Text("Deine persönliche KI — ich laufe direkt hier auf deinem iPhone. Lass uns kurz einrichten, wer du bist. Dauert keine Minute.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Question step

    private func questionCard(_ question: Question, index: Int) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                FieldLabel(text: "Frage \(index + 1) von \(questions.count)")
                Text(question.title)
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(Palette.ink)

                if !question.chips.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(question.chips, id: \.self) { chip in
                            let selected = answers[index] == chip
                            Button {
                                answers[index] = chip
                            } label: {
                                Text(chip)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(selected ? .white : Palette.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        Capsule().fill(selected ? Palette.accent : Palette.subtleFill)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField(question.placeholder, text: $answers[index])
                    .focused($isFieldFocused)
                    .appField()
                    .autocorrectionDisabled()

                HStack {
                    if index > 0 {
                        Button("Zurück") {
                            isFieldFocused = false
                            withAnimation { step -= 1 }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                    Button("Weiter") {
                        isFieldFocused = false
                        withAnimation { step += 1 }
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Palette.accent))
                    .buttonStyle(.plain)
                    .disabled(answers[index].trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(answers[index].trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                }
            }
        }
    }

    // MARK: Summary step

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Das habe ich über dich gelernt:")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(Palette.ink)
                summaryRow(icon: "person.fill", label: "Name", value: answers[0])
                summaryRow(icon: "moon.stars.fill", label: "Entspannung", value: answers[1])
                summaryRow(icon: "heart.fill", label: "Hobby", value: answers[2])
                summaryRow(icon: "airplane", label: "Teleport-Ziel", value: answers[3])
                Text("Stimmt so? Dann geht's los — ein optionaler Schritt wartet noch.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
                Button("Los geht's") {
                    withAnimation { step = questions.count + 1 }
                }
                .accentBlock()
                .buttonStyle(.plain)
            }
        }
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondaryText)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }
            Spacer()
        }
    }

    // MARK: Optional connect step

    private var connectCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Großes Modell verbinden")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text("Optional: Mit einem eigenen API-Key rede ich mit einem großen Modell statt im Demo-Modus. Ohne Key ist auch alles gut — dann bleibe ich lokal auf deinem iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)

                FieldLabel(text: "Anbieter")
                Picker("Anbieter", selection: $connectProvider) {
                    ForEach(APIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.accent)
                .labelsHidden()

                FieldLabel(text: "API Key")
                SecureField("API Key einfügen", text: $keyDraft)
                    .focused($isFieldFocused)
                    .appField()
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(connectProvider.keyHint)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)

                Text("Adresse und Modell kannst du später jederzeit in der Bibliothek unter „Einstellungen“ anpassen — dort gibt es auch einen „Verbindung testen“-Knopf.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)

                Button("Verbinden") {
                    isFieldFocused = false
                    store.provider = connectProvider
                    if !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        store.setKey(keyDraft, for: connectProvider)
                    }
                    finish()
                }
                .accentBlock()
                .buttonStyle(.plain)

                Button("Später") {
                    isFieldFocused = false
                    store.provider = connectProvider
                    finish()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.secondaryText)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
    }

    private func finish() {
        store.profile = UserProfile(
            name: answers[0].trimmingCharacters(in: .whitespaces),
            relax: answers[1].trimmingCharacters(in: .whitespaces),
            hobby: answers[2].trimmingCharacters(in: .whitespaces),
            teleport: answers[3].trimmingCharacters(in: .whitespaces)
        )
        // No seeded greeting message anymore: the chat's empty state greets
        // with the large companion and suggestion chips instead.
        store.selectedTab = .chat
    }
}
