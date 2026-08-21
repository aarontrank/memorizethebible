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
}
