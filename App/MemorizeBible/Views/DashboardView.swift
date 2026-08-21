import BibleCore
import SwiftUI

/// The root screen (§8.1), widened from 150 psalms to the whole Bible.
struct DashboardView: View {
    @Environment(AppState.self) private var state
    @Environment(Navigator.self) private var navigator
    @State private var showingWelcome = false
    @State private var showingSkipReminder = false
    @State private var showingWalkthroughFinished = false

    var body: some View {
        @Bindable var navigator = navigator
        return NavigationStack(path: $navigator.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    title
                    if let error = state.loadError {
                        errorBanner(error)
                    }
                    continueCard
                        .tip(
                            Walkthrough.continueTip(state: state),
                            caret: .bottom,
                            onSkip: skipWalkthrough
                        )
                    planSection
                    completedPlanSection
                    inProgressSection
                    memorizedSection
                    browseLinks
                        .tip(browseTip, caret: .top, onSkip: state.isWalkthroughRunning ? skipWalkthrough : nil)
                    // Last, not first: 31,086 verses is a number to glance at
                    // when you want it, not the thing that greets you.
                    overallSection
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 24)
                .frame(maxWidth: Metrics.scriptureMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background)
            .overlay {
                if state.celebrationCount > 0 {
                    FireworksView(trigger: state.celebrationCount)
                }
            }
            // The title is drawn in the content rather than left to the
            // navigation bar: a system large title truncates, and at
            // accessibility sizes "Memorize The Bible" loses the word that
            // matters. In content it wraps instead (§12).
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { navigator.push(.settings) } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .memorizeDestinations(route: $navigator.path)
            .sheet(isPresented: $showingWelcome) {
                WalkthroughWelcomeView(
                    onStart: {
                        state.startWalkthrough()
                        showingWelcome = false
                    },
                    onSkip: {
                        state.declineWalkthroughOffer()
                        showingWelcome = false
                        showingSkipReminder = true
                    }
                )
            }
            .sheet(isPresented: $showingWalkthroughFinished) {
                WalkthroughFinishedView { showingWalkthroughFinished = false }
            }
            .alert("Walkthrough skipped", isPresented: $showingSkipReminder) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can run it any time from Settings.")
            }
            // The walkthrough ends the moment its demo plan is finished, so the
            // congratulation and the plan's disappearance happen together.
            // Checked on appear as well as on change: finishing the demo and
            // then quitting would otherwise leave the walkthrough running
            // forever, with a completed plan and nothing left to do.
            .onChange(of: state.isWalkthroughRunning ? state.walkthroughProgress.isComplete : false) {
                _, _ in finishWalkthroughIfDemoComplete()
            }
            .onAppear {
                #if DEBUG
                    if DebugLaunch.celebrate { state.celebrate() }
                #endif
                finishWalkthroughIfDemoComplete()
                if state.shouldOfferWalkthrough { showingWelcome = true }
            }
            .task {
                #if DEBUG
                    if let route = DebugLaunch.initialRoute { navigator.path = [route] }
                #endif
            }
        }
    }

    /// The prompt under the browse links. It speaks up during the walkthrough,
    /// and whenever there is nothing to carry on with — a finished plan leaves
    /// the home screen with no obvious next move otherwise.
    private var browseTip: String? {
        if let tip = Walkthrough.browseTip(state: state) { return tip }
        guard resumableTarget == nil else { return nil }
        return "Nothing in progress. Pick a book or a plan to start something new."
    }

    private func finishWalkthroughIfDemoComplete() {
        guard state.isWalkthroughRunning, state.walkthroughProgress.isComplete else { return }
        state.endWalkthrough(completed: true)
        showingWalkthroughFinished = true
    }

    private func skipWalkthrough() {
        state.endWalkthrough(completed: false)
        showingSkipReminder = true
    }

    private var title: some View {
        Text("Memorize The Bible")
            .font(Typography.chrome(.largeTitle).weight(.bold))
            .foregroundStyle(Palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Overall

    private var overallSection: some View {
        let overall = state.overall
        return VStack(alignment: .leading, spacing: 8) {
            ProgressBar(fraction: overall.fraction, height: 4)
            Text(overallCaption(overall))
                .font(Typography.chrome(.footnote))
                .foregroundStyle(Palette.dimmedText)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Overall progress. \(overallCaption(overall))")
    }

    private func overallCaption(_ overall: OverallProgress) -> String {
        guard overall.masteredVerses > 0 else {
            return "\(overall.verseCount.formatted()) verses · nothing memorized yet"
        }
        var parts = ["\(overall.masteredVerses.formatted()) of \(overall.verseCount.formatted()) verses"]
        if overall.memorizedChapters > 0 {
            let noun = overall.memorizedChapters == 1 ? "chapter" : "chapters"
            parts.append("\(overall.memorizedChapters) \(noun)")
        }
        if overall.completedPlans > 0 {
            let noun = overall.completedPlans == 1 ? "plan" : "plans"
            parts.append("\(overall.completedPlans) \(noun)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Continue

    /// What Continue would resume, if there is anything. A finished target is
    /// nothing to continue — offering it would be a dead end.
    private var resumableTarget: MemoryTarget? {
        guard let target = state.target(for: state.progress.currentTarget),
            !target.units.isEmpty,
            !state.isComplete(target.id)
        else { return nil }
        return target
    }

    @ViewBuilder
    private var continueCard: some View {
        if let target = resumableTarget {
            let done = masteredCount(in: target)
            Button {
                navigator.push(.session(target.id))
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Continue")
                        .font(Typography.chrome(.caption))
                        .foregroundStyle(Palette.dimmedText)
                        .textCase(.uppercase)
                    Text(target.title)
                        .font(Typography.scripture(.title2))
                        .foregroundStyle(Palette.text)
                    Text(continueSubtitle(target: target, mastered: done))
                        .font(Typography.chrome(.subheadline))
                        .foregroundStyle(Palette.dimmedText)
                    ProgressBar(
                        fraction: target.units.isEmpty
                            ? 0 : Double(done) / Double(target.units.count)
                    )
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Palette.progressTrack.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Resumes your session")
        }
    }

    private func masteredCount(in target: MemoryTarget) -> Int {
        target.units.reduce(into: 0) { total, ref in
            if state.progress.state(for: ref).status == .mastered { total += 1 }
        }
    }

    private func continueSubtitle(target: MemoryTarget, mastered: Int) -> String {
        guard !target.units.isEmpty else { return "Nothing to memorize here" }
        let position = state.progress.currentVerse.flatMap { target.position(of: $0) }.map { $0 + 1 }
        let where_ = position.map { "Verse \($0) of \(target.units.count)" }
            ?? "\(target.units.count) verses"
        return "\(where_) · \(mastered) memorized"
    }

    // MARK: - Plans

    @ViewBuilder
    private var planSection: some View {
        let inProgress = state.plans.filter {
            let progress = state.planProgress($0)
            return progress.isStarted && !progress.isComplete
        }
        if inProgress.isEmpty && completedPlans.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Plans") { navigator.push(.plans) }
                Text("Memorize a set of verses together — the Roman Road, the Sermon on the Mount, or your own.")
                    .font(Typography.chrome(.footnote))
                    .foregroundStyle(Palette.dimmedText)
                Button("Browse plans") { navigator.push(.plans) }
                    .font(Typography.chrome(.subheadline))
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.text)
            }
        } else if !inProgress.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // Named as a pair with "Completed plans" below, so neither
                // header reads as though it holds every plan.
                sectionHeader("Plans in progress") { navigator.push(.plans) }
                ForEach(inProgress) { plan in
                    let progress = state.planProgress(plan)
                    Button { navigator.push(.plan(plan.id)) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.title)
                                    .font(Typography.scripture(.body))
                                    .foregroundStyle(Palette.text)
                                Text("\(progress.masteredCount) of \(progress.unitCount) verses")
                                    .font(Typography.chrome(.caption))
                                    .foregroundStyle(Palette.dimmedText)
                            }
                            Spacer(minLength: 12)
                            ProgressBar(fraction: progress.fraction, height: 4).frame(width: 56)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Plans finished, kept where they can be picked up again. Review is the
    /// only thing left to do with them, and it cannot disturb the result.
    @ViewBuilder
    private var completedPlanSection: some View {
        if !completedPlans.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Completed plans", action: nil)
                ForEach(completedPlans) { plan in
                    let progress = state.planProgress(plan)
                    Button { navigator.push(.review(.plan(plan.id))) } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(plan.title)
                                        .font(Typography.scripture(.body))
                                        .foregroundStyle(Palette.text)
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Palette.dimmedText)
                                }
                                Text("\(progress.unitCount) verses memorized")
                                    .font(Typography.chrome(.caption))
                                    .foregroundStyle(Palette.dimmedText)
                            }
                            Spacer(minLength: 12)
                            Text("Review")
                                .font(Typography.chrome(.footnote))
                                .foregroundStyle(Palette.dimmedText)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(plan.title). Memorized. Opens review.")
                }
            }
        }
    }

    /// Completed plans, most recently finished first.
    private var completedPlans: [MemoryPlan] {
        state.plans
            .filter { state.planProgress($0).isComplete }
            .sorted {
                (state.progress.completedPlans[$0.id] ?? .distantPast)
                    > (state.progress.completedPlans[$1.id] ?? .distantPast)
            }
    }

    // MARK: - In progress and memorized

    @ViewBuilder
    private var inProgressSection: some View {
        // Chapters the user has actually worked as chapters. A plan quoting a
        // verse from Romans 3 does not make Romans 3 something you started.
        let chapters = state.report.chaptersInProgress(in: state.progress)
        if !chapters.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("In progress", action: nil)
                ForEach(chapters.prefix(6)) { chapter in
                    chapterRow(chapter, route: .session(.chapter(chapter.ref)))
                }
            }
        }
    }

    @ViewBuilder
    private var memorizedSection: some View {
        let memorized = state.report.memorizedChapters(in: state.progress)
        if !memorized.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Memorized", action: nil)
                ForEach(memorized.prefix(8)) { chapter in
                    Button { navigator.push(.review(.chapter(chapter.ref))) } label: {
                        HStack {
                            Text(state.title(for: chapter.ref))
                                .font(Typography.scripture(.body))
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Text("Review")
                                .font(Typography.chrome(.footnote))
                                .foregroundStyle(Palette.dimmedText)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chapterRow(_ chapter: ChapterProgress, route: Route) -> some View {
        Button { navigator.push(route) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title(for: chapter.ref))
                        .font(Typography.scripture(.body))
                        .foregroundStyle(Palette.text)
                    Text("\(chapter.masteredCount) of \(chapter.unitCount) verses")
                        .font(Typography.chrome(.caption))
                        .foregroundStyle(Palette.dimmedText)
                }
                Spacer(minLength: 12)
                ProgressBar(fraction: chapter.fraction, height: 4).frame(width: 56)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chrome

    private func sectionHeader(_ title: String, action: (() -> Void)?) -> some View {
        HStack {
            Text(title)
                .font(Typography.chrome(.caption))
                .foregroundStyle(Palette.dimmedText)
                .textCase(.uppercase)
            Spacer()
            if let action {
                Button("All", action: action)
                    .font(Typography.chrome(.caption))
                    .foregroundStyle(Palette.dimmedText)
            }
        }
    }

    private func sectionHeader(_ title: String, action: @escaping () -> Void) -> some View {
        sectionHeader(title, action: Optional(action))
    }

    private var browseLinks: some View {
        VStack(spacing: 0) {
            navRow("All books", route: .books)
            Divider().overlay(Palette.progressTrack)
            navRow("All plans", route: .plans)
        }
    }

    private func navRow(_ title: String, route: Route) -> some View {
        Button { navigator.push(route) } label: {
            HStack {
                Text(title)
                    .font(Typography.chrome(.body))
                    .foregroundStyle(Palette.text)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.verseNumber)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(Typography.chrome(.footnote))
            .foregroundStyle(Palette.text)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.blankFill, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// §9: a flat bar in the two progress colors. No gradient, no shadow.
struct ProgressBar: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.progressTrack)
                Capsule()
                    .fill(Palette.progressFill)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
