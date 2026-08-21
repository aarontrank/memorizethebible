import BibleCore
import SwiftUI

/// Every book, split by testament (§8.1, widened to the whole Bible).
struct BookListView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        List {
            ForEach(Testament.allCases, id: \.self) { testament in
                let books = matchingBooks(in: testament)
                if !books.isEmpty {
                    Section(testament.title) {
                        ForEach(books) { book in
                            NavigationLink(value: Route.chapters(book.id)) {
                                row(book)
                            }
                            .listRowBackground(Palette.background)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Palette.background)
        .searchable(text: $search, prompt: "Find a book")
        .navigationTitle("Books")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func matchingBooks(in testament: Testament) -> [BookSummary] {
        let books = state.content.manifest.books(in: testament)
        guard !search.isEmpty else { return books }
        return books.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func row(_ book: BookSummary) -> some View {
        let progress = state.bookProgress(book.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(book.name)
                    .font(Typography.scripture(.body))
                    .foregroundStyle(Palette.text)
                Text(subtitle(book: book, progress: progress))
                    .font(Typography.chrome(.caption))
                    .foregroundStyle(Palette.dimmedText)
            }
            Spacer(minLength: 12)
            if progress.isStarted {
                ProgressBar(fraction: progress.fraction, height: 4).frame(width: 44)
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(book.name). \(subtitle(book: book, progress: progress))")
    }

    private func subtitle(book: BookSummary, progress: BookProgress) -> String {
        let chapters = book.chapterCount == 1 ? "1 chapter" : "\(book.chapterCount) chapters"
        guard progress.isStarted else { return chapters }
        if progress.isComplete { return "Memorized · \(chapters)" }
        return "\(chapters) · \(progress.masteredVerses) of \(progress.verseCount) verses"
    }
}
