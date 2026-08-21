import BibleCore
import SwiftUI

/// Memorize The Bible — a single-purpose, fully offline app for memorizing the
/// book of Psalms.
///
/// No account, no network, no analytics, no in-app purchases (§13). The only
/// framework dependencies are Apple's; the only data is in the app container.
@main
struct MemorizeBibleApp: App {
    @State private var state: AppState
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
                .tint(Palette.text)
                .background(Palette.background)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: state.didEnterForeground()
            case .background: state.didEnterBackground()
            default: break
            }
        }
    }
}
