import BibleCore
import SwiftUI

/// Every screen the dashboard can push. One type so navigation stays in one
/// place as the app grew from 150 psalms to the whole Bible plus plans.
enum Route: Hashable {
    case session(MemoryTargetID)
    case review(MemoryTargetID)
    case books
    case chapters(BookID)
    case chapter(ChapterRef)
    case plans
    case milestones
    case milestone(MilestoneKind)
    case plan(String)
    case newPlan
    case editPlan(String)
    case settings
}

extension View {
    /// The shared destination table, so every list pushes the same screens.
    ///
    /// Every screen in the app opens through here, whoever pushed it, which is
    /// what makes it the one place that can tell when someone has walked off
    /// the walkthrough.
    func memorizeDestinations(route: Binding<[Route]>) -> some View {
        navigationDestination(for: Route.self) { destination in
            Group {
                switch destination {
                case let .session(target): SessionView(targetID: target)
                case let .review(target): ReviewView(targetID: target)
                case .books: BookListView()
                case let .chapters(book): ChapterListView(book: book)
                case let .chapter(ref): ChapterDetailView(ref: ref)
                case .plans: PlanListView()
                case .milestones: MilestoneListView()
                case let .milestone(kind): MilestoneDetailView(kind: kind)
                case let .plan(id): PlanDetailView(planID: id)
                case .newPlan: PlanEditorView(existing: nil)
                case let .editPlan(id): PlanEditorView(planID: id)
                case .settings: SettingsView()
                }
            }
            .modifier(WalkthroughScript(route: destination))
        }
    }
}

/// Ends the walkthrough when the screen being opened is not one the tour sends
/// you to. Attached to the destination itself rather than watched from the
/// dashboard, so it catches a screen however it was reached.
private struct WalkthroughScript: ViewModifier {
    let route: Route

    @Environment(AppState.self) private var state

    func body(content: Content) -> some View {
        content.onAppear { Walkthrough.endIfOffScript(state: state, opening: route) }
    }
}
