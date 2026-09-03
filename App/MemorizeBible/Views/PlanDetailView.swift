import BibleCore
import SwiftUI

/// One plan: what it holds, how far through it you are, and the way in.
///
/// Reading a plan commits to nothing (§8.1). Start memorizing is what puts it
/// on the home page, and until then it is just something you looked at.
struct PlanDetailView: View {
    let planID: String

    @Environment(AppState.self) private var state
    @Environment(Navigator.self) private var navigator
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
        .toolbar {
            if let plan {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Built-in plans are already on everyone's device, so
                        // there is nothing to send. One someone sent you can be
                        // passed on.
                        if !plan.isBuiltIn, let message = state.shareText(for: plan) {
                            ShareLink(item: message, subject: Text("Memorize the Bible with me")) {
                                Label("Share this plan", systemImage: "link")
                            }
                        }
                        ProgressShareLink(
                            content: .plan(plan, progress: state.planProgress(plan))
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
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
                if plan.origin == .shared {
                    Label("Shared with you", systemImage: "person.crop.circle")
                        .font(Typography.chrome(.footnote))
                        .foregroundStyle(Palette.dimmedText)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ProgressBar(fraction: progress.fraction)
                    Text(caption(progress))
                        .font(Typography.chrome(.footnote))
                        .foregroundStyle(Palette.dimmedText)
                }
                .padding(.vertical, 4)

                Button { open(plan: plan, progress: progress) } label: {
                    HStack {
                        Text(primaryTitle(plan: plan, progress: progress))
                            .font(Typography.chrome(.headline))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.verseNumber)
                    }
                }
                .tip(Walkthrough.planDetailTip(state: state, planID: plan.id), caret: .bottom)
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
                if canStop(plan: plan, progress: progress) {
                    Button("Stop memorizing this plan") { state.deactivatePlan(plan) }
                        .listRowBackground(Palette.background)
                }
                Button(plan.isBuiltIn ? "Hide this plan" : "Delete this plan", role: .destructive) {
                    confirmingRemoval = true
                }
                .listRowBackground(Palette.background)
            } footer: {
                Text(removalFooter(plan: plan, progress: progress))
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

    /// A finished plan has nothing to stop: it lives under Completed plans on
    /// the home page, and there is no work in hand to put down.
    private func canStop(plan: MemoryPlan, progress: PlanProgress) -> Bool {
        state.isActive(plan) && !progress.isComplete
    }

    private func removalFooter(plan: MemoryPlan, progress: PlanProgress) -> String {
        let removing = "Removing a plan keeps every verse you have memorized — the verses belong to their chapters, not to the plan."
        guard canStop(plan: plan, progress: progress) else { return removing }
        return "Stopping takes the plan off the home page and leaves it here, exactly as far along as you left it. \(removing)"
    }

    private func primaryTitle(plan: MemoryPlan, progress: PlanProgress) -> String {
        if progress.isComplete { return "Review this plan" }
        guard state.isActive(plan) else { return "Start memorizing" }
        // Coverage, not mastery: knowing these verses from somewhere else is
        // not work done inside this plan, and the session would open at the
        // first verse either way.
        return progress.coveredCount > 0 ? "Continue" : "Start"
    }

    private func open(plan: MemoryPlan, progress: PlanProgress) {
        if progress.isComplete {
            return navigator.push(.review(.plan(plan.id)))
        }
        guard !state.isActive(plan) else {
            return navigator.push(.session(.plan(plan.id)))
        }
        // Taking a plan on ends the browsing that found it: the session opens
        // straight off the home page, where the plan now waits.
        state.activatePlan(plan)
        navigator.reset(to: .session(.plan(plan.id)))
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
