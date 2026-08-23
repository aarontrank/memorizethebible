import BibleCore
import SwiftUI

/// Memorize The Bible — a single-purpose, fully offline app for memorizing
/// scripture.
///
/// No account, no network, no analytics, no in-app purchases (§13). The only
/// framework dependencies are Apple's; the only data is in the app container.
@main
struct MemorizeBibleApp: App {
    @State private var state: AppState
    @State private var navigator = Navigator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before any view is built, so the first frame is already set in Literata.
        ScriptureFont.register()
        _state = State(initialValue: AppState.live())
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(state)
                .environment(navigator)
                // Above the navigation stack, not inside it: the walkthrough
                // can be skipped from a session, and the notice has to appear
                // wherever that happened.
                .alert(
                    "Walkthrough skipped",
                    isPresented: Bindable(state).isShowingWalkthroughSkipNotice
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("You can run it again any time from Settings.")
                }
                .tint(Palette.text)
                .background(Palette.background)
                // Shared plans arrive as links. Everything the plan is travels
                // inside the URL, so this reads it and asks; it fetches nothing.
                .onOpenURL { state.open($0) }
                #if DEBUG
                    .onAppear { if DebugLaunch.writeCards { DebugCards.write() } }
                    .onAppear {
                        guard let url = DebugLaunch.openURL else { return }
                        state.open(url)
                        if DebugLaunch.acceptShare,
                            case let .plan(plan, _)? = state.sharedPlanArrival
                        {
                            state.saveSharedPlan(plan)
                        }
                    }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                state.didEnterForeground()
                #if DEBUG
                    DebugLandscape.applyIfRequested()
                #endif
            case .background: state.didEnterBackground()
            default: break
            }
        }
    }
}

#if DEBUG
    /// Turns `-debugLandscape` into a real rotation request, so verification
    /// screenshots go through the same path a physical rotation does.
    private enum DebugLandscape {
        @MainActor
        static func applyIfRequested() {
            guard DebugLaunch.landscape else { return }
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
                print("debug landscape rotation failed: \(error)")
            }
        }
    }
#endif

#if DEBUG
    /// Renders the share cards straight to disk for inspection.
    private enum DebugCards {
        @MainActor
        static func write() {
            let samples: [(String, ProgressCardContent)] = [
                (
                    "card-progress",
                    ProgressCardContent(
                        kind: "Chapter", title: "Psalm 23",
                        memorized: 4, total: 6, isComplete: false, completedAt: nil
                    )
                ),
                (
                    "card-complete",
                    ProgressCardContent(
                        kind: "Plan", title: "The Roman Road",
                        memorized: 6, total: 6, isComplete: true, completedAt: Date()
                    )
                ),
                (
                    "card-long",
                    ProgressCardContent(
                        kind: "Plan", title: "Verses for a hard week, and the ones after it",
                        memorized: 112, total: 431, isComplete: false, completedAt: nil
                    )
                ),
            ]
            let directory = URL.documentsDirectory
            for (name, content) in samples {
                let renderer = ImageRenderer(content: ProgressCardView(content: content))
                renderer.scale = 2
                renderer.proposedSize = ProposedViewSize(ProgressCardView.size)
                guard let data = renderer.uiImage?.pngData() else { continue }
                try? data.write(to: directory.appendingPathComponent("\(name).png"))
            }
        }
    }
#endif
