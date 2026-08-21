import BibleCore
import SwiftUI

/// Building a plan of your own: a title, and the passages it holds.
struct PlanEditorView: View {
    /// Set when editing an existing plan; resolved from state so an edit always
    /// sees the current version.
    private let planID: String?

    init(existing: MemoryPlan?) { self.planID = existing?.id }
    init(planID: String) { self.planID = planID }

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var summary = ""
    @State private var passages: [PassageRef] = []
    @State private var addingPassage = false

    private var existing: MemoryPlan? { planID.flatMap { state.plan(id: $0) } }

    var body: some View {
        List {
            Section("Name") {
                TextField("Plan name", text: $title)
                    .font(Typography.scripture(.body))
                TextField("What it is for (optional)", text: $summary, axis: .vertical)
                    .font(Typography.chrome(.subheadline))
                    .lineLimit(1...3)
            }

            Section {
                ForEach(Array(passages.enumerated()), id: \.offset) { index, passage in
                    HStack {
                        Text(state.content.manifest.title(for: passage))
                            .font(Typography.scripture(.body))
                        Spacer()
                        Text(verseCount(passage))
                            .font(Typography.chrome(.caption))
                            .foregroundStyle(Palette.dimmedText)
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { passages.remove(at: index) }
                    }
                }
                .onMove { passages.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    addingPassage = true
                } label: {
                    Label("Add passage", systemImage: "plus")
                }
            } header: {
                Text("Passages")
            } footer: {
                Text("Verses are memorized in the order listed. Drag to reorder — the Roman Road, for instance, is not in canonical order.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle(existing == nil ? "New plan" : "Edit plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .sheet(isPresented: $addingPassage) {
            NavigationStack {
                PassagePickerView { passages.append($0) }
            }
        }
        .onAppear {
            guard let existing, title.isEmpty else { return }
            title = existing.title
            summary = existing.summary
            passages = existing.passages
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !passages.isEmpty
    }

    private func verseCount(_ passage: PassageRef) -> String {
        let count = passage.lastVerse - passage.firstVerse + 1
        return count == 1 ? "1 verse" : "\(count) verses"
    }

    private func save() {
        let plan = MemoryPlan(
            id: existing?.id ?? UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespaces),
            summary: summary.trimmingCharacters(in: .whitespaces),
            passages: passages,
            isBuiltIn: false,
            createdAt: existing?.createdAt ?? state.clock.now
        )
        if existing == nil {
            state.addPlan(plan)
        } else {
            state.updatePlan(plan)
        }
        dismiss()
    }
}

/// Picks a book, a chapter, and a verse range.
struct PassagePickerView: View {
    let onPick: (PassageRef) -> Void

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var book: BookID?
    @State private var chapter: Int?
    @State private var firstVerse = 1
    @State private var lastVerse = 1

    var body: some View {
        Group {
            if let book, let chapter {
                versePicker(book: book, chapter: chapter)
            } else if let book {
                chapterPicker(book: book)
            } else {
                bookPicker
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var navigationTitle: String {
        guard let book else { return "Choose a book" }
        guard let chapter else { return state.content.book(book)?.name ?? "Chapter" }
        return state.title(for: ChapterRef(book, chapter))
    }

    private var bookPicker: some View {
        List {
            ForEach(Testament.allCases, id: \.self) { testament in
                Section(testament.title) {
                    ForEach(state.content.manifest.books(in: testament)) { summary in
                        Button(summary.name) { book = summary.id }
                            .foregroundStyle(Palette.text)
                    }
                }
            }
        }
    }

    private func chapterPicker(book: BookID) -> some View {
        List {
            ForEach(state.content.book(book)?.chapters ?? []) { summary in
                Button {
                    chapter = summary.number
                    firstVerse = summary.firstVerse
                    lastVerse = summary.firstVerse
                } label: {
                    HStack {
                        Text(state.title(for: ChapterRef(book, summary.number)))
                        Spacer()
                        Text("\(summary.verseCount) verses")
                            .font(Typography.chrome(.caption))
                            .foregroundStyle(Palette.dimmedText)
                    }
                }
                .foregroundStyle(Palette.text)
            }
        }
    }

    private func versePicker(book: BookID, chapter: Int) -> some View {
        let summary = state.content.summary(for: ChapterRef(book, chapter))
        let numbers = verseNumbers(book: book, chapter: chapter, summary: summary)
        return List {
            Section("From") {
                Picker("First verse", selection: $firstVerse) {
                    ForEach(numbers, id: \.self) { Text("Verse \($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                .onChange(of: firstVerse) { _, new in
                    if lastVerse < new { lastVerse = new }
                }
            }
            Section("To") {
                Picker("Last verse", selection: $lastVerse) {
                    ForEach(numbers.filter { $0 >= firstVerse }, id: \.self) { Text("Verse \($0)").tag($0) }
                }
                .pickerStyle(.wheel)
            }
            Section {
                Button("Add \(label(book: book, chapter: chapter))") {
                    onPick(PassageRef(book, chapter, firstVerse, lastVerse))
                    dismiss()
                }
                .font(Typography.chrome(.headline))
            }
        }
    }

    private func label(book: BookID, chapter: Int) -> String {
        state.content.manifest.title(for: PassageRef(book, chapter, firstVerse, lastVerse))
    }

    /// Real verse numbers, so a chapter with an omitted verse cannot be picked
    /// into a plan that points at nothing.
    private func verseNumbers(book: BookID, chapter: Int, summary: ChapterSummary?) -> [Int] {
        if let loaded = state.chapter(ChapterRef(book, chapter)) { return loaded.verseNumbers }
        guard let summary else { return [1] }
        return Array(summary.firstVerse..<(summary.firstVerse + summary.verseCount))
    }
}
