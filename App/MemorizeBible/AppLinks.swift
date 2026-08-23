import Foundation

/// Links that point outside the app.
///
/// The app is otherwise entirely offline (§13); these are addresses written
/// into a message the user sends, never anything the app itself fetches.
enum AppLinks {
    /// Sent alongside a shared plan so a recipient without the app has
    /// somewhere to go.
    ///
    /// The locale-agnostic form rather than `/us/`: the App Store redirects it
    /// to whichever storefront the person opening it belongs to, and a plan is
    /// as likely to be sent abroad as not.
    static let appStore = URL(string: "https://apps.apple.com/app/id6803717306")!
}
