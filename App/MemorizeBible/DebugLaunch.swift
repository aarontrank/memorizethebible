#if DEBUG
    import Foundation
    import BibleCore

    /// Debug-build launch options, for driving the UI into a specific state
    /// without tapping through it by hand.
    ///
    /// Compiled out of Release entirely. Nothing here reads or writes the real
    /// progress file: `-uiDebug` swaps in a throwaway one.
    ///
    ///     xcrun simctl launch <sim> memorizethebible.aarontrank.com \
    ///         -uiDebug -debugBook PSA -debugChapter 23 -debugSeed ladder4
    ///
    /// Seeds: `read`, `ladder1`…`ladder4`, `cumulative`, `partial`,
    /// `recitation`, `memorized`.
    enum DebugLaunch {
        private static let arguments = ProcessInfo.processInfo.arguments

        static var isActive: Bool { arguments.contains("-uiDebug") }

        static var book: BookID { BookID(value(for: "-debugBook") ?? "PSA") }
        static var chapter: Int? { value(for: "-debugChapter").flatMap(Int.init) }
        static var planID: String? { value(for: "-debugPlan") }
        static var seed: String? { value(for: "-debugSeed") }

        /// `session` (default), `review`, `books`, `chapters`, `plans`, `plan`,
        /// `newPlan`, `settings`, or `dashboard`.
        static var screen: String? { value(for: "-debugScreen") }

        static var includeHeadings: Bool { arguments.contains("-debugHeadings") }

        /// Sets the celebration off on launch, so the fireworks can be seen
        /// without finishing something first.
        static var celebrate: Bool { arguments.contains("-debugCelebrate") }

        /// Puts the walkthrough into its running state without the welcome
        /// sheet, so its tips can be inspected screen by screen.
        static var walkthroughRunning: Bool { arguments.contains("-debugWalkthrough") }

        /// Puts onboarding in its finished state: no welcome sheet, no tips,
        /// and no demo plan in the list. What the app looks like once someone
        /// is actually using it, which is what a screenshot should show.
        static var onboarded: Bool { arguments.contains("-debugOnboarded") }

        /// Rotates the scene to landscape on launch, so the layout can be
        /// screenshot in that orientation without a keystroke into Simulator.
        static var landscape: Bool { arguments.contains("-debugLandscape") }

        /// Seeds one plan of the user's own and one that arrived shared, so
        /// both sections of the Plans page and the share button can be seen.
        static var seedPlans: Bool { arguments.contains("-debugSeedPlans") }

        /// Hides the built-in plans, so the sections below them are on screen
        /// without a scroll a screenshot cannot perform.
        static var hideBuiltInPlans: Bool { arguments.contains("-debugHideBuiltInPlans") }

        static let ownPlanID = "debug.own"
        static let sharedPlanID = "debug.shared"

        static var seededPlans: [MemoryPlan] {
            guard seedPlans else { return [] }
            return [
                MemoryPlan(
                    id: ownPlanID,
                    title: "Verses for a hard week",
                    summary: "Five to hold on to.",
                    passages: [
                        PassageRef(BookID("ROM"), 8, 28),
                        PassageRef(BookID("PSA"), 23, 1, 4),
                        PassageRef(BookID("PHP"), 4, 6, 7),
                    ]
                ),
                MemoryPlan(
                    id: sharedPlanID,
                    title: "What Marta sent",
                    summary: "Her favourites.",
                    passages: [PassageRef(BookID("JHN"), 1, 1, 3)],
                    origin: .shared
                ),
            ]
        }

        /// A plan link to hand straight to the URL handler on launch.
        /// `simctl openurl` raises a system confirmation no script can tap;
        /// this skips that prompt and exercises everything behind it.
        static var openURL: URL? { value(for: "-debugOpenURL").flatMap(URL.init(string:)) }

        /// Accepts the arriving plan without waiting for a tap on Save.
        static var acceptShare: Bool { arguments.contains("-debugAcceptShare") }

        /// Writes both progress cards to the app container as PNGs, so the
        /// shared artifact itself can be inspected rather than a screenshot of
        /// a menu that opens it.
        static var writeCards: Bool { arguments.contains("-debugWriteCards") }

        /// Initial mask level for Review, 0...4.
        static var level: Int? { value(for: "-debugLevel").flatMap(Int.init) }

        /// Marks another plan complete, so both plan sections can be seen at
        /// once. Repeatable is not needed; one extra is enough to check layout.
        static var completedPlanID: String? { value(for: "-debugCompletePlan") }

        /// Marks the target's first N units as already worked here, so a
        /// session can be dropped at a chosen point.
        static var workedThrough: Int? { value(for: "-debugWorkedThrough").flatMap(Int.init) }

        /// How many days ago the seeded work happened.
        static var dayOffset: Int { value(for: "-debugDayOffset").flatMap(Int.init) ?? 0 }

        private static var onboardingState: OnboardingState {
            if walkthroughRunning {
                return OnboardingState(isActive: true, hasBeenOffered: true)
            }
            if onboarded {
                return OnboardingState(isActive: false, hasBeenOffered: true, hasCompleted: true)
            }
            return OnboardingState()
        }

        private static func value(for flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }

        static func progressFileURL() -> URL {
            URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("memorize-bible-uidebug.json")
        }

        static var targetID: MemoryTargetID? {
            if let planID { return .plan(planID) }
            if let chapter { return .chapter(ChapterRef(book, chapter)) }
            return nil
        }

        static var initialRoute: Route? {
            switch screen {
            case "review": return targetID.map { Route.review($0) }
            case "books": return .books
            case "chapters": return .chapters(book)
            case "plans": return .plans
            case "plan": return planID.map { Route.plan($0) }
            case "newPlan": return .newPlan
            case "settings": return .settings
            case "dashboard": return nil
            default: return targetID.map { Route.session($0) }
            }
        }

        /// Builds a snapshot that lands the target on the requested step.
        static func seededProgress(content: ContentStore, clock: any AppClock) -> ProgressSnapshot? {
            guard let targetID else {
                guard walkthroughRunning || onboarded || seedPlans else { return nil }
                var snapshot = ProgressSnapshot()
                snapshot.customPlans = seededPlans
                if hideBuiltInPlans {
                    snapshot.hiddenBuiltInPlans = Set(BuiltInPlans.all.map(\.id))
                }
                snapshot.onboarding = onboardingState
                return snapshot
            }
            var snapshot = ProgressSnapshot()
            snapshot.customPlans = seededPlans
            snapshot.includeSuperscriptions = includeHeadings
            snapshot.currentTarget = targetID
            snapshot.onboarding = onboardingState

            let report = ProgressReport(content: content, clock: clock)
            let target: MemoryTarget?
            switch targetID {
            case let .chapter(ref):
                target = (try? content.chapter(ref)).map { report.target(for: $0, in: snapshot) }
            case let .plan(id):
                target = report.plan(id: id, in: snapshot).map { report.target(for: $0, in: snapshot) }
            }
            guard let target, !target.isEmpty else { return snapshot }

            let workDate =
                clock.calendar.date(byAdding: .day, value: -dayOffset, to: clock.now) ?? clock.now

            func read(_ ref: VerseRef) {
                snapshot.update(ref) { state in
                    state.status = .inProgress
                    state.readCount = SessionRules.requiredReads
                }
            }
            func cleared(_ ref: VerseRef, level: Int) {
                read(ref)
                snapshot.update(ref) { $0.highestMaskLevelCleared = level }
            }
            func mastered(_ ref: VerseRef) {
                cleared(ref, level: 4)
                snapshot.update(ref) { state in
                    state.status = .mastered
                    state.masteredAt = workDate
                }
                snapshot.markCovered(ref, by: targetID)
                if case let .chapter(chapterRef) = targetID {
                    snapshot.update(chapterRef) { $0.startedAt = workDate }
                }
            }
            func cumulativeThrough(_ refs: [VerseRef]) {
                guard let last = refs.last else { return }
                if let chapterRef = target.chapterRef {
                    snapshot.update(chapterRef) { $0.cumulativeConfirmedThrough = last.verse }
                } else if let planID = target.planID {
                    snapshot.planCumulativeProgress[planID] = refs.count
                }
            }

            if let workedThrough, workedThrough > 0 {
                let done = Array(target.units.prefix(workedThrough))
                done.forEach(mastered)
                cumulativeThrough(done)
            }

            switch seed {
            case "read":
                break
            case "ladder1", "ladder2", "ladder3", "ladder4":
                let level = Int(seed?.suffix(1) ?? "1") ?? 1
                cleared(target.units[0], level: max(level - 1, 0))
            case "cumulative":
                mastered(target.units[0])
            case "partial":
                let count = min(3, target.units.count)
                let done = Array(target.units.prefix(count))
                done.forEach(mastered)
                cumulativeThrough(done)
                snapshot.currentVerse = target.units.count > count ? target.units[count] : done.last
            case "recitation", "memorized":
                target.units.forEach(mastered)
                cumulativeThrough(target.units)
                if seed == "memorized" {
                    if let chapterRef = target.chapterRef {
                        snapshot.update(chapterRef) { state in
                            if target.blocks.count > 1 {
                                state.confirmedStanzas = Set(target.blocks.map(\.index))
                            } else {
                                state.fullRecitationConfirmed = true
                            }
                            state.completedAt = workDate
                        }
                    } else if let planID = target.planID {
                        snapshot.confirmedPlanBlocks[planID] = Set(target.blocks.map(\.index))
                        snapshot.completedPlans[planID] = workDate
                    }
                }
            default:
                break
            }

            if let completedID = completedPlanID,
                let plan = report.plan(id: completedID, in: snapshot)
            {
                let completed = report.target(for: plan, in: snapshot)
                for ref in completed.units {
                    snapshot.update(ref) { state in
                        state.status = .mastered
                        state.masteredAt = workDate
                        state.readCount = SessionRules.requiredReads
                        state.highestMaskLevelCleared = 4
                    }
                }
                for ref in completed.units { snapshot.markCovered(ref, by: .plan(completedID)) }
                snapshot.planCumulativeProgress[completedID] = completed.units.count
                snapshot.confirmedPlanBlocks[completedID] = Set(completed.blocks.map(\.index))
                snapshot.completedPlans[completedID] = workDate
            }
            return snapshot
        }
    }
#endif
