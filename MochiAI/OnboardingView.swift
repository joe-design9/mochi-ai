import SwiftUI

/// First-launch flow: Muse introduces itself, asks four questions one at a
/// time (chips + free text), shows a "what I learned" summary, and ends with
/// an optional provider-connect step that can always be skipped.
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
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            OrbView(size: 92)
            Text("Hi, ich bin Muse")
                .font(.system(.largeTitle, design: .default).weight(.black))
                .foregroundStyle(.white)
            Text("Deine persönliche KI — ich laufe direkt hier auf deinem iPhone. Lass uns kurz einrichten, wer du bist. Dauert keine Minute.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Question step

    private func questionCard(_ question: Question, index: Int) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Frage \(index + 1) von \(questions.count)")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
                Text(question.title)
                    .font(.system(.title3, design: .default).weight(.bold))
                    .foregroundStyle(.white)

                if !question.chips.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(question.chips, id: \.self) { chip in
                            Button {
                                answers[index] = chip
                            } label: {
                                Text(chip)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(answers[index] == chip ? .white : .white.opacity(0.8))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        Capsule().fill(
                                            answers[index] == chip
                                                ? Color(red: 0.55, green: 0.38, blue: 0.95).opacity(0.75)
                                                : Color.white.opacity(0.10)
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField(question.placeholder, text: $answers[index])
                    .glassField()
                    .autocorrectionDisabled()

                HStack {
                    if index > 0 {
                        Button("Zurück") {
                            withAnimation { step -= 1 }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Button("Weiter") {
                        withAnimation { step += 1 }
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(red: 0.55, green: 0.38, blue: 0.95)))
                    .buttonStyle(.plain)
                    .disabled(answers[index].trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(answers[index].trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                }
            }
        }
    }

    // MARK: Summary step

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Das habe ich über dich gelernt:")
                    .font(.system(.title3, design: .default).weight(.bold))
                    .foregroundStyle(.white)
                summaryRow(icon: "person.fill", label: "Name", value: answers[0])
                summaryRow(icon: "moon.stars.fill", label: "Entspannung", value: answers[1])
                summaryRow(icon: "heart.fill", label: "Hobby", value: answers[2])
                summaryRow(icon: "airplane", label: "Teleport-Ziel", value: answers[3])
                Text("Stimmt so? Dann geht's los — ein optionaler Schritt wartet noch.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                Button("Los geht's") {
                    withAnimation { step = questions.count + 1 }
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color(red: 0.55, green: 0.38, blue: 0.95)))
                .buttonStyle(.plain)
            }
        }
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.accentText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
    }

    // MARK: Optional connect step

    private var connectCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Großes Modell verbinden")
                    .font(.system(.title3, design: .default).weight(.bold))
                    .foregroundStyle(.white)
                Text("Optional: Mit einem eigenen API-Key rede ich mit einem großen Modell statt im Demo-Modus. Ohne Key ist auch alles gut — dann bleibe ich lokal auf deinem iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))

                FieldLabel(text: "ANBIETER")
                Picker("Anbieter", selection: $connectProvider) {
                    ForEach(APIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.accentText)
                .labelsHidden()

                FieldLabel(text: "API KEY")
                SecureField("API Key einfügen", text: $keyDraft)
                    .glassField()
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(connectProvider.keyHint)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))

                Text("Adresse und Modell kannst du später jederzeit in der Bibliothek unter „Einstellungen“ anpassen.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))

                Button("Verbinden") {
                    store.provider = connectProvider
                    if !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        store.setKey(keyDraft, for: connectProvider)
                    }
                    finish()
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color(red: 0.55, green: 0.38, blue: 0.95)))
                .buttonStyle(.plain)

                Button("Später") {
                    store.provider = connectProvider
                    finish()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
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
        store.seedGreetingIfNeeded()
        store.selectedTab = .chat
    }
}
