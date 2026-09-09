import BibleCore
import SwiftUI

/// Settings (§8.4).
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @State private var showHeadingsConfirmation = false
    @State private var reopenedChapters: [ChapterRef] = []
    @State private var isConfirmingReset = false
    /// The reset sheet opens to the height of its own content. Measured rather
    /// than guessed: the warning is three lines at the default text size and
    /// nine at the accessibility ones, and a fixed height would either crop it
    /// there or leave a hole here.
    @State private var resetSheetHeight: CGFloat = 260

    var body: some View {
        @Bindable var state = state
        List {
            spreadTheWordSection
            remindersSection
            headingsSection
            walkthroughSection
            iCloudSection
            aboutSection
            // Always last: the one thing here that cannot be undone.
            resetSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        // A sheet rather than a panel unfolding at the foot of a long list,
        // where it opened below the fold and had to be scrolled to before it
        // could be read — the last place to hide the one irreversible thing.
        .sheet(isPresented: $isConfirmingReset) {
            ResetProgressView(
                warning: resetWarning,
                contentHeight: $resetSheetHeight,
                onErase: {
                    state.resetProgress()
                    isConfirmingReset = false
                },
                onCancel: { isConfirmingReset = false }
            )
            .presentationDetents([.height(resetSheetHeight)])
        }
        .confirmationDialog(
            "Include psalm headings?",
            isPresented: $showHeadingsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Include headings") { state.setIncludeSuperscriptions(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            // §7.5: surface the consequence rather than silently reopening.
            Text(
                reopenedChapters.count == 1
                    ? "1 memorized psalm will reopen so you can learn its heading."
                    : "\(reopenedChapters.count) memorized psalms will reopen so you can learn their headings."
            )
        }
    }

    // MARK: - Reminders (§10)

    private var remindersSection: some View {
        Section {
            Toggle(
                "Daily reminder",
                isOn: Binding(
                    get: { state.progress.notificationsEnabled },
                    set: { enabled in Task { await state.setNotificationsEnabled(enabled) } }
                )
            )
            // §9: the app tints everything with the ink colour, which inverts to
            // near-white in dark mode — and a near-white switch carrying a white
            // knob reads as one blank capsule. The gold says "on" in both.
            .tint(Palette.accent)
            if state.progress.notificationsEnabled {
                DatePicker(
                    "Reminder time",
                    selection: Binding(
                        get: { reminderDate },
                        set: { state.setReminderTime(ReminderTime(from: $0, calendar: state.clock.calendar)) }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("You'll only be reminded after a full day away. Reminders are scheduled on this device; nothing is sent anywhere.")
        }
    }

    private var reminderDate: Date {
        var components = state.clock.calendar.dateComponents([.year, .month, .day], from: state.clock.now)
        components.hour = state.progress.reminderTime.hour
        components.minute = state.progress.reminderTime.minute
        return state.clock.calendar.date(from: components) ?? state.clock.now
    }

    // MARK: - iCloud (§13.1)

    /// On by default, and one tap from off. What it syncs is the progress
    /// record and nothing else — there is no account to make and no server of
    /// this app's to send anything to.
    private var iCloudSection: some View {
        Section {
            Toggle(
                "Sync with iCloud",
                isOn: Binding(
                    get: { state.isCloudSyncEnabled },
                    set: { state.setCloudSyncEnabled($0) }
                )
            )
            .tint(Palette.accent)
            if state.isCloudSyncEnabled, let note = cloudStatusNote {
                Text(note)
                    .font(Typography.chrome(.footnote))
                    .foregroundStyle(Palette.dimmedText)
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(
                "Keeps a copy of your progress in your own iCloud account, so a new iPhone or "
                    + "iPad picks up where the old one left off. Work done on two devices is "
                    + "combined rather than replaced — nothing you have memorized is ever "
                    + "dropped for being the older copy.\n\n"
                    + "Turn it off and your progress stays on this device alone. The copy already "
                    + "in iCloud is left where it is; erasing your progress below removes it.\n\n"
                    + "Syncing also has to be switched on for this app in the device's own iCloud "
                    + "settings. Turning it off there stops the copy without changing this switch."
            )
        }
    }

    /// Said plainly, and only when there is something to say — which means
    /// only when something is wrong. Every one of these ends the same way: the
    /// work on this device is safe either way.
    ///
    /// There is deliberately no line for the good case. The app hands the
    /// record to iOS and never learns what iOS did with it: iCloud switched
    /// off for this app in the device's own settings looks, from in here,
    /// exactly like iCloud working. Reporting a send under those conditions
    /// was telling people something the app could not know, so it says
    /// nothing, and the switch being on is the whole of the claim.
    private var cloudStatusNote: String? {
        switch state.cloudSyncStatus {
        case .idle, .synced:
            return state.isCloudReachable ? nil : "Waiting for iCloud."
        case .unavailable:
            return "Sign in to iCloud on this device to sync. Your progress is safe here meanwhile."
        case .refusedNewerRecord:
            return "The copy in iCloud was saved by a newer version of the app, so it has been "
                + "left alone. Update to sync with it."
        case .tooLarge:
            return "There is no room left in iCloud for your progress. It is all still on this device."
        case .accountChanged:
            return "The iCloud account on this device changed. Reopen the app to sync with it."
        case let .failed(message):
            return "iCloud could not be reached: \(message)"
        }
    }

    // MARK: - Headings (§7.5)

    private var headingsSection: some View {
        Section {
            Toggle(
                "Include psalm headings",
                isOn: Binding(
                    get: { state.progress.includeSuperscriptions },
                    set: { include in
                        guard include else {
                            // Disabling hides index 0 and excludes it from all
                            // counts, but never deletes its state.
                            state.setIncludeSuperscriptions(false)
                            return
                        }
                        reopenedChapters = state.chaptersReopenedByIncludingHeadings()
                        if reopenedChapters.isEmpty {
                            state.setIncludeSuperscriptions(true)
                        } else {
                            showHeadingsConfirmation = true
                        }
                    }
                )
            )
            .tint(Palette.accent)
        } header: {
            // Scoped to Psalms in the header, because that is genuinely the
            // only book with these: 116 psalms carry one and nothing else in
            // the Bible does.
            Text("Psalms")
        } footer: {
            Text(
                "116 psalms open with a line like \"For the choirmaster. A Psalm of David.\" "
                    + "No other book has them. They are part of the text, unlike the section "
                    + "titles a translation adds, which this app never shows.\n\n"
                    + "Off by default: headings are displayed but not memorized. Turning this "
                    + "back off keeps any heading work you have already done."
            )
        }
    }

    // MARK: - Walkthrough

    private var walkthroughSection: some View {
        Section {
            Button(state.isWalkthroughRunning ? "Restart the walkthrough" : "Show the walkthrough") {
                state.startWalkthrough()
                dismiss()
            }
            if state.isWalkthroughRunning {
                Button("Stop the walkthrough", role: .destructive) {
                    Walkthrough.skip(state: state, navigator: navigator)
                }
            }
        } header: {
            Text("Walkthrough")
        } footer: {
            Text("A guided tour of a plan, using a demo of two very short verses. The demo appears only while the walkthrough is running.")
        }
    }

    // MARK: - Rating and sharing

    /// The two outward-facing things a person might want to do on purpose.
    ///
    /// Rating links to the App Store rather than calling `requestReview`: a
    /// button someone went looking for has to work every time they press it,
    /// and the system prompt makes no such promise. See `AppLinks`.
    private var spreadTheWordSection: some View {
        Section {
            Link(destination: AppLinks.appStoreReview) {
                Label("Rate this app", systemImage: "star")
            }
            ShareLink(
                item: AppLinks.appStore,
                subject: Text("Memorize The Bible"),
                message: Text(Self.shareMessage)
            ) {
                Label("Tell someone about it", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Spread the word")
        } footer: {
            Text("Sharing sends a link and nothing else — no contacts are read and nothing is recorded.")
        }
    }

    /// Goes in the body of whatever they send. The link travels beside it, so
    /// this says what the app is rather than repeating the address.
    private static let shareMessage =
        "Memorize The Bible — read a verse, then say it back as the words disappear "
        + "one by one. The whole Bible, entirely offline, with no account."

    // MARK: - About (§8.4, §13)

    private var aboutSection: some View {
        Section("About") {
            NavigationLink("About this app") { AboutView() }
        }
    }

    // MARK: - Reset (§8.4: destructive, two-step)

    private var resetSection: some View {
        Section {
            Button("Reset all progress", role: .destructive) { isConfirmingReset = true }
        }
    }

    private var resetWarning: String {
        let warning = "This erases every verse you've memorized. It cannot be undone."
        guard state.isCloudSyncEnabled else { return warning }
        return warning
            + " The copy in iCloud goes too, though another device that still has your progress "
            + "will put its own copy back."
    }
}

extension ReminderTime {
    init(from date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 7, minute: components.minute ?? 0)
    }
}

/// §8.4 About: translation, attribution, licenses, version, privacy.
struct AboutView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List {
            Section("Translation") {
                Text(state.content.translationName)
                    .font(Typography.scripture(.body))
                Text("\(state.content.bookCount) books · \(state.content.manifest.chapterCount.formatted()) chapters · \(state.content.verseCount.formatted()) verses, all on device")
                    .font(Typography.chrome(.footnote))
                    .foregroundStyle(Palette.dimmedText)
                Text(state.content.attributionNotice)
                    .font(Typography.chrome(.footnote))
                    .foregroundStyle(Palette.dimmedText)
            }

            Section("Privacy") {
                // §13: a genuine differentiator in this category, and one that
                // survives iCloud sync — the copy goes to the user's own
                // account, not to anybody running this app.
                Text("This app collects no data and has no server of its own.")
                Text("Your progress is stored on this device and included in your device backups. With iCloud sync on — it is on unless you turn it off in Settings — a copy is also kept in your own iCloud account, which is what carries your work to a new device; it goes there and nowhere else. Scripture is read from the app itself, never fetched. There are no accounts to make, no analytics, no advertising identifiers, and no in-app purchases.")
                    .font(Typography.chrome(.footnote))
                    .foregroundStyle(Palette.dimmedText)
            }

            Section("Licenses") {
                Text("Berean Standard Bible — public domain.")
                    .font(Typography.chrome(.footnote))
                Text(fontLicenseText)
                    .font(Typography.chrome(.footnote))
                    .foregroundStyle(Palette.dimmedText)
            }

            Section("Version") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// §9: ship the OFL text in the bundle and reference it here.
    private var fontLicenseText: String {
        let preamble =
            "Scripture is set in Literata, used under the SIL Open Font License 1.1. "
            + "Interface type is SF Pro, supplied by the system. No third-party code is used.\n\n"
        guard
            let url = Bundle.main.url(forResource: "Literata-OFL", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return preamble }
        return preamble + text
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// The confirmation for erasing everything, given the whole screen.
struct ResetProgressView: View {
    let warning: String
    /// Reported back so the sheet can open to exactly this much.
    @Binding var contentHeight: CGFloat
    let onErase: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            Text("Erase everything?")
                .font(Typography.chrome(.largeTitle).weight(.bold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(warning)
                .font(Typography.scripture(.body))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                Button("Erase everything", action: onErase)
                    .buttonStyle(DestructiveButtonStyle())
                // Cancel is the quiet one and the easy one to hit by accident,
                // so it is the plain text rather than the filled button.
                Button("Cancel", action: onCancel)
                    .font(Typography.chrome(.subheadline))
                    .foregroundStyle(Palette.dimmedText)
            }
        }
            .padding(Metrics.gutter * 1.5)
            // No maxHeight: the sheet opens to whatever this measures, so it
            // has to be its own size rather than filling what it is handed.
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.height, initial: true) { _, height in
                            contentHeight = height
                        }
                }
            }
        }
        // Scrolls only when it has to, which is at the accessibility text
        // sizes, where four lines of warning become a screenful and the sheet
        // can no longer open tall enough to hold it.
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background)
    }
}
