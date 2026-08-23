import BibleCore
import SwiftUI

/// The chapters of one book. A memorized chapter opens in Review; anything else
/// opens a session.
struct ChapterListView: View {
    let book: BookID

    @Environment(AppState.self) private var state

    private var summary: BookSummary? { state.content.book(book) }

    var body: some View {
        List {
            if let summary {
                ForEach(summary.chapters) { chapter in
                    let ref = ChapterRef(book, chapter.number)
                    let progress = state.chapterProgress(ref)
                    NavigationLink(
                        value: progress.isMemorized ? Route.review(.chapter(ref)) : Route.session(.chapter(ref))
                    ) {
                        row(chapter: chapter, ref: ref, progress: progress)
                    }
                    .listRowBackground(Palette.background)
                    // A chapter has no screen of its own — it opens straight
                    // into the work — so its card hangs off the row.
                    .contextMenu {
                        ProgressShareLink(
                            content: .chapter(title: state.title(for: ref), progress: progress)
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Palette.background)
        .navigationTitle(summary?.name ?? book.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let summary {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ProgressShareLink(
                            content: .book(summary, progress: state.bookProgress(book)),
                            title: "Share my progress in \(summary.name)"
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
    }

    private func row(chapter: ChapterSummary, ref: ChapterRef, progress: ChapterProgress) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(state.title(for: ref))
                        .font(Typography.scripture(.body))
                        .foregroundStyle(Palette.text)
                    if progress.isMemorized {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.dimmedText)
                    }
                }
                Text(subtitle(chapter: chapter, progress: progress))
                    .font(Typography.chrome(.caption))
                    .foregroundStyle(Palette.dimmedText)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if progress.isStarted && !progress.isMemorized {
                ProgressBar(fraction: progress.fraction, height: 4).frame(width: 56)
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(chapter: ChapterSummary, progress: ChapterProgress) -> String {
        if progress.isMemorized { return "Memorized · tap to review" }
        guard progress.isStarted else { return chapter.firstLine }
        var text = "\(progress.masteredCount) of \(progress.unitCount) verses"
        // Say where they came from, so a chapter you have never opened does not
        // look mysteriously part-done.
        if !progress.isStartedAsChapter, progress.carriedOverCount > 0 {
            text += " · memorized elsewhere"
        }
        return text
    }
}
