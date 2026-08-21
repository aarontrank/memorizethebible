import BibleCore
import SwiftUI

/// Memory plans: the ones that ship with the app, and the user's own.
struct PlanListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List {
            Section {
                ForEach(builtIn) { plan in
                    NavigationLink(value: Route.plan(plan.id)) { row(plan) }
                        .listRowBackground(Palette.background)
                }
            } header: {
                Text("Plans")
            } footer: {
                Text("A plan is a set of verses memorized together. Learning a verse in a plan also counts toward its chapter.")
            }

            Section("Your plans") {
                ForEach(custom) { plan in
                    NavigationLink(value: Route.plan(plan.id)) { row(plan) }
                        .listRowBackground(Palette.background)
                }
                if custom.isEmpty {
                    Text("None yet.")
                        .font(Typography.chrome(.footnote))
                        .foregroundStyle(Palette.dimmedText)
                        .listRowBackground(Palette.background)
                }
                NavigationLink(value: Route.newPlan) {
                    Label("New plan", systemImage: "plus")
                        .font(Typography.chrome(.body))
                }
                .listRowBackground(Palette.background)
            }

            if !state.progress.hiddenBuiltInPlans.isEmpty {
                Section {
                    Button("Restore hidden plans") { state.restoreHiddenPlans() }
                        .listRowBackground(Palette.background)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var builtIn: [MemoryPlan] { state.plans.filter(\.isBuiltIn) }
    private var custom: [MemoryPlan] { state.plans.filter { !$0.isBuiltIn } }

    private func row(_ plan: MemoryPlan) -> some View {
        let progress = state.planProgress(plan)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(plan.title)
                        .font(Typography.scripture(.body))
                        .foregroundStyle(Palette.text)
                    if progress.isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.dimmedText)
                    }
                }
                Text(subtitle(plan: plan, progress: progress))
                    .font(Typography.chrome(.caption))
                    .foregroundStyle(Palette.dimmedText)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            if progress.isStarted && !progress.isComplete {
                ProgressBar(fraction: progress.fraction, height: 4).frame(width: 44)
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(plan: MemoryPlan, progress: PlanProgress) -> String {
        if progress.isComplete { return "Memorized · tap to review" }
        if progress.isStarted { return "\(progress.masteredCount) of \(progress.unitCount) verses" }
        let count = progress.unitCount
        let noun = count == 1 ? "verse" : "verses"
        return plan.summary.isEmpty ? "\(count) \(noun)" : "\(count) \(noun) · \(plan.summary)"
    }
}
