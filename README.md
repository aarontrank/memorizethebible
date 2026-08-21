# Memorize The Bible

A single-purpose, fully offline iOS app for memorizing scripture. Grown from
[`psalms-app-design-doc.md`](psalms-app-design-doc.md), which covered Psalms
alone; every section reference in the code (§7.2, §8.1, …) points back to it.

No account, no network, no analytics, no in-app purchases. The whole Bible —
66 books, 1,189 chapters, 31,086 verses — ships in the app bundle; all progress
stays in the app container.

## Divergences from the design doc

The design doc is the spec, and the code cites it throughout. Two decisions have
since been overturned in use, and the doc has **not** been rewritten — read it
with these on top:

**1. Delayed mastery is gone (supersedes §7.1 phase 3/3b, §7.4, §15 decision 6).**
There is no `provisional` state and no next-day confirming pass. A clean level-4
pass masters the verse there and then. The rule was meant to distinguish
short-term recall from memorization; in practice it read as confusing and
patronising, and it made the app's idea of "memorized" disagree with the user's.
Saved progress from before the change migrates automatically (schema 1 → 2):
provisional verses come back as mastered, since they had already passed level 4
cleanly.

**2. Review is now whole-block and gated (supersedes §8.3).** Review covers a
whole psalm at once — one stanza at a time for stanza-scoped psalms — and masks
words across the entire block rather than a verse at a time. It is offered only
for psalms already fully memorized, and it still writes no progress, so
re-testing a psalm can never endanger its completed status.

Re-testing what you have learned is Review's job now, rather than something the
session imposes the next day.

**3. The app covers the whole Bible, not only Psalms (supersedes §3's non-goal
and §6's data model).** Progress is keyed by verse reference rather than psalm
number, so a chapter is just an ordered set of verses.

**4. Memory plans.** A plan is a curated, ordered set of verses — the Roman
Road, the Sermon on the Mount, or one the user builds. Plans own no progress:
mastery belongs to the verse, so a verse learned in a plan is already learned in
its chapter, and a verse in two plans is learned once. Six plans ship built in;
built-ins can be hidden but not edited.

Because a chapter and a plan both reduce to "an ordered list of verses plus the
blocks they are recited in" (`MemoryTarget`), the session engine drives both and
cannot tell them apart.

**5. Mastery belongs to the verse; *coverage* belongs to the context.** Knowing
Romans 3:23 from the Roman Road does not mean you have worked it inside Romans 3
— reciting a verse among its neighbours is a different act from reciting it in a
plan. So each target records which of its units it has covered:

- A plan touching a verse never puts that verse's chapter in the dashboard's
  in-progress list. Chapters appear there once worked *as chapters*.
- The chapter still counts the verse it knows: "1 of 31 verses · memorized
  elsewhere".
- When a session reaches a verse you already know, it stops and offers both
  **"I still know it"** (accept it here) and **"Memorize it again"** (full read →
  ladder). Verses before and after are worked as normal, and the verse is marked
  in the text so the difference is visible.
- Re-memorizing never gives up the mastery already earned, so stopping halfway
  costs nothing.
- The rule runs both ways: a plan asks the same question about a verse you
  learned in its chapter.

## Layout

```
Tools/ContentPipeline/     build-time: BSB sources → bundled JSON (M1)
Tools/AppIcon/             build-time: the app icon
Packages/BibleCore/        all the rules: content, masking, session, plans, storage
App/MemorizeBible/        SwiftUI app
App/MemorizeBible.xcodeproj
```

**The bundle ships text and structure, not tokens.** Splitting verses into
maskable words happens at runtime (`Tokenizer.swift`), seeded deterministically
by book, chapter, and verse. Pre-tokenising 31,086 verses came to roughly 45 MB
of JSON; text plus structure is 5 MB. `CorpusTests` asserts the runtime
reproduces every verse exactly, so the move is checked rather than hoped for.

**`BibleCore` is now a misnomer** — it holds the whole Bible. Renaming the
module is mechanical but touches the Xcode package reference, so it is left for
a moment when the project is not mid-change. The same goes for the app's own
name, which is yours to decide.

The split matters: `BibleCore` is pure Foundation with no UI and no `Date()`,
so the memorization rules are testable in about two seconds, with no simulator
and no waiting on the calendar.

## Build and test

```sh
# Logic (100 tests, no simulator needed)
cd Packages/BibleCore && swift test

# Content pipeline (29 tests, validates all 31,086 verses)
cd Tools/ContentPipeline && python3 -m unittest test_content

# App
cd App && xcodebuild -project MemorizeBible.xcodeproj -scheme MemorizeBible \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

The scheme is shared (checked in), so the project opens in Xcode ready to build.
The built product is `Memorize Bible.app` — note the space, since `PRODUCT_NAME`
carries the real app name.

## Running on a device

The project is unsigned: `CODE_SIGN_STYLE` is `Automatic` with no
`DEVELOPMENT_TEAM`, so it builds for the simulator as-is. To run on hardware,
open `App/MemorizeBible.xcodeproj`, select the **MemorizeBible** target →
**Signing & Capabilities**, and choose your team. Xcode writes `DEVELOPMENT_TEAM`
into the project; nothing else needs to change.

The bundle identifier is `memorizethebible.aarontrank.com`. Change it in **Signing
& Capabilities** if that identifier is not available under your team.

### Naming

| Key | Value |
|---|---|
| `CFBundleDisplayName` | Memorize The Bible — the user-visible name |
| `CFBundleName` | Memorize Bible — the short name, kept to Apple's 15-character guidance |
| `CFBundleIdentifier` | memorizethebible.aarontrank.com |

`CFBundleName` comes from `PRODUCT_NAME`; the Info.plist generator ignores
`INFOPLIST_KEY_CFBundleName`. The two names differ on purpose: "Memorize The
Bible" is 18 characters, and Apple asks for 15 or fewer in `CFBundleName`, so
the full name lives in `CFBundleDisplayName` and the product keeps the shorter
one.

## Regenerating content

```sh
cd Tools/ContentPipeline && python3 build_content.py
```

Writes `App/MemorizeBible/Resources/Content/` (a manifest plus one file per
psalm, loaded lazily). Sources and the reasoning behind using two of them are
in [`Tools/ContentPipeline/README.md`](Tools/ContentPipeline/README.md).

## App icon and launch screen

Both come from one piece of supplied artwork, kept at
`Tools/AppIcon/source/memorizethebible.png`:

```sh
swift Tools/AppIcon/prepare_assets.swift        # resizes it into the asset catalog
```

- **Icon** — 1024×1024, written **without an alpha channel**. An RGBA app icon is
  rejected at submission and renders badly on the home screen. The artwork
  carries its own dark ground, so it ships as a single opaque icon rather than
  with dark and tinted variants, which would need transparent versions.
- **Launch screen** — `LaunchScreen.storyboard`, referenced by
  `INFOPLIST_KEY_UILaunchStoryboardName`. The image is pinned to both edges and
  centred vertically, so it is full width and aspect-fit whatever the device.
  The background is `#060706`, which is exactly the artwork's own ground colour,
  so there is no seam where one ends and the other begins.

## Driving the UI without tapping (debug builds)

Any screen or session step can be reached from the command line. These flags are
compiled out of Release, and they write to a throwaway progress file, never the
real one.

```sh
xcrun simctl launch <sim> memorizethebible.aarontrank.com \
    -uiDebug -debugBook PSA -debugChapter 23 -debugSeed ladder4
```

| Flag | Values |
|---|---|
| `-debugBook` | book code, e.g. `PSA`, `ROM`, `MAT` |
| `-debugChapter` | chapter number within that book |
| `-debugPlan` | plan id, e.g. `builtin.roman-road` |
| `-debugCompletePlan` | additionally marks a plan complete, to see both plan sections |
| `-debugWorkedThrough` | marks the target's first N units as already worked here |
| `-debugSeed` | `read`, `ladder1`…`ladder4`, `cumulative`, `partial`, `recitation`, `memorized` |
| `-debugScreen` | `session` (default), `review`, `books`, `chapters`, `plans`, `plan`, `newPlan`, `settings`, `dashboard` |
| `-debugLevel` | initial mask level for Review, `0`–`4` |
| `-debugHeadings` | include psalm headings as memorizable units |
| `-debugDayOffset` | date the seeded work N days in the past |

## Milestones

| # | Milestone | State |
|---|---|---|
| M1 | Content pipeline | done — 66 books, 1,189 chapters, 31,086 verses, all validated |
| M2 | Data + persistence | done — atomic snapshot, schema 1→2→3→4 migrations, corrupt-file recovery |
| M3 | Masking renderer | done — zero reflow at every level and every Dynamic Type size |
| M4 | Session engine | done — read → ladder → mastered → cumulative |
| M5 | Confirmation pass | **removed** — see divergences above |
| M6 | Dashboard + Review | done — Review reworked to whole-chapter recall |
| M7 | Psalm 119 | done — 22 acrostic stanzas; every long chapter is stanza-scoped |
| M8 | Notifications + Settings | done — 24h rule unit tested; heading toggle non-destructive both ways |
| M9 | Accessibility + polish | done — VoiceOver, Dynamic Type, dark mode, Reduce Motion, Literata |
| M10 | TestFlight | not started — needs a signing team |

## Content figures

| | |
|---|---|
| Books | 66 |
| Chapters | 1,189 |
| Verses | 31,086 |
| Superscriptions | 116, all in Psalms |
| Bundle | 5 MB of content; 12 MB app |

The BSB numbers 31,102 verses, but prints sixteen of them empty — the omitted
verses of the critical text (Matthew 17:21, Mark 9:44, John 5:4 and the rest).
Those are not shipped, so a few New Testament chapters have deliberate gaps in
their verse numbering, and nothing in the app assumes verses run 1…n.

## Known gaps before shipping

- **Signing.** `DEVELOPMENT_TEAM` is unset; the project builds and runs in the
  simulator but needs a team to install on a device or reach TestFlight.
- **The app is called "Memorize The Bible".**
  The name is yours to decide; changing it means `PRODUCT_NAME` and
  `INFOPLIST_KEY_CFBundleDisplayName` in the target settings, and the name still
  wants checking for collisions in App Store Connect before you commit to it.
- **`BibleCore` should be renamed** for the same reason. Mechanical, but it
  touches the Xcode package reference, so it is worth doing on a quiet diff.
- **Reminder copy.** Now reads "Romans 8 is waiting — 3 of 39 verses." for a
  chapter and "The Roman Road — 2 of 6 verses." for a plan; still a tone call.
- **Custom plans are not shareable or exportable.** They live only in the
  progress file, which rides along in device backups.
