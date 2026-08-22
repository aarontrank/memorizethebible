import BibleCore
import SwiftUI

/// A run of verses from one chapter, as shown on screen.
struct ScriptureSection: Identifiable, Hashable {
    let ref: ChapterRef
    /// Shown above the verses when more than one section is on screen — a plan
    /// jumping between books needs to say where it is.
    let title: String
    let superscription: Verse?
    let verses: [Verse]

    var id: ChapterRef { ref }
}

/// Scripture as continuous scrolling text (§8.2).
///
/// Active verses are at full opacity; everything else is dimmed but readable.
/// A chapter session shows the whole chapter for context; a plan shows the
/// plan's own verses, which is the context that matters there.
struct ScriptureView: View {
    let sections: [ScriptureSection]
    let activeUnits: Set<VerseRef>
    let activeLevel: MaskLevel
    /// Level applied to surrounding, dimmed verses.
    var contextLevel: MaskLevel = .none
    var showSuperscriptions: Bool = true
    /// Verses already memorized elsewhere and not yet worked in this context.
    var carriedOverUnits: Set<VerseRef> = []
    var onPeek: ((VerseRef) -> Void)?
    var scrollTarget: VerseRef?

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        if sections.count > 1 {
                            Text(section.title)
                                .font(Typography.chrome(.caption))
                                .foregroundStyle(Palette.verseNumber)
                                .textCase(.uppercase)
                                .padding(.top, section == sections.first ? 0 : 26)
                                .padding(.bottom, 6)
                        }
                        if showSuperscriptions, let superscription = section.superscription {
                            verseView(superscription)
                                .padding(.bottom, 14)
                        }
                        ForEach(section.verses) { verse in
                            verseView(verse)
                                .padding(.top, verse.startsParagraph ? 16 : 8)
                        }
                    }
                }
                .frame(maxWidth: Metrics.scriptureMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, Metrics.gutter)
                // Breathing room above and below the text, but not in
                // landscape, where 48 points is most of a line of scripture.
                .padding(.vertical, verticalSizeClass == .compact ? 12 : 24)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
            }
            .onAppear {
                guard let scrollTarget else { return }
                proxy.scrollTo(scrollTarget, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func verseView(_ verse: Verse) -> some View {
        let isActive = activeUnits.contains(verse.ref)
        VerseView(
            verse: verse,
            level: isActive ? activeLevel : contextLevel,
            emphasis: isActive ? .active : .dimmed,
            isCarriedOver: carriedOverUnits.contains(verse.ref),
            onPeek: isActive && onPeek != nil ? { onPeek?(verse.ref) } : nil
        )
        .id(verse.ref)
    }
}
