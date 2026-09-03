import Observation
import SwiftUI

/// The dashboard's navigation path, shared so a screen deep in the stack can
/// send the user home.
///
/// Finishing a plan should land you on the home screen, not back on the plan
/// detail you happened to come through, and only the owner of the path can do
/// that.
@Observable
@MainActor
final class Navigator {
    var path: [Route] = []

    func push(_ route: Route) { path.append(route) }

    func popToRoot() { path.removeAll() }

    /// Clears the stack and opens one screen straight off the home page.
    ///
    /// Taking something on ends the browsing that found it: Back should go
    /// home, not back through the books and lists you rummaged through on the
    /// way here.
    func reset(to route: Route) { path = [route] }
}
