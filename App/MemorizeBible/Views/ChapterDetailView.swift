import BibleCore
import SwiftUI

/// One chapter, to read before deciding anything about it.
///
/// Browsing is not committing (§8.1): you can open Psalm 1, read it through and
/// leave again without it becoming what you are memorizing. Start memorizing is
/// the only thing that puts it on the home page — and once it is there, this
/// screen is the way back into it.
struct ChapterDetailView: View {
    let ref: ChapterRef

    @Environment(AppState.self) private var state
    @Environment(Navigator.self) private var navigator

    private var progress: ChapterProgress { state.chapterProgress(ref) }
    private var sections: [ScriptureSection] { state.wholeChapterSections(ref) }

    /// Every verse on screen, so the whole chapter reads at full opacity rather
    /// than dimmed the way context around a session verse is.
    private var units: Set<VerseRef> {
        Set(
            sections.flatMap { section in
                (section.superscription.map { [$0.ref] } ?? []) + section.verses.map(\.ref)
            }
        )
    }

    var body: some View {
        Group {
            if sections.isEmpty {
                Text("This chapter is not available.")
                    .font(Typography.chrome(.subheadline))
                    .foregroundStyle(Palette.dimmedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .background(Palette.background)
        .navigationTitle(state.title(for: ref))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ProgressShareLink(
                        content: .chapter(title: state.title(for: ref), progress: progress)
                    )
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScriptureView(sections: sections, activeUnits: units, activeLevel: .none)
            Divider().overlay(Palette.progressTrack)
            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text(caption)
                .font(Typography.chrome(.footnote))
                .foregroundStyle(Palette.dimmedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if progress.isStarted, !progress.isMemorized {
                ProgressBar(fraction: progress.fraction)
            }
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(PrimaryButtonStyle())
        }
        // Matched to the text above, so the button never runs the full width of
        // an iPad while the scripture sits in a column.
        .frame(maxWidth: Metrics.scriptureMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var primaryTitle: String {
        if progress.isMemorized { return "Review" }
        return progress.isStartedAsChapter ? "Continue" : "Start memorizing"
    }

    private func primaryAction() {
        if progress.isMemorized {
            return navigator.push(.review(.chapter(ref)))
        }
        guard !progress.isStartedAsChapter else {
            return navigator.push(.session(.chapter(ref)))
        }
        // Taking it on ends the browsing that found it: the session opens
        // straight off the home page, where the chapter now waits.
        state.activateChapter(ref)
        navigator.reset(to: .session(.chapter(ref)))
    }

    private var caption: String {
        if progress.isMemorized { return "Memorized" }
        let noun = progress.unitCount == 1 ? "verse" : "verses"
        if progress.isStartedAsChapter {
            return "\(progress.masteredCount) of \(progress.unitCount) \(noun) memorized"
        }
        // Say where a part-done chapter you have never opened came from, rather
        // than leaving it looking mysteriously started.
        if progress.carriedOverCount > 0 {
            return "\(progress.unitCount) \(noun) · \(progress.carriedOverCount) already memorized elsewhere"
        }
        return "\(progress.unitCount) \(noun)"
    }
}
