import StoreKit
import SwiftUI

/// Apple's rating prompt.
///
/// The asking is Apple's to do. Their prompt carries their own wording, offers
/// Not Now, and the system decides whether to show it at all and how often — a
/// few times a year at most, and never if the user has switched it off. That is
/// also what keeps the app inside guideline 3.2.2(x): nothing is withheld until
/// someone rates it, because this app cannot even tell whether they did.
///
/// Asked on the foreground-active scene explicitly, as Apple's guidance
/// recommends. SwiftUI's `requestReview` environment action resolves a scene of
/// its own and was silently doing nothing here.
enum ReviewPrompt {
    /// Returns false when there is no scene to ask on, so the caller can keep
    /// its turn rather than spending it on a prompt nobody saw.
    @MainActor
    @discardableResult
    static func ask() -> Bool {
        guard
            let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return false }
        AppStore.requestReview(in: scene)
        return true
    }
}
