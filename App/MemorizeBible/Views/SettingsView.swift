import BibleCore
import SwiftUI

/// Settings (§8.4).
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var showHeadingsConfirmation = false
    @State private var reopenedChapters: [ChapterRef] = []
    @State private var resetStage = 0

    var body: some View {
        @Bindable var state = state
        List {
            remindersSection
            walkthroughSection
            headingsSection
            aboutSection
            resetSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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
                    state.endWalkthrough()
                }
            }
        } header: {
            Text("Walkthrough")
        } footer: {
            Text("A guided tour of a plan, using a demo of two very short verses. The demo appears only while the walkthrough is running.")
        }
    }

    // MARK: - About (§8.4, §13)

    private var aboutSection: some View {
        Section("About") {
            NavigationLink("About this app") { AboutView() }
        }
    }

    // MARK: - Reset (§8.4: destructive, two-step)

    private var resetSection: some View {
        Section {
            if resetStage == 0 {
                Button("Reset all progress", role: .destructive) { resetStage = 1 }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This erases every verse you've memorized. It cannot be undone.")
                        .font(Typography.chrome(.footnote))
                        .foregroundStyle(Palette.dimmedText)
                    HStack {
                        Button("Cancel") { resetStage = 0 }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("Erase everything", role: .destructive) {
                            state.resetProgress()
                            resetStage = 0
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 4)
            }
        }
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
                // §13: a genuine differentiator in this category.
                Text("This app collects no data and makes no network connections.")
                Text("Your progress is stored only on this device. It is included in your device backups and is never synced or sent anywhere. There are no accounts, no analytics, no advertising identifiers, and no in-app purchases.")
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
