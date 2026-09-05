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

**Punctuation never starts a line.** Words are placed one at a time so a blank
can be the same word drawn invisibly, which means a line could otherwise break
anywhere — leaving a lone `,` or `.` stranded at the left margin.
`LineWrapping.groupIndices` ties each mark to the word it belongs to, and
`FlowLayout` may only break between those groups. A corpus test walks all 31,086
verses and asserts no group is punctuation alone.

**A shared plan travels inside its own link.** A plan is only an ordering over
references, so the whole plan — title, sections, passages — is JSON, base64url,
and a query parameter. There is no server to publish to, no account to look it
up under, and nothing that can go stale or be taken down; the recipient's app
reads the link and asks whether to save it. Ordinary plans come to a few hundred
characters (`PlanSharingTests` holds the largest built-in under 900). Receiving
the same plan twice updates the copy you have rather than leaving you with two,
because the link carries the sender's plan id.

`PlanSharing.decode` treats every link as hostile: unreadable passages are
dropped, a section left with none goes, titles are clamped, absurd counts are
capped, and a payload from a newer format is refused rather than guessed at.

**Progress cards are drawn, not screenshotted.** `ProgressCardView` is a SwiftUI
view run through `ImageRenderer` at 1080×1080, offered from the share sheet on a
plan, a book, or a chapter. A finished one leads with a gold seal — the same
gold a filled blank has been all along — and carries the date; an unfinished one
carries the bar and the count. It is the one thing in the app not bound by §9's
"no decorative imagery", because it leaves the app and has to stand on its own
in a feed, so it carries the mark and the name.

Two things the card does deliberately: it pins `colorScheme` to light, so an
exported image does not depend on what the device was set to when it was made,
and it draws its own border, so a white card does not dissolve into a white
feed. It is square because it holds four short lines — a taller frame only added
emptiness, and a square survives every place these get posted uncropped.

**Plan links are universal links.** `PlanSharing.link` writes
`https://aarontrank.com/projects/memorize-the-bible/plan?d=…`, claimed by the
Associated Domains entitlement in `App/MemorizeBible.entitlements`. Tapping one
opens the app directly, with none of the "Open in…" confirmation a custom scheme
draws; anyone without the app lands on a page that explains what the link is.

The reader still accepts the original `memorizethebible://plan` scheme, which
stays registered in `Info.plist`. Links written before the move are already out
in people's messages, and there is no way to reach back and fix them.

The matching half is served from the `aarontrank.com` site repo, as a static
asset at `public/.well-known/apple-app-site-association` with
`Content-Type: application/json` forced by `public/_headers`. A static asset
rather than a route because that site sets `trailingSlash: true`, which would
308 a route, and Apple's fetcher does not follow redirects. **Changing the path
in one place without the other silently stops links opening the app**, so
`PlanSharing.webHost` and `webPath` say so.

**Landscape moves the session controls, it does not just permit rotation.**
Height is what landscape is short of, and a control bar across the foot spends
two fifths of it — about three lines of scripture. In compact height the same
prompt, level controls and buttons become a column beside the text, which costs
width that landscape has to spare, and the reading area roughly triples. The bar
and the rail are two arrangements of one set of views (`AnyLayout`), so rotating
mid-session keeps your place in the chapter. At accessibility text sizes a
column that narrow would be worse than the squeeze, so the bar stays.

**`BibleCore` is now a misnomer** — it holds the whole Bible. Renaming the
module is mechanical but touches the Xcode package reference, so it is left for
a moment when the project is not mid-change. The same goes for the app's own
name, which is yours to decide.

The split matters: `BibleCore` is pure Foundation with no UI and no `Date()`,
so the memorization rules are testable in about two seconds, with no simulator
and no waiting on the calendar.

## Build and test

```sh
# Logic (155 tests, no simulator needed)
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
| `-debugWalkthrough` | puts the walkthrough into its running state, skipping the welcome sheet |
| `-debugCelebrate` | sets the fireworks off on launch |
| `-debugLandscape` | rotates the scene to landscape on launch (Simulator ignores keystroke rotation from a script) |
| `-debugSeed` | `read`, `ladder1`…`ladder4`, `cumulative`, `partial`, `recitation`, `memorized` |
| `-debugScreen` | `session` (default), `review`, `books`, `chapters`, `chapter`, `plans`, `plan`, `newPlan`, `settings`, `dashboard` |
| `-debugLevel` | initial mask level for Review, `0`–`4` |
| `-debugHeadings` | include psalm headings as memorizable units |
| `-debugDayOffset` | date the seeded work N days in the past |
| `-debugSeedPlans` | adds one plan of your own and one received as shared |
| `-debugHideBuiltInPlans` | hides the built-ins, so the sections under them fit on screen |
| `-debugOpenURL` | hands a plan link to the URL handler. Only needed for the legacy `memorizethebible://` scheme, whose "Open in…" prompt no script can tap — a universal link can just be passed to `simctl openurl` |
| `-debugAcceptShare` | with `-debugOpenURL`, saves the arriving plan without a tap |
| `-debugOnboarded` | finished onboarding: no welcome sheet, no tips, no demo plan — the state to take screenshots in |

## Milestones

| # | Milestone | State |
|---|---|---|
| M1 | Content pipeline | done — 66 books, 1,189 chapters, 31,086 verses, all validated |
| M2 | Data + persistence | done — atomic snapshot, schema 1→2→3→4→5 migrations, corrupt-file recovery |
| M3 | Masking renderer | done — zero reflow at every level and every Dynamic Type size |
| M4 | Session engine | done — read → ladder → mastered → cumulative |
| M5 | Confirmation pass | **removed** — see divergences above |
| M6 | Dashboard + Review | done — Review reworked to whole-chapter recall |
| M7 | Psalm 119 | done — 22 acrostic stanzas; every long chapter is stanza-scoped |
| M8 | Notifications + Settings | done — 24h rule unit tested; heading toggle non-destructive both ways |
| M9 | Accessibility + polish | done — VoiceOver, Dynamic Type, dark mode, Reduce Motion, Literata |
| M10 | TestFlight | not started — needs a signing team |

## Walkthrough

A first-run tour, also reachable from **Settings → Walkthrough**. It is built
around a demo plan of 1 Thessalonians 5:16–17 — "Rejoice at all times." and
"Pray without ceasing.", seven words together — so the whole loop can be walked
in a minute.

The demo plan is listed **only while the walkthrough is running**, and goes when
it ends, whether finished or skipped. The two verses it taught stay memorized:
they are real verses and the user really learned them, and mastery belongs to
the verse rather than to the plan that introduced it. The completion sheet says
so, because a demo that quietly kept something would be a surprise and one that
quietly took something away would be worse.

**Skipping counts as finishing.** Leaving the tour part-way through is a
decision about whether it is useful, not a failure to complete it, so it is
recorded as done and never offered again unprompted — and wherever the skip
happened, a notice says it can be restarted from Settings. That notice is
attached above the navigation stack rather than to the dashboard, because the
tour can be abandoned from inside a session.

Tips are derived from context — which screen, and how far the demo plan has got
— rather than from a step counter. A counter falls out of step the moment the
user taps back or finishes a verse early, and then the tour is either stuck or
lying; asking "what is on screen" cannot get stuck.

## Finishing something

Completing a chapter or a plan takes you straight back to the home screen —
`Navigator` owns the navigation path so a session deep in the stack can send you
home rather than back through the screens you arrived by — and sets off a short
burst of fireworks.

`FireworksView` draws into a single `Canvas` rather than animating a few hundred
views, and stops itself after 2.6 seconds instead of idling on a timer. It is
three shades of the icon's gold, with no white or ink: one would vanish on the
light background and the other on the dark. Under Reduce Motion it draws one
still frame of the burst instead of animating (§12).

The celebration fires only when something is finished **in that session** —
`SessionEngine.justCompletedTarget` — so reopening a finished plan is quiet.

It is a token that gets **spent**, not a counter. `AppState.celebration` is
cleared by the burst itself once it has played, and the dashboard shows the
overlay only while it is set. A count only ever goes up, so a dashboard that
celebrates whenever the count is above zero celebrates again every single time
you come home — and under Reduce Motion, where the still frame never fades on
its own, it simply stayed there.

A finished target is also nothing to continue, so the Continue card stands down
rather than offering a dead end, and the home screen prompts you to pick a book
or a plan instead.

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

- **Signing.** `DEVELOPMENT_TEAM` is set to `74S95ZT622`, and Associated Domains
  is enabled on the App ID — a device build signs with the `applinks` entitlement
  and its provisioning profile grants it. Nothing outstanding.
- **The app is called "Memorize The Bible".**
  The name is yours to decide; changing it means `PRODUCT_NAME` and
  `INFOPLIST_KEY_CFBundleDisplayName` in the target settings, and the name still
  wants checking for collisions in App Store Connect before you commit to it.
- **`BibleCore` should be renamed** for the same reason. Mechanical, but it
  touches the Xcode package reference, so it is worth doing on a quiet diff.
- **Reminder copy.** Now reads "Romans 8 is waiting — 3 of 39 verses." for a
  chapter and "The Roman Road — 2 of 6 verses." for a plan; still a tone call.
