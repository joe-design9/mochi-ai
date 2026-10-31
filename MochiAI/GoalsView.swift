import SwiftUI

/// Goals tab: expandable goal cards with a progress ring and step checkboxes.
struct GoalsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var expandedID: UUID?
    @State private var showingNewGoal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle(text: "Ziele")
                        Text("Kleine Schritte, sichtbarer Fortschritt.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Button {
                        showingNewGoal = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Neues Ziel")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if store.goals.isEmpty {
                    GlassCard {
                        Text("Noch keine Ziele — leg oben dein erstes an.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(store.goals) { goal in
                        goalCard(goal)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showingNewGoal) {
            NewGoalSheet()
        }
    }

    private func goalCard(_ goal: GoalItem) -> some View {
        let expanded = expandedID == goal.id
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedID = expanded ? nil : goal.id
                    }
                } label: {
                    HStack(spacing: 14) {
                        ProgressRing(progress: goal.progress)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(goal.title)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                            Text("\(goal.doneCount) von \(goal.steps.count) Schritten geschafft")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(goal.steps) { step in
                            Button {
                                toggleStep(goal: goal, step: step)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: step.done ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 19))
                                        .foregroundStyle(step.done ? Color(red: 0.45, green: 0.90, blue: 0.55) : .white.opacity(0.6))
                                    Text(step.title)
                                        .font(.subheadline)
                                        .foregroundStyle(step.done ? .white.opacity(0.5) : .white)
                                        .strikethrough(step.done)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }

                        Button(role: .destructive) {
                            store.goals.removeAll { $0.id == goal.id }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Ziel löschen")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func toggleStep(goal: GoalItem, step: GoalStep) {
        guard let goalIndex = store.goals.firstIndex(where: { $0.id == goal.id }),
              let stepIndex = store.goals[goalIndex].steps.firstIndex(where: { $0.id == step.id }) else {
            return
        }
        store.goals[goalIndex].steps[stepIndex].done.toggle()
    }
}

// MARK: - New goal sheet

struct NewGoalSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var stepsText = ""

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Neues Ziel")
                        .font(.system(.title2, design: .default).weight(.black))
                        .foregroundStyle(.white)
                    FieldLabel(text: "ZIEL")
                    TextField("z. B. GTA 6 auf 100 % spielen", text: $title)
                        .glassField()
                    FieldLabel(text: "SCHRITTE (EINER PRO ZEILE)")
                    TextField("Schritt 1\nSchritt 2\nSchritt 3", text: $stepsText, axis: .vertical)
                        .lineLimit(4...8)
                        .glassField()
                    Button("Ziel speichern") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
                        guard !trimmedTitle.isEmpty else { return }
                        var steps = stepsText
                            .split(separator: "\n")
                            .map { GoalStep(title: $0.trimmingCharacters(in: .whitespaces)) }
                            .filter { !$0.title.isEmpty }
                        if steps.isEmpty {
                            steps = [GoalStep(title: "Einfach anfangen")]
                        }
                        store.goals.append(GoalItem(title: trimmedTitle, steps: steps))
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color(red: 0.55, green: 0.38, blue: 0.95)))
                    .buttonStyle(.plain)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                    Button("Abbrechen") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }
}
