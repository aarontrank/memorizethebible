import Foundation

/// Whether the user has been walked through the app, and whether they are
/// being walked through it right now.
public struct OnboardingState: Codable, Hashable, Sendable {
    /// The walkthrough is running. This is also what makes the demo plan
    /// visible — it exists only for the walkthrough.
    public var isActive: Bool
    /// The walkthrough has been offered at least once, so a user who skipped it
    /// is not asked again every launch.
    public var hasBeenOffered: Bool
    /// Ran all the way to the end at least once.
    public var hasCompleted: Bool

    public init(isActive: Bool = false, hasBeenOffered: Bool = false, hasCompleted: Bool = false) {
        self.isActive = isActive
        self.hasBeenOffered = hasBeenOffered
        self.hasCompleted = hasCompleted
    }

    /// Offered on first launch only; after that it lives in Settings.
    public var shouldOfferOnLaunch: Bool { !hasBeenOffered && !isActive }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        hasBeenOffered = try container.decodeIfPresent(Bool.self, forKey: .hasBeenOffered) ?? false
        hasCompleted = try container.decodeIfPresent(Bool.self, forKey: .hasCompleted) ?? false
    }
}

extension BuiltInPlans {
    /// The demo plan the walkthrough is built around.
    ///
    /// Two of the shortest verses in the Bible — seven words together — so the
    /// whole loop can be walked in a minute rather than becoming a chore. It is
    /// listed only while the walkthrough is running, and disappears when the
    /// walkthrough ends.
    public static let walkthrough = MemoryPlan(
        id: "builtin.walkthrough",
        title: "Walkthrough Demo",
        summary: "Two very short verses, to show how a plan works.",
        passages: [PassageRef(BookID("1TH"), 5, 16, 17)],
        isBuiltIn: true
    )

    public static let walkthroughID = walkthrough.id
}

extension ProgressReport {
    /// The demo plan, whether or not it is currently listed.
    public var walkthroughPlan: MemoryPlan { BuiltInPlans.walkthrough }

    /// Starts the walkthrough from the beginning, clearing anything left from a
    /// previous run so it always demonstrates the same thing.
    public func startingWalkthrough(_ progress: ProgressSnapshot) -> ProgressSnapshot {
        var updated = progress
        updated.onboarding.isActive = true
        updated.onboarding.hasBeenOffered = true
        updated.completedPlans.removeValue(forKey: BuiltInPlans.walkthroughID)
        updated.confirmedPlanBlocks.removeValue(forKey: BuiltInPlans.walkthroughID)
        updated.planCumulativeProgress.removeValue(forKey: BuiltInPlans.walkthroughID)
        updated.coveredUnits.removeValue(forKey: .plan(BuiltInPlans.walkthroughID))
        updated.hiddenBuiltInPlans.remove(BuiltInPlans.walkthroughID)
        return updated
    }

    /// Ends the walkthrough, whether finished or skipped.
    ///
    /// The demo plan goes; the verses it taught stay memorized, because the
    /// user did actually learn them and mastery belongs to the verse.
    public func endingWalkthrough(_ progress: ProgressSnapshot, completed: Bool) -> ProgressSnapshot {
        var updated = progress
        updated.onboarding.isActive = false
        updated.onboarding.hasBeenOffered = true
        if completed { updated.onboarding.hasCompleted = true }
        if updated.currentTarget == .plan(BuiltInPlans.walkthroughID) {
            updated.currentTarget = .chapter(ChapterRef(.psalms, 1))
            updated.currentVerse = nil
        }
        return updated
    }
}
