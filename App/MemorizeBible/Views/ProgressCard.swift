import BibleCore
import SwiftUI

/// What a progress card says.
///
/// Chapters, books and plans each track progress in their own type; the card
/// only needs the four things they have in common, so it takes them flattened
/// rather than learning about all three.
struct ProgressCardContent {
    /// "Chapter", "Book", "Plan" — the small label above the title.
    let kind: String
    /// "Psalm 23", "Romans", "The Roman Road".
    let title: String
    let memorized: Int
    let total: Int
    let isComplete: Bool
    let completedAt: Date?

    var fraction: Double { total == 0 ? 0 : Double(memorized) / Double(total) }

    /// The name the share sheet shows before the image loads.
    var shareTitle: String {
        isComplete ? "\(title) — memorized" : "\(title) — \(memorized) of \(total) verses"
    }

    static func plan(_ plan: MemoryPlan, progress: PlanProgress) -> Self {
        Self(
            kind: "Plan",
            title: plan.title,
            memorized: progress.masteredCount,
            total: progress.unitCount,
            isComplete: progress.isComplete,
            completedAt: progress.completedAt
        )
    }

    static func chapter(title: String, progress: ChapterProgress) -> Self {
        Self(
            kind: "Chapter",
            title: title,
            memorized: progress.masteredCount,
            total: progress.unitCount,
            isComplete: progress.isMemorized,
            completedAt: progress.completedAt
        )
    }

    static func book(_ book: BookSummary, progress: BookProgress) -> Self {
        Self(
            kind: "Book",
            title: book.name,
            memorized: progress.masteredVerses,
            total: progress.verseCount,
            isComplete: progress.isComplete,
            completedAt: nil
        )
    }
}

/// The shareable card itself.
///
/// This is the one thing in the app that is not bound by §9's "no decorative
/// imagery": it leaves the app and has to stand on its own in a feed, next to
/// no other context, so it carries the mark and the name. It stays inside the
/// palette all the same — a finished card is the same gold as a filled blank,
/// which is what memorizing has looked like all along.
struct ProgressCardView: View {
    let content: ProgressCardContent

    /// Rendered at twice this, giving 1080×1080. Square because the card holds
    /// four short lines: a taller frame only adds emptiness, and a square is
    /// what survives every place these get posted without being cropped.
    static let size = CGSize(width: 540, height: 540)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The block sits centred in the space above the mark, so a short
            // card and a long one are both composed rather than top-heavy.
            Spacer(minLength: 24)

            // A finished card leads with the seal: it is the first thing the
            // eye lands on, and the only thing that has to read at thumbnail
            // size in a feed.
            if content.isComplete {
                seal.padding(.bottom, 30)
            }

            Text(content.isComplete ? "Memorized" : content.kind)
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .tracking(2.5)
                .textCase(.uppercase)
                .foregroundStyle(content.isComplete ? Palette.text : Palette.dimmedText)

            Text(content.title)
                .font(Typography.scripture(.largeTitle))
                .foregroundStyle(Palette.text)
                .minimumScaleFactor(0.4)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            if content.isComplete {
                Text(completeCaption)
                    .font(Typography.scripture(.title3))
                    .foregroundStyle(Palette.text)
                    .padding(.top, 16)
            } else {
                bar.padding(.top, 34)
            }

            Spacer(minLength: 24)
            footer
        }
        .padding(48)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(content.isComplete ? Palette.blankFill : Palette.background)
        // An edge, so a white card does not dissolve into a white feed.
        .overlay(
            Rectangle()
                .strokeBorder(
                    content.isComplete ? Palette.blankUnderline : Palette.progressTrack,
                    lineWidth: 4
                )
        )
        // An exported image must look the same whatever the device was set to
        // when it was made, so the palette is pinned to its light values.
        .environment(\.colorScheme, .light)
    }

    private var completeCaption: String {
        guard let completedAt = content.completedAt else { return unitCount(content.total) }
        let date = completedAt.formatted(.dateTime.day().month(.wide).year())
        return "\(unitCount(content.total)) · \(date)"
    }

    private var seal: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 46, weight: .semibold))
            .foregroundStyle(Palette.text)
            .frame(width: 104, height: 104)
            .background(Circle().fill(Palette.blankUnderline))
    }

    private var bar: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.progressTrack)
                    Capsule()
                        .fill(Palette.progressFill)
                        .frame(width: max(geometry.size.width * content.fraction, 6))
                }
            }
            .frame(height: 10)

            Text("\(content.memorized) of \(unitCount(content.total)) memorized")
                .font(Typography.scripture(.title3))
                .foregroundStyle(Palette.text)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Image("LaunchIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("Memorize The Bible")
                .font(.system(.headline).weight(.semibold))
                .foregroundStyle(Palette.text)
            Spacer(minLength: 0)
        }
    }

    private func unitCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "verse" : "verses")"
    }
}

/// A share-sheet entry that hands over the card as an image.
///
/// The card is drawn when this view is built. Every caller puts it inside a
/// menu or a context menu, so that happens on the tap that opens the menu
/// rather than once per row in a list of 150 psalms.
struct ProgressShareLink: View {
    let content: ProgressCardContent
    var title: String = "Share my progress"

    var body: some View {
        if let image = render() {
            ShareLink(
                item: image,
                preview: SharePreview(content.shareTitle, image: image)
            ) {
                Label(title, systemImage: "square.and.arrow.up")
            }
        }
    }

    @MainActor
    private func render() -> Image? {
        let renderer = ImageRenderer(content: ProgressCardView(content: content))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(ProgressCardView.size)
        guard let rendered = renderer.uiImage else { return nil }
        return Image(uiImage: rendered)
    }
}
