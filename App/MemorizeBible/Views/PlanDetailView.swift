import BibleCore
import SwiftUI

/// One plan: what it holds, how far through it you are, and the way in.
struct PlanDetailView: View {
    let planID: String

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemoval = false

    private var plan: MemoryPlan? { state.plan(id: planID) }

    var body: some View {
        Group {
            if let plan {
                content(plan: plan)
            } else {
                Text("This plan is no longer available.")
                    .font(Typography.chrome(.subheadline))
                    .foregroundStyle(Palette.dimmedText)
            }
        }
        .navigationTitle(plan?.title ?? "Plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(plan: MemoryPlan) -> some View {
        let progress = state.planProgress(plan)
        let target = state.target(forPlan: plan)

        List {
            Section {
                if !plan.summary.isEmpty {
                    Text(plan.summary)
                        .font(Typography.chrome(.subheadline))
                        .foregroundStyle(Palette.dimmedText)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ProgressBar(fraction: progress.fraction)
                    Text(caption(progress))
                        .font(Typography.chrome(.footnote))
                        .foregroundStyle(Palette.dimmedText)
                }
                .padding(.vertical, 4)

                NavigationLink(value: progress.isComplete ? Route.review(.plan(plan.id)) : Route.session(.plan(plan.id))) {
                    Text(progress.isComplete ? "Review this plan" : progress.isStarted ? "Continue" : "Start")
                        .font(Typography.chrome(.headline))
                        .foregroundStyle(Palette.text)
                }
            }
            .listRowBackground(Palette.background)

            ForEach(Array(plan.sections.enumerated()), id: \.element.id) { _, section in
                Section(plan.sections.count > 1 ? section.title : "Verses") {
                    ForEach(section.passages, id: \.self) { passage in
                        passageRow(passage, target: target)
                    }
                    .listRowBackground(Palette.background)
                }
            }

            Section {
                if !plan.isBuiltIn {
                    NavigationLink(value: Route.editPlan(plan.id)) { Text("Edit plan") }
                        .listRowBackground(Palette.background)
                }
                Button(plan.isBuiltIn ? "Hide this plan" : "Delete this plan", role: .destructive) {
                    confirmingRemoval = true
                }
                .listRowBackground(Palette.background)
            } footer: {
                Text("Removing a plan keeps every verse you have memorized — the verses belong to their chapters, not to the plan.")
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(
            plan.isBuiltIn ? "Hide this plan?" : "Delete this plan?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(plan.isBuiltIn ? "Hide" : "Delete", role: .destructive) {
                state.removePlan(plan)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your memorized verses are not affected.")
        }
    }

    private func caption(_ progress: PlanProgress) -> String {
        if progress.isComplete { return "Memorized" }
        if progress.unitCount == 0 { return "This plan names no verses in this translation." }
        return "\(progress.masteredCount) of \(progress.unitCount) verses memorized"
    }

    private func passageRow(_ passage: PassageRef, target: MemoryTarget) -> some View {
        let refs = target.units.filter { $0.chapterRef == passage.chapterRef
            && $0.verse >= passage.firstVerse && $0.verse <= passage.lastVerse }
        let mastered = refs.filter { state.progress.state(for: $0).status == .mastered }.count
        return HStack {
            Text(state.content.manifest.title(for: passage))
                .font(Typography.scripture(.body))
                .foregroundStyle(Palette.text)
            Spacer()
            if !refs.isEmpty, mastered == refs.count {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.dimmedText)
            } else if !refs.isEmpty {
                Text("\(mastered)/\(refs.count)")
                    .font(Typography.chrome(.caption))
                    .foregroundStyle(Palette.dimmedText)
            }
        }
    }
}
