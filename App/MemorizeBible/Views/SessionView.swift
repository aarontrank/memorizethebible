import BibleCore
import SwiftUI

/// The session screen (§8.2): scripture as scrolling text with a control bar
/// at the bottom. Drives a chapter or a memory plan without caring which.
struct SessionView: View {
    let targetID: MemoryTargetID

    @Environment(AppState.self) private var state
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var engine: SessionEngine?

    /// In landscape the scarce dimension is height, and a bottom bar spends
    /// two fifths of it on controls — leaving about three lines of scripture.
    /// The same controls in a column beside the text cost width, which
    /// landscape has to spare. At accessibility sizes a column that narrow
    /// would be worse than the squeeze, so the bar stays put there.
    private var usesSideRail: Bool {
        verticalSizeClass == .compact && dynamicTypeSize <= .accessibility1
    }

    var body: some View {
        Group {
            if let engine {
                content(engine: engine)
            } else {
                ProgressView().task { start() }
            }
        }
        .background(Palette.background)
        .navigationTitle(engine?.target.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func start() {
        guard let target = state.target(for: targetID) else { return }
        engine = SessionEngine(
            target: target,
            snapshot: state.progress,
            clock: state.clock,
            persist: { state.apply($0) }
        )
    }

    @ViewBuilder
    private func content(engine: SessionEngine) -> some View {
        let controls = ControlBar(
            engine: engine,
            axis: usesSideRail ? .vertical : .horizontal,
            tip: Walkthrough.sessionTip(state: state, engine: engine),
            onSkip: { state.endWalkthrough(completed: false) },
            onFinish: { navigator.popToRoot() }
        )
        // One arrangement swapped for another, rather than one view tree
        // swapped for another: rotating mid-session keeps the same scroll view,
        // so it keeps your place in the chapter.
        let arrangement = usesSideRail
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        arrangement {
            scripture(engine: engine)
            Divider().overlay(Palette.progressTrack)
            controls.frame(width: usesSideRail ? Metrics.controlRailWidth : nil)
        }
        // Finishing takes you home rather than back through the screens you
        // came in by, and the celebration happens there.
        .onChange(of: engine.justCompletedTarget) { _, finished in
            guard finished else { return }
            state.celebrate()
            navigator.popToRoot()
        }
    }

    private func scripture(engine: SessionEngine) -> some View {
        ScriptureView(
            sections: state.sections(for: engine.target),
            activeUnits: Set(engine.activeUnits),
            activeLevel: engine.level,
            carriedOverUnits: engine.carriedOverUnits,
            onPeek: { engine.recordPeek($0) },
            scrollTarget: engine.focusVerse
        )
    }
}

/// §8.2: `Show more` · level indicator · `Show less` · primary action.
///
/// The same three pieces — what to do, how much is hidden, and the answer —
/// arranged as a bar under the text in portrait and as a column beside it in
/// landscape.
struct ControlBar: View {
    let engine: SessionEngine
    /// `.horizontal` reads as a bar across the foot; `.vertical` as a rail
    /// down the trailing edge.
    var axis: Axis = .horizontal
    var tip: String?
    var onSkip: (() -> Void)?
    let onFinish: () -> Void

    var body: some View {
        Group {
            switch axis {
            case .horizontal: bar
            case .vertical: rail
            }
        }
        .background(Palette.background)
    }

    private var bar: some View {
        VStack(spacing: 14) {
            if let tip { TipBubble(text: tip, caret: .bottom, onSkip: onSkip) }
            prompt
            if showsLevelControls { levelControls }
            HStack(spacing: 12) {
                if showsMissButton { missButton.fixedSize() }
                primaryButton
            }
        }
        // Match the text above: controls that ran the full width of a wide
        // screen would sit nowhere near the column they belong to.
        .frame(maxWidth: Metrics.scriptureMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var rail: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            // What to do sits directly above the controls it describes. It can
            // run long — a walkthrough tip at a large text size more so — so it
            // scrolls when it has to, and only then. The controls never scroll.
            ViewThatFits(in: .vertical) {
                guidance
                ScrollView { guidance }.scrollBounceBehavior(.basedOnSize)
            }
            if showsLevelControls { levelControls }
            primaryButton
            if showsMissButton { missButton }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 12)
    }

    private var guidance: some View {
        VStack(spacing: 12) {
            if let tip { TipBubble(text: tip, caret: .bottom, onSkip: onSkip) }
            prompt
        }
    }

    private var levelControls: some View {
        HStack(spacing: 18) {
            levelButton("Show more", systemImage: "eye", enabled: engine.canShowMore) {
                engine.showMore()
            }
            LevelIndicator(level: engine.level)
            levelButton("Show less", systemImage: "eye.slash", enabled: engine.canShowLess) {
                engine.showLess()
            }
        }
    }

    private var primaryButton: some View {
        Button(primaryTitle) { primaryAction() }
            .buttonStyle(PrimaryButtonStyle())
    }

    private var missButton: some View {
        Button(missTitle) { engine.reportMiss() }
            .buttonStyle(SecondaryButtonStyle())
    }

    // MARK: - Copy

    @ViewBuilder
    private var prompt: some View {
        Text(promptText)
            .font(Typography.chrome(.footnote))
            .foregroundStyle(Palette.dimmedText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var promptText: String {
        switch engine.step {
        case .read:
            let remaining = engine.readsRemaining
            return remaining > 0
                ? "Read the verse aloud — \(remaining) more to go"
                : "Ready when you are"
        case .carriedOver:
            return "You already know this verse from elsewhere. Keep it, or work it again here?"
        case .ladder:
            if engine.level == .full {
                return engine.attemptHasPeek
                    ? "You peeked — start the attempt again for a clean pass"
                    : "Recite the whole verse from memory"
            }
            return "Recite the verse aloud, filling in the blanks"
        case let .cumulative(units, _):
            return cumulativePrompt(units: units)
        case .recitation:
            guard let block = engine.currentBlock else { return "Recite it all from memory" }
            if let title = block.title { return "Recite \(title) from memory" }
            return engine.target.blocks.count > 1
                ? "Recite this section from memory"
                : "Recite the whole thing from memory"
        case .done:
            return "Memorized. Well done."
        }
    }

    /// The accumulated block: one verse, a run within a chapter, or — for a
    /// plan — a handful of references from wherever they came.
    private func cumulativePrompt(units: [VerseRef]) -> String {
        guard let first = units.first else { return "Recite what you have so far" }
        if units.count == 1 {
            return first.isSuperscription
                ? "Recite the heading from memory"
                : "Recite verse \(first.verse) from memory"
        }
        let sameChapter = units.allSatisfy { $0.chapterRef == first.chapterRef }
        if sameChapter {
            let verses = units.filter { !$0.isSuperscription }
            guard let low = verses.first?.verse, let high = verses.last?.verse else {
                return "Recite what you have so far"
            }
            return units.contains(where: \.isSuperscription)
                ? "Recite the heading and verses \(low)–\(high) together"
                : "Recite verses \(low)–\(high) together"
        }
        return "Recite all \(units.count) verses so far, together"
    }

    private var primaryTitle: String {
        switch engine.step {
        case .read: return "Read"
        case .ladder:
            if engine.attemptHasPeek && engine.level == .full { return "Try again" }
            return engine.isAtMasteryRung ? "I know it" : "I got it"
        case .cumulative, .recitation: return "Confirm"
        case .carriedOver: return "I still know it"
        case .done: return "Done"
        }
    }

    private var missTitle: String {
        switch engine.step {
        case .cumulative, .recitation: return "Need help"
        case .carriedOver: return "Memorize it again"
        default: return "Not yet"
        }
    }

    private var showsMissButton: Bool {
        switch engine.step {
        case .ladder, .cumulative, .recitation, .carriedOver: return true
        case .read, .done: return false
        }
    }

    private var showsLevelControls: Bool {
        switch engine.step {
        // A carried-over verse is shown in full while the choice is made.
        case .read, .done, .carriedOver: return false
        default: return true
        }
    }

    /// A peek at level 4 resets the attempt rather than conferring mastery
    /// (§7.1 phase 3, §7.3).
    private var isRestartingAttempt: Bool {
        engine.attemptHasPeek && engine.level == .full
    }

    private func primaryAction() {
        if case .done = engine.step {
            onFinish()
        } else if isRestartingAttempt {
            engine.restartAttempt()
        } else {
            engine.confirmCurrentStep()
        }
    }

    private func levelButton(
        _ title: String,
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: Metrics.minimumTapTarget, height: Metrics.minimumTapTarget)
        }
        .disabled(!enabled)
        .foregroundStyle(enabled ? Palette.text : Palette.progressTrack)
        // §12: the level controls carry explicit labels.
        .accessibilityLabel(title == "Show more" ? "Show more words" : "Show fewer words")
    }
}

/// The ●●●○○ level indicator (§8.2).
struct LevelIndicator: View {
    let level: MaskLevel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MaskLevel.allCases, id: \.rawValue) { rung in
                Circle()
                    .fill(rung.rawValue <= level.rawValue ? Palette.progressFill : Palette.progressTrack)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.percentMasked) percent hidden")
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.chrome(.headline))
            .foregroundStyle(Palette.background)
            .frame(maxWidth: .infinity, minHeight: Metrics.minimumTapTarget)
            .background(
                (isEnabled ? Palette.progressFill : Palette.progressTrack),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.chrome(.headline))
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: Metrics.minimumTapTarget)
            .frame(minWidth: 96)
            .background(Palette.progressTrack, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
