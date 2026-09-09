# App Store Connect listing

App Store id **6803717306** — `https://apps.apple.com/app/id6803717306`, the
locale-agnostic form, which redirects to the opener's own storefront. It is set
in `App/MemorizeBible/AppLinks.swift`, on the project page and on the shared-plan
landing page.

Everything the submission form asks for. Character counts are against Apple's
hard caps, checked, not estimated.

---

## The three fields that are searched

Name, subtitle and keywords are indexed as **one pool**, and Apple builds
multi-word matches across the three. So a word placed in two of them is bought
twice and delivered once. Title carries the most weight; subtitle and keywords
are near enough equal.

The description is **not** indexed by App Store search. It is a conversion
field, and the only reason to touch it is to make someone tap Get. (Google does
index the App Store page, so it earns a little web traffic — not enough to write
for.)

One lever that is easy to forget: the **developer name is indexed too**. If it is
set to a personal name in App Store Connect, that is free keyword space going
unused.

## Name — 26 / 30

```
Memorize The Bible: Verses
```

The previous name was `Memorize The Bible`, 18 / 30 — twelve unused characters
in the highest-weighted field there is. The clause spends them on `verses` and
frees the subtitle to carry different words entirely.

The alternative, if the name is ever treated as disposable:
`Bible Memory: Memorize Verses` (29), which leads with the category term at top
weight. Better ASO, worse branding, and it changes the icon label, the landing
page and every screenshot.

## Subtitle — 30 / 30

```
Scripture memory, daily recall
```

The previous subtitle was `Verses by heart, offline`, which spent 24 characters
on `by`, `heart` and `offline` — all at or near the floor of the popularity
scale. This one buys `scripture`, `memory`, `daily` and `recall`, and puts
`memory` in the pool alongside `bible` so the phrase **"bible memory"** — the
term this category is actually searched by — matches.

It reads a shade more like a feature list than the old one did. That is the
price of the density; earlier drafts kept for the record:

| Subtitle | Len |
|---|---|
| Learn verses by heart, offline | 30 |
| The words disappear as you go | 29 |
| Scripture memory, offline | 25 |
| Whole Bible. No account. | 24 |

## Keywords — 95 / 100

```
psalms,christian,study,devotional,learn,memorization,recite,flashcards,testament,teach,remember
```

No spaces after commas — they count against the 100. Nothing here repeats a word
from the name or subtitle, which is where the room came from: `scripture`,
`memory` and `recall` moved up into the subtitle, and `verse`, `offline`, `heart`
and `quiet time` were dropped for having no volume.

`memorization` earns its 12 characters. It is a different lemma from `memorize`
and Apple will not bridge the two, and "bible memorization" is genuinely
searched.

The marginal entries, to swap first when testing alternatives: `flashcards` (the
app is deliberately not flashcards, but the search intent matches) and `teach`.

Still excluded on purpose: no competitor app names, which Apple rejects, and no
translation names the app does not ship. `kjv`, `niv` and `esv` are all high
volume and all off the table — the app ships the BSB, and claiming otherwise is
both a rejection risk and a one-star review waiting to happen.

## What none of the above will fix

Ranking is driven mostly by download velocity, retention and rating count. The
three fields decide what the app is *eligible* to rank for; they do not decide
where it lands. The app already had `bible` in its title and ranked nowhere for
it — `bible` scores 75 for popularity against 88 for competitiveness, and that
is not a text problem.

So the in-app rating prompt and the certificate sharing from 1.3 are doing more
for search rank than the keyword field is.

Prompted by an ASO Scout report, 8 September 2026, which is worth reading with
its sales framing subtracted: it opens on `memorize` ranking outside the top 200,
and its own table scores that keyword 6 for popularity — the floor of a 5–100
scale, meaning essentially nobody searches it. The one useful row was `verses`,
at 26 popularity against 44 competitiveness, with the real category listed beside
it: Verses – Bible Memory, The Bible Memory App, Memorize By Heart.

## Promotional text — 167 / 170

Editable without shipping a build, so it is the place for anything seasonal —
and the one field worth pointing at whatever shipped most recently. It sits
directly above the description, so it should never repeat the description's
opening lines.

```
New in 1.4: your progress follows you. A new iPhone or iPad picks up exactly where the old one left off, and work done on two devices is combined rather than replaced.
```

Being version-specific, this one needs retiring when 1.4 stops being news. The
evergreen line it replaced, to go back to:

```
Read a verse, then say it back as the words disappear one by one. The whole Bible, offline — no account, no ads, and your progress follows you to a new device.
```

## Description — 3,255 / 4,000

```
Memorize The Bible teaches a verse the way people actually learn one.

Read it aloud a few times. Then say it back as the words disappear — a quarter at a time, then half, then three quarters, until you are reciting it with nothing on the screen. Tap any blank for the first letter of the word underneath, and again for the whole of it. Peeking is free right up to the last pass, where the whole point is to have it.

After each verse you recite everything up to that point together, so a chapter becomes a passage rather than a pile of verses.

THE WHOLE BIBLE
All 66 books, 1,189 chapters and 31,086 verses of the Berean Standard Bible, on your device. Start anywhere.

MEMORY PLANS
Learn a set of verses together: the Roman Road, the Sermon on the Mount, the Lord's Prayer, the Fruit of the Spirit, or any plan you assemble yourself. A verse learned in a plan is already learned in its chapter — mastery belongs to the verse, so nothing is ever counted twice or learned twice over.

Custom plans can be shared with a link. The plan travels inside the link itself, so there is no server involved and nothing to sign up for. Whoever you send it to sees exactly what it holds before deciding to keep it.

LOOK BEFORE YOU COMMIT
Read any book, chapter or plan straight through before deciding anything. Nothing reaches your home screen until you tap Start memorizing, so what waits for you there is only ever the work you actually chose — and you can put a plan back down again without losing a verse of it.

WORDS THAT STAY PUT
A blank is the same word drawn invisibly, so a line breaks in exactly the same place at every level and at every text size. Nothing reflows as you go, and the shape of the verse on the page becomes part of how you remember it.

REVIEW WHAT YOU KNOW
A memorized chapter can be reviewed whole, at whatever level of masking you choose. Reviewing can never undo the progress you have made.

MILESTONES WORTH KEEPING
Your first verse. Ten of them. A whole chapter, a whole book, a whole plan. A hundred verses. Each one is a certificate you can look back at in the order you earned them, and send to whoever would want to know.

WORKS OFFLINE, MOVES WITH YOU
No account. No sign-in. No analytics, no tracking, no advertising, no subscription, no in-app purchases. Every screen works in airplane mode, because the whole Bible is already on your device.

Your progress is kept on the device and, unless you turn it off in Settings, copied to your own iCloud account — so a new iPhone or iPad picks up exactly where the old one left off. Work done on two devices is combined rather than replaced. That copy goes to your iCloud and nowhere else; there is no server on our side and nothing about you to collect.

BUILT TO BE READ
A serif face set with generous leading, a measure capped for comfortable reading, and a palette of six colours. Full Dynamic Type support through the accessibility sizes, VoiceOver labels throughout, and Reduce Motion respected. Portrait and landscape.

A gentle daily reminder is available, scheduled on your device, and off until you ask for it.

Scripture quotations are from the Berean Standard Bible (BSB), which has been dedicated to the public domain. Free resources are available at BereanBible.com.
```

## What's New — 497

For 1.4, which is the iCloud release. Milestones and the rest shipped in 1.3,
so re-announcing them here would spend the field telling people about something
they already have.

```
Your progress now follows you.

Everything you have memorized is kept in your own iCloud account, so a new iPhone or iPad picks up exactly where the old one left off. Work done on two devices is combined rather than replaced — nothing you have learned is ever dropped for being the older copy.

It goes to your iCloud and nowhere else: there is still no account to make and no server on our side. Settings > iCloud turns it off in one tap, and with it off your progress stays on this device alone.
```

Earlier releases, for the record. The 1.3 text was written straight into App
Store Connect and never copied back here.

1.1:

```
Browse before you commit.

Open any book, chapter or plan and read it in full. Nothing reaches your home screen until you tap Start memorizing, so you can look around without cluttering up what you are actually working on — and take a plan back off again whenever you like, without losing a verse of it.

Peeking is gentler. Tap a blank once for its first letter, again for the whole word. Either way it closes on its own.

Finishing something is celebrated properly now, wherever you finish it.
```

1.0:

```
The first release.

The whole Berean Standard Bible, memory plans you can build and share, review for anything you have finished, and progress cards worth sending to someone. Entirely offline, with no account and nothing collected.
```

---

## URLs

| Field | Value |
|---|---|
| Privacy Policy URL (**required**) | `https://aarontrank.com/projects/memorize-the-bible/privacy/` |
| Support URL (**required**) | `https://aarontrank.com/projects/memorize-the-bible/` |
| Marketing URL (optional) | `https://aarontrank.com/projects/memorize-the-bible/` |
| Custom EULA (optional) | paste `https://aarontrank.com/projects/memorize-the-bible/terms/` |

Apple expects the Support URL to offer a way to get help. The project page links
to the privacy and terms pages, which carry the contact address — adequate, but a
dedicated support page with the address on it is the safer answer.

Leaving the EULA blank means Apple's standard licence applies, which is fine. The
terms page exists either way and is linked from the project page.

## Categories

- **Primary: Education** — it is a learning tool, and the category is less
  crowded than Reference.
- **Secondary: Reference** — where people browse for Bible apps.

Swapping them is defensible; primary drives more of the ranking, so pick the one
whose charts you would rather appear in.

## Age rating

Bible apps are generally rated 4+. Answer the questionnaire honestly about the
app's own features — there is no user-generated content, no web access, no
gambling, no contests. The only judgement call is whether unabridged scripture
counts as depicting violence, and the settled convention in this category is that
it does not.

## App Privacy — "Data Not Collected"

Still the easiest section in the form, and still a genuine selling point.
Declare **no data collected at all**: every category answered No, with no linked
or tracking data.

iCloud sync does not change the answer. Apple's definition of collection is data
transmitted off the device *and accessible to the developer or a third party*;
the progress record goes into the user's own iCloud account, which nobody on
this side can read. There is no server here to receive anything. The app itself
contains no networking code — iOS moves the value.

Do not let the daily reminder confuse the answer either: local notifications are
scheduled on-device by iOS and involve no push server, so nothing is collected.

## Copyright

```
2026 Aaron Trank
```

## App Review notes

The full text lives in `AppReviewNotes.md` — it answers the seven questions
Apple's Guideline 2.1 template asks, and belongs in the **App Review Information
→ Notes** field permanently, not just in a reply. A thin Notes field is what
triggers that rejection in the first place.

---

## Screenshots

Three sets under `AppStore/screenshots/`. Same seven shots each; upload in this
order, since the first two are what most people ever see.

| # | File | Shows |
|---|---|---|
| 1 | `1-ladder.png` | Psalm 23 mid-ladder, blanks in the active verse — the mechanic, first |
| 2 | `2-full-mask.png` | The same verse fully hidden, "I know it" |
| 3 | `3-home.png` | Continue, what is in progress, a completed plan, milestones, 9 of 31,086 |
| 4 | `4-plans.png` | Built-in plans and one of your own |
| 5 | `5-plan-detail.png` | The Roman Road, 3 of 6, verse by verse |
| 6 | `6-review.png` | A memorized psalm reviewed whole at 50% hidden |
| 7 | `7-milestone.png` | The first-verse certificate, carrying the verse it was earned on |

| Folder | Size | Slot |
|---|---|---|
| `iphone-6.5/` | 1284 × 2778 | iPhone 6.5" — what App Store Connect asked for |
| `iphone-6.9/` | 1320 × 2868 | iPhone 6.9" — the newer slot, if the record offers it |
| `ipad-13/` | 2064 × 2752 | iPad 12.9"/13" |

The iPad set is shot on iPadOS 17.5 rather than 26.x on purpose: iPadOS 26 draws
a window-resize grabber in the bottom-right corner, which is system chrome but
reads as a rendering defect in a store screenshot. Screenshots carry no
latest-OS requirement — only Apple's review recording does.

Regenerate with `scripts/shoot.sh <sim-udid> <outdir>` after pinning the status
bar to Apple's convention:

```sh
xcrun simctl status_bar $SIM override --time "9:41" \
    --batteryState discharging --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3
```

`-debugOnboarded` is the flag that matters: it puts onboarding in its finished
state, so no welcome sheet, no tips, and no demo plan in the list — what the app
looks like once someone is actually using it. Shooting without it puts the
walkthrough's tip bubble and demo plan into the marketing shots.

Apple's rating prompt is suppressed under `-uiDebug` for the same reason: two of
these seeds — a completed plan for shot 3, a plan of your own for shot 4 — now
earn it, and it would land on top of the screenshot. `-debugReviewPrompt` turns
it back on for testing it.

### iPad support is new, and adapted rather than designed

`TARGETED_DEVICE_FAMILY` was `1` (iPhone only) until these screenshots were
needed; it is now `"1,2"`, and iPad gets all four orientations while iPhone still
skips upside-down.

The app runs correctly on iPad — the reading column stays at its readable measure
and centres, the controls sit under it, nothing is clipped or broken. But it is
an iPhone layout on a larger canvas: on a 13" iPad the home screen fills about a
third of the height and leaves the rest empty. Acceptable, not impressive.

**This may not be needed at all.** App Store Connect shows screenshot slots for
device families the app record has not ruled out yet; attaching an iPhone-only
build normally makes the iPad section go away. If the intent is to stay
iPhone-only, revert `TARGETED_DEVICE_FAMILY` to `1` and drop `ipad-13/`.

Doing iPad properly — a layout that earns the space rather than floating in it —
is its own piece of work, and shipping iPad support means Apple reviews that
experience too.

## Universal links — done

**Associated Domains is already enabled on the App ID** — Xcode's automatic
signing added it when it first provisioned after the entitlement appeared. A
device build signs with `com.apple.developer.associated-domains:
["applinks:aarontrank.com"]`, and the profile it pulls down
(`iOS Team Provisioning Profile: memorizethebible.aarontrank.com`) grants that
entitlement, which a profile only does when the App ID allows it. Verified with:

```sh
xcodebuild -project App/MemorizeBible.xcodeproj -scheme MemorizeBible \
    -destination 'generic/platform=iOS' build
codesign -d --entitlements - --xml "<built>.app" | plutil -p -
```

If a universal link ever fails on device: the device caches the association file
from Apple's CDN and only refreshes on install or first launch. Appending
`?mode=developer` to the entitlement (`applinks:aarontrank.com?mode=developer`)
makes the device fetch it straight from the domain instead, which is the way to
test a change without waiting on the cache. Take it back out before shipping.
