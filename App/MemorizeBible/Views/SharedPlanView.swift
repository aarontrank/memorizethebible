import BibleCore
import SwiftUI

/// What someone sent you, before it is yours.
///
/// A link can arrive from anyone, so this screen is a question rather than an
/// announcement: here is what the plan holds, save it or leave it. Nothing is
/// written until Save is tapped.
struct SharedPlanView: View {
    let arrival: AppState.SharedPlanArrival

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch arrival {
                case let .plan(plan, replacing): planContent(plan: plan, replacing: replacing)
                case let .failed(message): failure(message: message)
                }
            }
            .background(Palette.background)
            .navigationTitle("Shared with you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFailure ? "Close" : "Ignore") {
                        state.dismissSharedPlan()
                        dismiss()
                    }
                }
            }
        }
    }

    private var isFailure: Bool {
        if case .failed = arrival { return true }
        return false
    }

    @ViewBuilder
    private func planContent(plan: MemoryPlan, replacing: MemoryPlan?) -> some View {
        let verseCount = state.target(forPlan: plan).units.count

        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.title)
                        .font(Typography.scripture(.title3))
                        .foregroundStyle(Palette.text)
                    if !plan.summary.isEmpty {
                        Text(plan.summary)
                            .font(Typography.chrome(.subheadline))
                            .foregroundStyle(Palette.dimmedText)
                    }
                    Text(countCaption(verseCount))
                        .font(Typography.chrome(.footnote))
                        .foregroundStyle(Palette.dimmedText)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Palette.background)

            ForEach(Array(plan.sections.enumerated()), id: \.element.id) { _, section in
                Section(plan.sections.count > 1 ? section.title : "Verses") {
                    ForEach(section.passages, id: \.self) { passage in
                        Text(state.content.manifest.title(for: passage))
                            .font(Typography.scripture(.body))
                            .foregroundStyle(Palette.text)
                    }
                    .listRowBackground(Palette.background)
                }
            }

            Section {
                Button {
                    state.saveSharedPlan(plan)
                    dismiss()
                } label: {
                    Text(replacing == nil ? "Save to Shared plans" : "Replace the copy you have")
                        .font(Typography.chrome(.headline))
                        .foregroundStyle(Palette.text)
                }
                .disabled(verseCount == 0)
                .listRowBackground(Palette.background)
            } footer: {
                Text(footer(verseCount: verseCount, replacing: replacing))
            }
        }
        .listStyle(.insetGrouped)
    }

    private func countCaption(_ verseCount: Int) -> String {
        switch verseCount {
        case 0: return "None of these verses are in this translation."
        case 1: return "1 verse"
        default: return "\(verseCount) verses"
        }
    }

    private func footer(verseCount: Int, replacing: MemoryPlan?) -> String {
        if verseCount == 0 {
            return "This plan names verses this translation does not have, so there is nothing to memorize in it."
        }
        if replacing != nil {
            return "You already have this plan, under the name “\(replacing?.title ?? "")”. Saving replaces it, including any changes you made. Verses you have memorized are not affected."
        }
        return "Saving adds the plan to your Plans page. Verses you have already memorized still count toward it."
    }

    private func failure(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(Palette.dimmedText)
            Text(message)
                .font(Typography.chrome(.subheadline))
                .foregroundStyle(Palette.dimmedText)
                .multilineTextAlignment(.center)
        }
        .padding(Metrics.gutter)
        .frame(maxWidth: Metrics.scriptureMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
