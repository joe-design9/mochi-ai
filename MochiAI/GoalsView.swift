import SwiftUI

/// Goals tab: expandable goal cards with a monochrome progress ring and
/// step checkboxes — Liquid Glass cards on the black backdrop.
struct GoalsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var expandedID: UUID?
    @State private var showingNewGoal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        ScreenTitle(text: "Ziele")
                        Text("Kleine Schritte, sichtbarer Fortschritt.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                    Button {
                        showingNewGoal = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Neues Ziel")
                        }
                        .accentCapsule()
                    }
                    .buttonStyle(.plain)
                }

                if store.goals.isEmpty {
                    Card {
                        Text("Noch keine Ziele — leg oben dein erstes an.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
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
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .sheet(isPresented: $showingNewGoal) {
            NewGoalSheet()
        }
    }

    private func goalCard(_ goal: GoalItem) -> some View {
        let expanded = expandedID == goal.id
        return Card {
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
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.leading)
                            Text("\(goal.doneCount) von \(goal.steps.count) Schritten geschafft")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.secondaryText)
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
                                        .foregroundStyle(step.done ? Palette.accent : Palette.secondaryText)
                                    Text(step.title)
                                        .font(.subheadline)
                                        .foregroundStyle(step.done ? Palette.secondaryText : Palette.ink)
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
                            .foregroundStyle(Palette.danger)
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
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(text: "Neues Ziel")
                    FieldLabel(text: "Ziel")
                    TextField("z. B. GTA 6 auf 100 % spielen", text: $title)
                        .focused($isFieldFocused)
                        .appField()
                    FieldLabel(text: "Schritte (einer pro Zeile)")
                    TextField("Schritt 1\nSchritt 2\nSchritt 3", text: $stepsText, axis: .vertical)
                        .focused($isFieldFocused)
                        .lineLimit(4...8)
                        .appField()
                    Button("Ziel speichern") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
                        guard !trimmedTitle.isEmpty else { return }
                        isFieldFocused = false
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
                    .accentBlock()
                    .buttonStyle(.plain)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                    Button("Abbrechen") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { isFieldFocused = false }
                    .font(.body.weight(.semibold))
                    .tint(Palette.accent)
            }
        }
    }
}
