import BibleCore
import SwiftUI

/// Every screen the dashboard can push. One type so navigation stays in one
/// place as the app grew from 150 psalms to the whole Bible plus plans.
enum Route: Hashable {
    case session(MemoryTargetID)
    case review(MemoryTargetID)
    case books
    case chapters(BookID)
    case plans
    case plan(String)
    case newPlan
    case editPlan(String)
    case settings
}

extension View {
    /// The shared destination table, so every list pushes the same screens.
    func memorizeDestinations(route: Binding<[Route]>) -> some View {
        navigationDestination(for: Route.self) { destination in
            switch destination {
            case let .session(target): SessionView(targetID: target)
            case let .review(target): ReviewView(targetID: target)
            case .books: BookListView()
            case let .chapters(book): ChapterListView(book: book)
            case .plans: PlanListView()
            case let .plan(id): PlanDetailView(planID: id)
            case .newPlan: PlanEditorView(existing: nil)
            case let .editPlan(id): PlanEditorView(planID: id)
            case .settings: SettingsView()
            }
        }
    }
}
