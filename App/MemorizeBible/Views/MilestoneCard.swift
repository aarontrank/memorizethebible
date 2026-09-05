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
    /// The words of `milestone.verse`, where there is one to print.
    var verseText: String?

    /// Rendered at twice this, giving 1080×1080. Square is what survives being
    /// posted anywhere without being cropped.
    static let size = CGSize(width: 540, height: 540)

    /// A verse has to share a fixed square with everything else, so when there
    /// is one the chrome around it gives up room: a smaller seal, tighter
    /// margins, and the verse set at reading size rather than display size.
    private var hasVerse: Bool { verseText != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: hasVerse ? 12 : 24)

            seal.padding(.bottom, hasVerse ? 20 : 30)

            Text("Milestone")
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .tracking(2.5)
                .textCase(.uppercase)
                .foregroundStyle(Palette.text)

            Text(milestone.kind.title)
                // The headline gives way when a verse has to share the card
                // with it: the verse is the thing worth reading here.
                .font(Typography.scripture(verseText == nil ? .largeTitle : .title2))
                .foregroundStyle(Palette.text)
                .minimumScaleFactor(0.4)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            if let verseText {
                Text(verseText)
                    .font(Typography.scripture(.body))
                    .foregroundStyle(Palette.text)
                    // Six lines and free to shrink into them: the longest
                    // opening verse in the book runs to 377 characters, and it
                    // has to fit rather than push the footer off the card.
                    .minimumScaleFactor(0.4)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }

            if let subject = milestone.subject {
                Text(subject)
                    .font(
                        verseText == nil
                            ? Typography.scripture(.title3) : Typography.chrome(.subheadline)
                    )
                    .foregroundStyle(verseText == nil ? Palette.text : Palette.dimmedText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, verseText == nil ? 16 : 10)
            }

            Text(milestone.achievedAt.formatted(.dateTime.day().month(.wide).year()))
                .font(.system(.subheadline))
                .foregroundStyle(Palette.dimmedText)
                .padding(.top, 10)

            Spacer(minLength: hasVerse ? 12 : 24)
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
            .font(.system(size: hasVerse ? 34 : 46, weight: .semibold))
            .foregroundStyle(Palette.text)
            .frame(width: hasVerse ? 76 : 104, height: hasVerse ? 76 : 104)
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
    static func rendered(_ milestone: Milestone, verseText: String? = nil) -> UIImage? {
        let renderer = ImageRenderer(
            content: MilestoneCardView(milestone: milestone, verseText: verseText)
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }
}
