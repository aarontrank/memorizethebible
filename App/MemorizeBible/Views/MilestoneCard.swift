import BibleCore
import SwiftUI

extension MilestoneKind {
    /// A mark of its own for each, so a row of them reads at a glance without
    /// anybody having to check the words underneath.
    var symbol: String {
        switch self {
        case .firstVerse: return "text.quote"
        case .tenVerses: return "10.circle"
        case .firstChapter: return "book.closed"
        case .firstPlan: return "checklist"
        case .firstBook: return "books.vertical"
        case .hundredVerses: return "star.circle"
        }
    }
}

/// The certificate: a milestone as something you can hand to someone.
///
/// Like the progress cards it replaces, this is the one place §9's "no
/// decorative imagery" gives way — it leaves the app and has to stand on its
/// own in a feed with no context around it, so it carries the mark and the
/// name. It stays inside the palette all the same: the gold of a finished
/// blank, which is what memorizing has looked like all along.
struct MilestoneCardView: View {
    let milestone: Milestone

    /// Rendered at twice this, giving 1080×1080. Square is what survives being
    /// posted anywhere without being cropped.
    static let size = CGSize(width: 540, height: 540)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)

            seal.padding(.bottom, 30)

            Text("Milestone")
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .tracking(2.5)
                .textCase(.uppercase)
                .foregroundStyle(Palette.text)

            Text(milestone.kind.title)
                .font(Typography.scripture(.largeTitle))
                .foregroundStyle(Palette.text)
                .minimumScaleFactor(0.4)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Text(milestone.caption)
                .font(Typography.scripture(.title3))
                .foregroundStyle(Palette.text)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Text(milestone.achievedAt.formatted(.dateTime.day().month(.wide).year()))
                .font(.system(.subheadline))
                .foregroundStyle(Palette.dimmedText)
                .padding(.top, 10)

            Spacer(minLength: 24)
            footer
        }
        .padding(48)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Palette.blankFill)
        // An edge, so the card does not dissolve into a pale feed.
        .overlay(Rectangle().strokeBorder(Palette.blankUnderline, lineWidth: 4))
        // An exported image has to look the same whatever the device was set
        // to when it was made, so the palette is pinned to its light values.
        .environment(\.colorScheme, .light)
    }

    private var seal: some View {
        Image(systemName: milestone.kind.symbol)
            .font(.system(size: 46, weight: .semibold))
            .foregroundStyle(Palette.text)
            .frame(width: 104, height: 104)
            .background(Circle().fill(Palette.blankUnderline))
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

    /// The card as an image, which is both what is shown on the milestone
    /// screen and what gets shared — so the two can never disagree.
    @MainActor
    static func rendered(_ milestone: Milestone) -> UIImage? {
        let renderer = ImageRenderer(content: MilestoneCardView(milestone: milestone))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }
}
