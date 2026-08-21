import BibleCore
import SwiftUI

/// The first-run walkthrough: a demo plan and a running commentary on it.
///
/// The tips are derived from where the user actually is rather than driven by a
/// step counter. A counter can fall out of step with the app — the user taps
/// back, or finishes a verse early — and then the walkthrough is either stuck
/// or lying. Asking "what is on screen, and what has the demo plan done so far"
/// cannot get stuck.
@MainActor
enum Walkthrough {
    static let planID = "builtin.walkthrough"

    // Two dashboard tips rather than one, because they point at different
    // things: the first sends you to the plans list at the foot of the page,
    // the second to the Continue card at the top. A single tip would have to
    // sit somewhere that suits neither.

    /// Sits under the browse links, pointing up at All plans.
    static func browseTip(state: AppState) -> String? {
        guard state.isWalkthroughRunning else { return nil }
        let progress = state.walkthroughProgress
        guard !progress.isStarted, !progress.isComplete else { return nil }
        return "Plans are sets of verses learned together. Open All plans to find the demo."
    }

    /// Sits above the Continue card, pointing down at it.
    static func continueTip(state: AppState) -> String? {
        guard state.isWalkthroughRunning else { return nil }
        let progress = state.walkthroughProgress
        guard progress.isStarted, !progress.isComplete else { return nil }
        return "Continue picks up exactly where you left off — \(progress.masteredCount) of \(progress.unitCount) verses so far."
    }

    /// Tips on the plans list.
    static func planListTip(state: AppState) -> String? {
        guard state.isWalkthroughRunning, !state.walkthroughProgress.isComplete else { return nil }
        return "This demo holds two very short verses. Tap it to look inside."
    }

    /// Tips on the demo plan's own screen.
    static func planDetailTip(state: AppState, planID: String) -> String? {
        guard state.isWalkthroughRunning, planID == Self.planID else { return nil }
        let progress = state.walkthroughProgress
        if progress.isComplete {
            return "Finished plans keep their place here, and on the home screen under Completed plans. Opening one now starts a review, which can never undo your progress."
        }
        if progress.isStarted {
            return "The bar and the count follow you as you go — \(progress.masteredCount) of \(progress.unitCount) so far. Tap Continue to carry on."
        }
        return "Here is what the plan holds and how far through it you are. Tap Start."
    }

    /// Tips inside a session on the demo plan, keyed to what the session is
    /// asking for right now.
    static func sessionTip(state: AppState, engine: SessionEngine) -> String? {
        guard state.isWalkthroughRunning, engine.target.planID == Self.planID else { return nil }
        switch engine.step {
        case .read:
            return engine.readsRemaining == SessionRules.requiredReads
                ? "Read the verse aloud, then tap Read. Three times, so it is in your ear before you try to recall it."
                : "Once more."
        case .ladder:
            switch engine.level {
            case .none, .quarter:
                return "Now words start disappearing. Say the whole verse aloud, blanks and all, then tap I got it."
            case .half, .threeQuarters:
                return "More is hidden each time. Tap a blank to peek at one word — peeking is fine here, it only blocks the final pass."
            case .full:
                return "Everything is hidden. Say it from memory, then tap I know it."
            }
        case .cumulative:
            return "After each verse you recite everything so far together. This is what makes it a passage rather than a pile of verses."
        case .recitation:
            return "Both verses are learned. Recite them once through to finish the plan."
        case .carriedOver:
            return "You already know this one from elsewhere. Keep it, or work it again here."
        case .done:
            return nil
        }
    }
}

/// A tooltip: a short piece of guidance attached to the thing it describes.
///
/// Rendered inline next to its subject rather than floating over it, so it
/// never covers the control it is talking about and never clips at a screen
/// edge — including at accessibility text sizes, where a floating callout would
/// be most of the screen.
struct TipBubble: View {
    let text: String
    /// Which side of the bubble points at its subject.
    var caret: Edge = .bottom
    var onSkip: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if caret == .top { caretShape }
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(Typography.chrome(.footnote))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let onSkip {
                    Button("Skip walkthrough", action: onSkip)
                        .font(Typography.chrome(.caption))
                        .foregroundStyle(Palette.dimmedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.blankFill, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Palette.blankUnderline, lineWidth: 1)
            )
            if caret == .bottom { caretShape }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Walkthrough. \(text)")
    }

    private var caretShape: some View {
        Triangle()
            .fill(Palette.blankFill)
            .frame(width: 14, height: 7)
            .rotationEffect(.degrees(caret == .top ? 180 : 0))
            .padding(.leading, 22)
            .padding(caret == .top ? .bottom : .top, -1)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Attaches a tip beneath this view when there is one to show.
    @ViewBuilder
    func tip(_ text: String?, caret: Edge = .top, onSkip: (() -> Void)? = nil) -> some View {
        if let text {
            VStack(alignment: .leading, spacing: 0) {
                if caret == .bottom { TipBubble(text: text, caret: caret, onSkip: onSkip) }
                self
                if caret == .top { TipBubble(text: text, caret: caret, onSkip: onSkip) }
            }
        } else {
            self
        }
    }
}
