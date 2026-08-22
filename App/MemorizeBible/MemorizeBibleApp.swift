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
                .tint(Palette.text)
                .background(Palette.background)
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
