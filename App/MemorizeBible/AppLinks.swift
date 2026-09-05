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
    static let appStore = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!

    /// Opens the App Store with the review sheet already up.
    ///
    /// A button has to do something when it is pressed, and `requestReview`
    /// cannot promise that: the system shows its prompt a few times a year at
    /// most, declines silently the rest of the time, and the user can switch it
    /// off altogether. So the button people go looking for links straight to
    /// the App Store, and the system prompt is left for the moments nobody
    /// asked for it.
    static let appStoreReview = URL(
        string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review"
    )!

    private static let appStoreID = "6803717306"
}
