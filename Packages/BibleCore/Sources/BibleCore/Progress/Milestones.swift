import Foundation

/// The things worth marking, in the order of what each one takes.
///
/// Six, each earned once. They are landmarks rather than a running tally: the
/// point of "a whole book" is the first time a whole book is done, and a
/// seventh badge for the seventh chapter would say less every time it arrived.
public enum MilestoneKind: String, Codable, Sendable, CaseIterable {
    case firstVerse
    case tenVerses
    case firstChapter
    case firstPlan
    case firstBook
    case hundredVerses

    /// The name on the certificate.
    public var title: String {
        switch self {
        case .firstVerse: return "First verse"
        case .tenVerses: return "Ten verses"
        case .firstChapter: return "A whole chapter"
        case .firstPlan: return "A whole plan"
        case .firstBook: return "A whole book"
        case .hundredVerses: return "A hundred verses"
        }
    }

    /// The line beneath the name, for milestones no single passage earned.
    /// Where one did — a chapter, a book, a plan — its name is shown instead.
    public var caption: String {
        switch self {
        case .firstVerse: return "The first one, by heart"
        case .tenVerses: return "Ten verses, by heart"
        case .firstChapter: return "A chapter, start to finish"
        case .firstPlan: return "A plan, all the way through"
        case .firstBook: return "Every chapter of a book"
        case .hundredVerses: return "A hundred verses, by heart"
        }
    }

    /// Ties are broken by what each one takes, so the verse that finishes a
    /// chapter reads first verse → ten verses → chapter rather than wobbling
    /// between runs. Sorting by date alone is not stable in Swift.
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// One milestone, earned.
public struct Milestone: Hashable, Sendable, Identifiable {
    public let kind: MilestoneKind
    public let achievedAt: Date
    /// What earned it, where one thing did: "Psalm 23", "Jude", "The Roman
    /// Road". Nil for the counting ones, which no single passage earns.
    public let subject: String?

    public var id: MilestoneKind { kind }

    public init(kind: MilestoneKind, achievedAt: Date, subject: String? = nil) {
        self.kind = kind
        self.achievedAt = achievedAt
        self.subject = subject
    }

    /// What the certificate says under the name.
    public var caption: String { subject ?? kind.caption }
}

extension ProgressReport {
    /// Every milestone earned, oldest first.
    ///
    /// Worked out from the record rather than written down as it happens. That
    /// is what lets this ship to someone who has been using the app for months
    /// and show them their whole history rather than an empty page — and it
    /// cannot drift out of step with the progress it describes, because it is
    /// the same progress read a second way.
    public func milestones(in progress: ProgressSnapshot) -> [Milestone] {
        var earned: [Milestone] = []

        // Undated masteries are skipped rather than guessed at: a verse with no
        // date cannot be placed in a sequence, and this whole list is a
        // sequence.
        let masteredOn = progress.verseStates.values
            .compactMap { $0.status == .mastered ? $0.masteredAt : nil }
            .sorted()
        func dateOfVerse(_ n: Int) -> Date? {
            masteredOn.count >= n ? masteredOn[n - 1] : nil
        }
        if let date = dateOfVerse(1) { earned.append(Milestone(kind: .firstVerse, achievedAt: date)) }
        if let date = dateOfVerse(10) { earned.append(Milestone(kind: .tenVerses, achievedAt: date)) }
        if let date = dateOfVerse(100) {
            earned.append(Milestone(kind: .hundredVerses, achievedAt: date))
        }

        if let (ref, date) = firstFinishedChapter(in: progress) {
            earned.append(
                Milestone(kind: .firstChapter, achievedAt: date, subject: content.title(for: ref))
            )
        }
        if let (plan, date) = firstFinishedPlan(in: progress) {
            earned.append(Milestone(kind: .firstPlan, achievedAt: date, subject: plan.title))
        }
        if let (book, date) = firstFinishedBook(in: progress) {
            earned.append(Milestone(kind: .firstBook, achievedAt: date, subject: book.name))
        }

        return earned.sorted {
            ($0.achievedAt, $0.kind.rank) < ($1.achievedAt, $1.kind.rank)
        }
    }

    private func firstFinishedChapter(in progress: ProgressSnapshot) -> (ChapterRef, Date)? {
        progress.chapterStates
            .compactMap { ref, state in state.completedAt.map { (ref, $0) } }
            .min { $0.1 < $1.1 }
    }

    /// The walkthrough's demo is excluded: two verses the app put there is not
    /// a plan anybody took on.
    private func firstFinishedPlan(in progress: ProgressSnapshot) -> (MemoryPlan, Date)? {
        progress.completedPlans
            .filter { $0.key != BuiltInPlans.walkthroughID }
            .compactMap { id, date in plan(id: id, in: progress).map { ($0, date) } }
            .min { $0.1 < $1.1 }
    }

    /// Cheap test first, honest test second: a book is only checked properly
    /// once it has as many finished chapters recorded as it has chapters, so
    /// the common case costs a dictionary walk rather than 1,189 lookups.
    private func firstFinishedBook(in progress: ProgressSnapshot) -> (BookSummary, Date)? {
        var finishedChapters: [BookID: [Date]] = [:]
        for (ref, state) in progress.chapterStates {
            guard let date = state.completedAt else { continue }
            finishedChapters[ref.book, default: []].append(date)
        }

        var earliest: (BookSummary, Date)?
        for (id, dates) in finishedChapters {
            guard let book = content.book(id), dates.count >= book.chapterCount else { continue }
            let whole = book.chapters.allSatisfy {
                chapterProgress(ChapterRef(id, $0.number), in: progress).isMemorized
            }
            guard whole, let finishedAt = dates.max() else { continue }
            if earliest == nil || finishedAt < earliest!.1 { earliest = (book, finishedAt) }
        }
        return earliest
    }
}
