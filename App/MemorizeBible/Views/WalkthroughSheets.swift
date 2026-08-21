import BibleCore
import SwiftUI

/// The first thing a new user sees: an offer, not an obstacle.
struct WalkthroughWelcomeView: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)

            Text("Memorize The Bible")
                .font(Typography.chrome(.largeTitle).weight(.bold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("Read a verse a few times, then recall it as the words disappear one by one, until you can say it with nothing on the screen.")
                .font(Typography.scripture(.body))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("The walkthrough uses a demo plan of two very short verses — seven words in all — so you can see the whole loop in a minute. The demo disappears once you finish it.")
                .font(Typography.chrome(.subheadline))
                .foregroundStyle(Palette.dimmedText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button("Show me", action: onStart)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Skip for now", action: onSkip)
                    .font(Typography.chrome(.subheadline))
                    .foregroundStyle(Palette.dimmedText)
            }
        }
        .padding(Metrics.gutter * 1.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.background)
        .presentationDetents([.medium, .large])
    }
}

/// Shown the moment the demo plan is finished.
struct WalkthroughFinishedView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)

            Text("That's the whole loop")
                .font(Typography.chrome(.title).weight(.bold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("A finished plan moves to Completed, where you can review it without ever putting it at risk.")
                .font(Typography.chrome(.subheadline))
                .foregroundStyle(Palette.dimmedText)
                .fixedSize(horizontal: false, vertical: true)

            // Said plainly, because a demo that quietly kept something would be
            // a surprise, and one that quietly took something away would be worse.
            Text("The demo plan has gone, since it was only for showing you around. The two verses you learned stay memorized — they are real verses, and you really learned them.")
                .font(Typography.chrome(.subheadline))
                .foregroundStyle(Palette.dimmedText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Pick a book or a plan whenever you are ready. The walkthrough is in Settings if you want it again.")
                .font(Typography.chrome(.subheadline))
                .foregroundStyle(Palette.dimmedText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button("Done", action: onDismiss)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Metrics.gutter * 1.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.background)
        .presentationDetents([.medium, .large])
    }
}
