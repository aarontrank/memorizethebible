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
    /// What the user was in the middle of when the tour began.
    ///
    /// Opening the demo takes the resume point, the way any session does, so
    /// the walkthrough has to put the real work somewhere before it borrows it.
    /// Starting a tour from Settings must not cost you your place.
    public var parkedTarget: MemoryTargetID?
    public var parkedVerse: VerseRef?

    public init(
        isActive: Bool = false,
        hasBeenOffered: Bool = false,
        hasCompleted: Bool = false,
        parkedTarget: MemoryTargetID? = nil,
        parkedVerse: VerseRef? = nil
    ) {
        self.isActive = isActive
        self.hasBeenOffered = hasBeenOffered
        self.hasCompleted = hasCompleted
        self.parkedTarget = parkedTarget
        self.parkedVerse = parkedVerse
    }

    /// Offered on first launch only; after that it lives in Settings.
    public var shouldOfferOnLaunch: Bool { !hasBeenOffered && !isActive }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        hasBeenOffered = try container.decodeIfPresent(Bool.self, forKey: .hasBeenOffered) ?? false
        hasCompleted = try container.decodeIfPresent(Bool.self, forKey: .hasCompleted) ?? false
        parkedTarget = try container.decodeIfPresent(MemoryTargetID.self, forKey: .parkedTarget)
        parkedVerse = try container.decodeIfPresent(VerseRef.self, forKey: .parkedVerse)
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
        // Park the real work before the tour borrows the resume point. Not
        // parked over an earlier note: restarting a tour twice must not lose
        // the plan the first one set aside.
        if updated.onboarding.parkedTarget == nil,
            progress.currentTarget != .plan(BuiltInPlans.walkthroughID)
        {
            updated.onboarding.parkedTarget = progress.currentTarget
            updated.onboarding.parkedVerse = progress.currentVerse
        }
        updated.completedPlans.removeValue(forKey: BuiltInPlans.walkthroughID)
        updated.confirmedPlanBlocks.removeValue(forKey: BuiltInPlans.walkthroughID)
        updated.planCumulativeProgress.removeValue(forKey: BuiltInPlans.walkthroughID)
        updated.coveredUnits.removeValue(forKey: .plan(BuiltInPlans.walkthroughID))
        updated.hiddenBuiltInPlans.remove(BuiltInPlans.walkthroughID)
        // Not activated here: taking the demo on is one of the things the
        // walkthrough is teaching, so the user does it themselves.
        updated.activePlans.remove(BuiltInPlans.walkthroughID)
        return updated
    }

    /// Ends the walkthrough, whether finished or skipped.
    ///
    /// The demo plan goes; the verses it taught stay memorized, because the
    /// user did actually learn them and mastery belongs to the verse.
    /// Ending the walkthrough marks it done however it ended. Skipping it is a
    /// decision, not a failure, and the user should not be asked again either
    /// way; Settings starts it over.
    public func endingWalkthrough(_ progress: ProgressSnapshot) -> ProgressSnapshot {
        var updated = progress
        updated.onboarding.isActive = false
        updated.onboarding.hasBeenOffered = true
        updated.onboarding.hasCompleted = true
        updated.activePlans.remove(BuiltInPlans.walkthroughID)
        // Hand back whatever the tour borrowed. Psalm 1 is only the fallback for
        // a walkthrough begun before there was anywhere to park a place.
        if updated.currentTarget == .plan(BuiltInPlans.walkthroughID) {
            updated.currentTarget = updated.onboarding.parkedTarget ?? .chapter(ChapterRef(.psalms, 1))
            updated.currentVerse = updated.onboarding.parkedVerse
        }
        updated.onboarding.parkedTarget = nil
        updated.onboarding.parkedVerse = nil
        return updated
    }
}
