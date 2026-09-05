import BibleCore
import SwiftUI

/// Everything earned, oldest first — the sequence it actually happened in.
struct MilestoneListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.milestones.isEmpty {
                empty
            } else {
                List {
                    ForEach(state.milestones) { milestone in
                        NavigationLink(value: Route.milestone(milestone.kind)) {
                            row(milestone)
                        }
                        .listRowBackground(Palette.background)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Palette.background)
        .navigationTitle("Milestones")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ milestone: Milestone) -> some View {
        HStack(spacing: 14) {
            MilestoneMark(kind: milestone.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(milestone.kind.title)
                    .font(Typography.scripture(.body))
                    .foregroundStyle(Palette.text)
                Text(milestone.caption)
                    .font(Typography.chrome(.caption))
                    .foregroundStyle(Palette.dimmedText)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(milestone.achievedAt.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(Typography.chrome(.caption))
                .foregroundStyle(Palette.dimmedText)
        }
        .padding(.vertical, 4)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Text("Nothing yet")
                .font(Typography.scripture(.title3))
                .foregroundStyle(Palette.text)
            Text("Memorize a verse and the first one is yours.")
                .font(Typography.chrome(.subheadline))
                .foregroundStyle(Palette.dimmedText)
                .multilineTextAlignment(.center)
        }
        .padding(Metrics.gutter * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One milestone, as the certificate, with the way to send it.
struct MilestoneDetailView: View {
    let kind: MilestoneKind

    @Environment(AppState.self) private var state
    @State private var card: UIImage?

    private var milestone: Milestone? { state.milestones.first { $0.kind == kind } }

    var body: some View {
        Group {
            if let milestone {
                certificate(milestone)
            } else {
                // Reachable only if progress changed under a pushed screen.
                Text("This milestone has not been earned yet.")
                    .font(Typography.chrome(.subheadline))
                    .foregroundStyle(Palette.dimmedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.background)
        .navigationTitle(milestone?.kind.title ?? "Milestone")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func certificate(_ milestone: Milestone) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            // The image is shown rather than the view it came from, so what is
            // on screen and what gets sent are the same pixels.
            if let card {
                Image(uiImage: card)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: Metrics.scriptureMaxWidth)
                    .accessibilityLabel(
                        "\(milestone.kind.title). \(milestone.caption). "
                            + milestone.achievedAt.formatted(.dateTime.day().month(.wide).year())
                    )
            } else {
                ProgressView().frame(height: 200)
            }

            if let card {
                ShareLink(
                    item: Image(uiImage: card),
                    preview: SharePreview(milestone.kind.title, image: Image(uiImage: card))
                ) {
                    Text("Share")
                        .font(Typography.chrome(.headline))
                        .foregroundStyle(Palette.background)
                        .frame(maxWidth: .infinity, minHeight: Metrics.minimumTapTarget)
                        .background(Palette.progressFill, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: Metrics.scriptureMaxWidth)
        .frame(maxWidth: .infinity)
        // Drawn once when the screen opens rather than on every redraw.
        .task { card = MilestoneCardView.rendered(milestone) }
    }
}

/// The gold disc and its mark, at whatever size the caller needs.
struct MilestoneMark: View {
    let kind: MilestoneKind
    var diameter: CGFloat = 44

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: diameter * 0.42, weight: .semibold))
            .foregroundStyle(Palette.text)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Palette.blankUnderline))
            .accessibilityHidden(true)
    }
}
