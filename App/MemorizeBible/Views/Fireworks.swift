import SwiftUI

/// A short burst of fireworks, shown when something is finished.
///
/// The one place the app is allowed to be loud. It draws into a single Canvas
/// rather than animating a pile of views, so a few hundred particles cost one
/// redraw a frame, and it stops itself after a couple of seconds rather than
/// idling on a timer for the rest of the session.
///
/// Under Reduce Motion nothing moves: the particles are drawn once, at rest, as
/// a still burst that fades (§12).
struct FireworksView: View {
    /// Restarting the display means handing this a new value.
    let trigger: String
    /// Called once the burst is spent, so the caller can take it off screen.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bursts: [Burst] = []
    @State private var startedAt = Date()

    private static let duration: TimeInterval = 2.6

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let elapsed = reduceMotion
                    ? 0.55  // a single frame from the middle of the burst
                    : timeline.date.timeIntervalSince(startedAt)
                guard elapsed < Self.duration else { return }
                for burst in bursts {
                    draw(burst, at: elapsed, in: &context, size: size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // One task drives both ends of the display: it starts the burst and,
        // when the burst is over, reports back. Under Reduce Motion the still
        // frame is on screen for the same time, so it leaves rather than
        // sitting there for the rest of the session.
        .task(id: trigger) {
            restart()
            try? await Task.sleep(for: .seconds(Self.duration))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    private func restart() {
        startedAt = Date()
        bursts = (0..<5).map { index in
            Burst(
                delay: Double(index) * 0.28,
                center: UnitPoint(
                    x: .random(in: 0.18...0.82),
                    y: .random(in: 0.18...0.55)
                ),
                color: Self.palette[index % Self.palette.count],
                particles: (0..<28).map { _ in
                    Particle(
                        angle: .random(in: 0..<(2 * .pi)),
                        speed: .random(in: 90...260),
                        size: .random(in: 2...4.5)
                    )
                }
            )
        }
    }

    /// Three shades of the icon's gold. Deliberately no white or ink: one
    /// would vanish on the light background and the other on the dark, and a
    /// firework that only half shows up is worse than one colour that always
    /// does.
    private static let palette: [Color] = [
        Color(red: 0.96, green: 0.68, blue: 0.02),
        Color(red: 1.0, green: 0.80, blue: 0.30),
        Color(red: 0.85, green: 0.52, blue: 0.02),
    ]

    private func draw(_ burst: Burst, at elapsed: TimeInterval, in context: inout GraphicsContext, size: CGSize) {
        let age = elapsed - burst.delay
        guard age > 0, age < Self.duration - burst.delay else { return }
        let fade = max(0, 1 - age / 1.5)
        guard fade > 0.01 else { return }

        let origin = CGPoint(x: burst.center.x * size.width, y: burst.center.y * size.height)
        for particle in burst.particles {
            // Outward, slowing, and pulled down: enough physics to read as a
            // firework without pretending to be one.
            let drift = particle.speed * age * (1 - age * 0.32)
            let point = CGPoint(
                x: origin.x + cos(particle.angle) * drift,
                y: origin.y + sin(particle.angle) * drift + 110 * age * age
            )
            let radius = particle.size * fade
            guard radius > 0.2 else { continue }
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - radius, y: point.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(burst.color.opacity(fade))
            )
        }
    }

    private struct Burst {
        let delay: TimeInterval
        let center: UnitPoint
        let color: Color
        let particles: [Particle]
    }

    private struct Particle {
        let angle: Double
        let speed: Double
        let size: Double
    }
}
