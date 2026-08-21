import BibleCore
import SwiftUI

/// Review mode: re-testing something already memorized.
///
/// Works at the scale you actually recite at — a whole chapter or plan at once,
/// or one stanza or section at a time for the long ones — and masks words
/// across the entire block rather than a verse at a time.
///
/// Nothing here writes progress. Reviewing can neither improve nor endanger
/// what you have memorized, which is what makes it safe to push to level 4 on
/// something you finished months ago.
struct ReviewView: View {
    let targetID: MemoryTargetID

    @Environment(AppState.self) private var state
    @State private var level: MaskLevel = .none
    @State private var blockIndex = 0

    private var target: MemoryTarget? { state.target(for: targetID) }

    private var isMemorized: Bool {
        switch targetID {
        case let .chapter(ref): return state.chapterProgress(ref).isMemorized
        case let .plan(id): return state.plan(id: id).map { state.planProgress($0).isComplete } ?? false
        }
    }

    private var blocks: [MemoryBlock] { target?.blocks ?? [] }

    private var block: MemoryBlock? {
        guard !blocks.isEmpty else { return nil }
        return blocks[min(blockIndex, blocks.count - 1)]
    }

    var body: some View {
        Group {
            if let target, let block, isMemorized {
                review(target: target, block: block)
            } else if target != nil, !isMemorized {
                notYetMemorized
            } else {
                Color.clear
            }
        }
        .background(Palette.background)
        .navigationTitle(target?.title ?? "Review")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            #if DEBUG
                if let raw = DebugLaunch.level, let seeded = MaskLevel(rawValue: raw) {
                    level = seeded
                }
            #endif
        }
    }

    @ViewBuilder
    private func review(target: MemoryTarget, block: MemoryBlock) -> some View {
        VStack(spacing: 0) {
            ScriptureView(
                // Every verse in the block is live at once: a whole passage
                // under recall, not one verse with the rest as context.
                sections: sections(for: block, in: target),
                activeUnits: Set(block.units),
                activeLevel: level,
                contextLevel: level,
                onPeek: nil,
                scrollTarget: block.units.first
            )
            Divider().overlay(Palette.progressTrack)
            controls(block: block)
        }
    }

    /// Only the block being reviewed, so a stanza of Psalm 119 does not drag
    /// the other 168 verses along.
    private func sections(for block: MemoryBlock, in target: MemoryTarget) -> [ScriptureSection] {
        var sections: [ScriptureSection] = []
        var seen: Set<ChapterRef> = []
        for ref in block.units where seen.insert(ref.chapterRef).inserted {
            guard let chapter = state.chapter(ref.chapterRef) else { continue }
            let wanted = Set(block.units.filter { $0.chapterRef == ref.chapterRef }.map(\.verse))
            sections.append(
                ScriptureSection(
                    ref: ref.chapterRef,
                    title: state.title(for: ref.chapterRef),
                    superscription: wanted.contains(0) ? chapter.superscription : nil,
                    verses: chapter.verses.filter { wanted.contains($0.number) }
                )
            )
        }
        return sections
    }

    private func controls(block: MemoryBlock) -> some View {
        VStack(spacing: 12) {
            Text(caption(for: block))
                .font(Typography.chrome(.footnote))
                .foregroundStyle(Palette.dimmedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 18) {
                Button { level = level.showingMore } label: {
                    Image(systemName: "eye")
                        .frame(width: Metrics.minimumTapTarget, height: Metrics.minimumTapTarget)
                }
                .disabled(level == .none)
                .accessibilityLabel("Show more words")

                LevelIndicator(level: level)

                Button { level = level.showingLess } label: {
                    Image(systemName: "eye.slash")
                        .frame(width: Metrics.minimumTapTarget, height: Metrics.minimumTapTarget)
                }
                .disabled(level == .full)
                .accessibilityLabel("Show fewer words")
            }
            .foregroundStyle(Palette.text)

            if blocks.count > 1 { blockNavigation }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Long chapters and sectioned plans are reviewed a block at a time.
    private var blockNavigation: some View {
        HStack(spacing: 12) {
            Button("Previous") { step(by: -1) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(blockIndex == 0)
            Button("Next") { step(by: 1) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(blockIndex >= blocks.count - 1)
        }
    }

    private func step(by delta: Int) {
        blockIndex = min(max(blockIndex + delta, 0), max(blocks.count - 1, 0))
        // Each block starts fully visible, the way you would open the page.
        level = .none
    }

    private func caption(for block: MemoryBlock) -> String {
        let scope: String
        if blocks.count == 1 {
            scope = "Reviewing the whole thing"
        } else {
            let position = "\(blockIndex + 1) of \(blocks.count)"
            scope = block.title.map { "\($0) · \(position)" } ?? "Part \(position)"
        }
        return level == .none
            ? "\(scope) — hide words to test yourself"
            : "\(scope) — \(level.percentMasked)% hidden"
    }

    private var notYetMemorized: some View {
        VStack(spacing: 12) {
            Text("Not yet memorized")
                .font(Typography.scripture(.title3))
                .foregroundStyle(Palette.text)
            Text("Review opens once every verse here is memorized and you have recited it through.")
                .font(Typography.chrome(.subheadline))
                .foregroundStyle(Palette.dimmedText)
                .multilineTextAlignment(.center)
        }
        .padding(Metrics.gutter * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
