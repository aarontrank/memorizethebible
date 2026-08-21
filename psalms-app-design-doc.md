# Psalms — Design Document

**Author:** Aaron
**Date:** August 18, 2026
**Status:** Approved for implementation — all open questions resolved (see §15)
**Audience:** Execution agent / implementing engineer

---

## 1. Summary

Psalms is a single-purpose, fully offline iOS app for memorizing the book of Psalms. The user works through one psalm at a time. Each psalm is learned verse by verse using progressive word masking: read the verse in full, then re-recite it as words are progressively replaced by blanks, until the user can recite it with every word hidden. Mastered verses accumulate into a full-psalm recitation. A dashboard tracks progress across all 150 psalms.

No account. No network. No cloud sync. No analytics. All scripture text ships in the app bundle; all progress is stored locally on device.

---

## 2. Goals

- Help a motivated user memorize entire psalms, not isolated verses.
- Make the daily loop frictionless: open app → resume exactly where you left off.
- Show honest progress at two levels: overall (psalms complete) and per-psalm (verses mastered).
- Work perfectly with airplane mode on, forever, with no server dependency.
- Visual design that gets out of the way of the text.

## 3. Non-goals (v1)

- Speech recognition / automatic recitation grading. Mastery is self-attested.
- Multiple translations in one build. One translation per build.
- Books other than Psalms.
- iCloud sync, accounts, social features, leaderboards, streak gamification.
- Audio playback of scripture.
- iPad-optimized or watchOS layouts (must not crash on iPad; run as scaled iPhone app).
- Any server, backend, or third-party SDK of any kind.

---

## 4. Scripture text — RESOLVED: Berean Standard Bible (BSB)

**v1 ships the BSB.** It is free for any use including commercial and offline embedding, is modern readable English, and is explicitly developer-friendly with clean machine-readable editions available. No permission request, no licensing gate, no dependency on a third party's timeline. Include the BSB attribution on the About screen.

The content layer remains translation-agnostic (see §11) so another translation can be added later as a content pack without code changes.

### Why not the NIV or ESV (recorded for future reference)

**NIV.** This is not a fair-use gray area.

Biblica's standing general-use grant allows quoting the NIV <cite index="53-1">up to and inclusive of five hundred (500) verses without express written permission, provided the verses quoted do not amount to a complete book of the Bible nor account for twenty-five percent (25%) or more of the total text of the work in which they are quoted</cite>. Psalms is 2,461 verses, it *is* a complete book, and it would be ~100% of the app's text content. The proposed app fails all three conditions simultaneously.

Additionally, <cite index="52-1">Biblica does not permit uncontrolled downloads of their texts, and Bible text is generally licensed for online display rather than unrestricted download or redistribution</cite> — which is in direct tension with the "embedded in the app bundle, fully offline" architecture. A license may still be obtainable, but expect the offline-embedding question to be the crux of the negotiation.

**ESV.** A harder no than the NIV for this architecture. Crossway allows <cite index="9-1">up to 500 verses without a formal license, provided the quoted verses do not amount to more than one-half of any one book, nor account for 25% or more of the total text of the work</cite> — Psalms fails every clause. Decisively, their terms state <cite index="10-1">you may not locally store more than 500 verses or one-half of any book of the Bible, whichever is less</cite>, which is a direct prohibition on offline embedding rather than merely a silence.

**Other free options considered:** JPS 1917 (<cite index="16-1">public domain</cite>, but <cite index="17-1">archaic KJV-derived diction — "shalt," "thee," "thou"</cite>), WEB (public domain, modern), KJV and ASV (public domain, dated).

**The execution agent must not bundle NIV or ESV text under any circumstances.** If a licensed translation is added in future, it ships as an additional content pack, never as a replacement that strands existing user progress (progress is keyed to `translationId`).

---

## 5. Platform and stack

- **Platform:** iOS 17+, iPhone. SwiftUI.
- **Language:** Swift 5.9+.
- **Persistence:** Codable JSON snapshot written atomically to Application Support. Versioned schema (`schemaVersion` int). No Core Data, no SwiftData — the data volume is trivial and the migration surface should stay near zero.
- **Content:** Bundled JSON, loaded lazily per psalm.
- **Notifications:** `UNUserNotificationCenter`, local only.
- **Dependencies:** none. No SPM packages beyond Apple frameworks.
- **Entitlements:** none requiring network. App should function with no network entitlement at all. App Store privacy label: **Data Not Collected**.

---

## 6. Core concepts and data model

### Content (read-only, bundled)

```
Translation
  id: String              // "bsb"
  name: String            // "Berean Standard Bible"
  attributionNotice: String // rendered on About screen
  psalms: [Psalm]

Psalm
  number: Int             // 1...150
  superscription: Verse?  // modeled as a Verse with number = 0
  verses: [Verse]         // numbered 1...n
  stanzas: [Stanza]?      // present for psalms > 40 verses

Verse
  number: Int             // 0 == superscription
  text: String
  tokens: [Token]         // precomputed at build time

Token
  kind: .word | .punctuation | .selah
  text: String
  maskIndex: Int?         // deterministic mask ordering; nil for non-maskable
```

### Progress (read-write, local)

```
Progress
  schemaVersion: Int
  translationId: String
  currentPsalm: Int
  currentVerse: Int
  psalmStates: [Int: PsalmState]
  lastOpenedAt: Date
  notificationsEnabled: Bool
  includeSuperscriptions: Bool    // default false

PsalmState
  psalmNumber: Int
  verseStates: [Int: VerseState]  // key 0 == superscription
  fullRecitationConfirmed: Bool   // gates "memorized"
  completedAt: Date?

VerseState
  status: .untouched | .inProgress | .provisional | .mastered
  highestMaskLevelCleared: Int    // 0...4
  readCount: Int
  peekCount: Int
  provisionalAt: Date?            // when the first clean level-4 pass happened
  masteredAt: Date?               // when confirmed on a later day
```

### Reference figures for validation

- 150 psalms, **2,461 verses** total (KJV versification; verify against whichever translation ships — versification differs slightly between translations, and superscription handling differs significantly).
- Shortest: Psalm 117 (2 verses). Longest: Psalm 119 (176 verses).

---

## 7. The memorization loop

This is the heart of the app. Build this first and get it right; everything else is chrome.

### 7.1 Session structure

A session operates on **one psalm**, advancing **one verse at a time**, with cumulative review folded in.

```
For the current verse V:

  PHASE 1 — READ
    Show V at mask level 0 (full text), in the context of the full psalm.
    User taps "Read" to advance a counter. Require 3 reads before Phase 2 unlocks.
    (3 is the default; make it a constant, not a magic number.)

  PHASE 2 — RECALL LADDER
    Mask level 1 (25% masked) → user recites aloud → taps "I got it" → level 2
    Mask level 2 (50%)        → ... → level 3
    Mask level 3 (75%)        → ... → level 4
    Mask level 4 (100%)       → recite entire verse from blanks

    At any level, "Show more" steps DOWN one level (more words visible).
    "Show less" steps UP one level (fewer words visible).
    Level is never lost permanently — highestMaskLevelCleared is a high-water mark.

  PHASE 3 — PROVISIONAL
    Verse is marked .provisional when the user clears level 4 with zero peeks
    and confirms. Peeking at level 4 resets that attempt (not the high-water mark).
    A .provisional verse counts as in-progress, NOT as memorized, in all
    progress calculations.

  PHASE 3b — CONFIRMATION (a later day)
    See §7.5. A provisional verse becomes .mastered only after a clean
    level-4 pass on a different local calendar day.

  PHASE 4 — CUMULATIVE PASS  (required, not skippable)
    After verse V goes provisional, present verses 1...V together at mask level 4.
    User recites the accumulated block and confirms.
    This is what makes it whole-psalm memorization rather than verse collection.
    On failure, user may drop the cumulative block to level 2 for a supported pass.
    The cumulative pass does NOT itself confer mastery on any verse.

Psalm is .memorized when: every verse is .mastered (not .provisional) AND a
full-psalm level-4 recitation is confirmed.
```

### 7.2 Masking algorithm

Requirements:

1. **Deterministic.** Mask selection is seeded by `(psalmNumber, verseNumber)` so the same words are hidden every time the user sees that verse. Randomizing per session destroys the learning signal.
2. **Layout-stable.** A blank occupies the same width as the word it replaces. Text must not reflow when the mask level changes — reflow is jarring and breaks spatial memory, which is a real part of how people memorize text.
3. **Distributed.** At level 1 (25%), masked words should be spread across the verse, not clustered at the front. Assign `maskIndex` by walking the verse and interleaving positions rather than by shuffling the whole token list.
4. **Punctuation preserved.** Commas, periods, and line-break markers stay visible at all levels. They are structural scaffolding, not content.
5. **"Selah" and superscriptions are never masked.** They are not part of the memorized text by default.

Suggested implementation: precompute `maskIndex` for every word token at content-build time and ship it in the JSON. The runtime then only needs `isMasked = token.maskIndex != nil && token.maskIndex! < ceil(maskLevel/4 * wordCount)`. Zero runtime randomness, trivially testable, identical across devices.

### 7.3 Peek (see §7.6 for long-psalm scoping)

Tapping a single blank reveals that one word for ~2 seconds, then re-hides it. Each peek increments `peekCount`. Peeks are allowed at every level but block mastery confirmation at level 4 (the attempt must be clean). This gives the user a low-friction escape hatch without letting them fake mastery.

### 7.4 Confirmation pass (delayed mastery)

Clearing a verse thirty seconds after reading it four times is short-term recall, not memorization. Mastery therefore requires a second clean pass **on a later day**.

- **Rule:** a `.provisional` verse becomes `.mastered` when the user completes a clean level-4 pass (zero peeks) on a **different local calendar day** from `provisionalAt`. Calendar day, not a rolling 24h window — it's easier to reason about, easier to test, and matches the notification cadence.
- **Placement:** pending confirmations are presented at the **start** of a session, before any new material. Cap the queue at 5 per session, oldest `provisionalAt` first, so a returning user isn't buried.
- **On failure:** the verse drops back to `.inProgress` at mask level 2 and re-enters the ladder. `provisionalAt` is cleared. `highestMaskLevelCleared` is retained — never punish the user by erasing prior work.
- **Timezone/clock:** use the device's current local calendar. Do not attempt to detect clock tampering; a user who wants to cheat their own memorization is not a threat model.
- **Edge case:** if a psalm's verses are all provisional and the user wants to finish, the full-psalm recitation is still gated on all verses reaching `.mastered`. Surface this clearly in the UI ("2 verses awaiting confirmation — come back tomorrow") rather than silently disabling the button.

### 7.5 Superscriptions

Roughly 116 psalms carry a heading ("For the choirmaster. A Psalm of David."). In the BSB these are unnumbered lines above verse 1.

- **Default: display only, never masked.** Rendered in the dimmed style, italic, always fully visible.
- **Setting: "Include psalm headings"** (Settings, default off). When enabled, the superscription becomes a memorizable unit at verse index 0 and participates in the ladder, cumulative review, and psalm completion.
- **Toggling must be non-destructive in both directions.** Enabling adds an `.untouched` VerseState at key 0 for affected psalms and reopens any psalm previously marked complete (surface this: "12 psalms will reopen to include headings"). Disabling hides index 0 and excludes it from all counts but **retains its VerseState** so re-enabling does not erase work. Never delete verse-0 state on toggle.
- Psalms with no superscription (e.g. 1, 2, 33, 91) are unaffected by the setting.

### 7.6 Psalm 119 special handling

176 verses makes naive cumulative review unusable — by verse 100 the user would be reciting 100 verses to add one. Rule:

- For any psalm with more than **40 verses**, cumulative review is scoped to the current **stanza** rather than the whole psalm.
- Psalm 119 has natural 8-verse stanzas (the acrostic sections: Aleph, Beth, Gimel…). Ship these as explicit stanza boundaries in the content JSON.
- For other long psalms without acrostic structure (e.g. 18, 78, 89), chunk into blocks of 8 verses at content-build time.
- Full-psalm recitation confirmation for these psalms is stanza-by-stanza; the psalm completes when all stanzas are confirmed.

---

## 8. Screens

### 8.1 Dashboard (root)

- **Overall progress bar** — psalms memorized / 150. Numeric label: "12 of 150 memorized · 138 remaining".
- **Continue card** — the primary CTA. Shows current psalm, current verse, and per-psalm progress ("Psalm 23 · 3 of 6 verses"). If confirmations are pending, note it ("2 awaiting confirmation"). Tapping resumes the session at the exact verse and phase.
- **Next up** — the next unstarted psalm, one tap to begin.
- **Completed** — a scrollable list of memorized psalms, each opening in Review mode.
- **All psalms** — full 1–150 list with per-psalm progress indicators, so the user can jump anywhere. Do not force strict sequential order; a user may want Psalm 23 before Psalm 4.

### 8.2 Session

- Full psalm rendered as continuous scrolling text.
- The **current verse** is visually active (full opacity); other verses are dimmed but readable — Aaron's requirement is that you always see the full psalm for context.
- Bottom control bar: `Show more` · level indicator (e.g. ●●●○○) · `Show less` · primary action button (`Read` / `I got it` / `Confirm`).
- Verse numbers rendered small, in muted gray, superscript-ish.

### 8.3 Review

Same renderer as Session, read-only, level selector free-floating 0–4. No state is written except `lastOpenedAt`. Lets the user re-test a memorized psalm without risking their completion status.

### 8.4 Settings

- Daily reminder toggle (default **off** — do not request notification permission on first launch).
- Reminder time picker (default 7:00 AM).
- **Include psalm headings** toggle (default off). Enabling shows a confirmation sheet if it would reopen completed psalms (see §7.5).
- Reset progress (destructive, two-step confirm).
- About: translation name (Berean Standard Bible), attribution notice, font licenses (SIL OFL), app version, privacy statement ("This app collects no data and makes no network connections.").

---

## 9. Visual design

### Type

- **Scripture:** a free serif — **Literata** or **Source Serif 4** (both SIL OFL, no attribution burden in-app beyond bundling the license file). Generous line height (1.6), measure capped around 38–42 characters per line on iPhone.
- **UI chrome:** system **SF Pro** (free on Apple platforms, zero bundle cost) or **Inter** (OFL) if a more neutral voice is wanted.
- Ship the OFL license text in the bundle and reference it on the About screen.

### Color

Light mode (primary):

| Role | Value |
|---|---|
| Text | `#1C1C1E` |
| Background | `#FFFFFF` |
| Blank fill | `#FFF4C2` |
| Blank underline | `#E8CE6A` |
| Dimmed verse text | `#8A8A8E` |
| Verse numbers | `#A0A0A5` |
| Progress fill | `#1C1C1E` |
| Progress track | `#EAEAEC` |

Dark mode (required — iOS users expect it; a pure-white app at 5 AM is hostile):

| Role | Value |
|---|---|
| Text | `#F2F2F2` |
| Background | `#0F0F10` |
| Blank fill | `#3A3220` |
| Blank underline | `#C9A94A` |

No other colors. No gradients, no shadows, no decorative imagery.

### Motion

Mask level changes cross-fade over 180ms. Peek reveal fades in 120ms, out 200ms. Nothing else animates.

---

## 10. Notifications

- **Local only**, scheduled by the app via `UNUserNotificationCenter`. No push, no server, no third-party service.
- Permission is requested **only** when the user enables the toggle in Settings, never at launch.
- **Logic:** on every app foreground, cancel all pending notifications and schedule one for `lastOpenedAt + 24h`, clamped to the user's chosen time of day. If the user opens the app, that notification is cancelled and rescheduled on the next backgrounding. Net effect: the user is only notified after a full day of inactivity, exactly as specified.
- Copy should be quiet and non-nagging. Suggested: *"Psalm 23 is waiting — 3 of 6 verses."* Pull the live psalm/verse from progress at schedule time.
- Disabling the toggle cancels all pending notifications immediately.

---

## 11. Content pipeline

A **build-time script** (Swift CLI or Python, not shipped in the app) converts a source text into the bundled JSON:

1. Ingest the BSB in a standard format (USFM or a clean JSON Bible dump).
2. Extract Psalms only.
3. Parse superscriptions to **verse index 0** — they must not be absorbed into verse 1 text. Translations disagree on whether headings are numbered, and the BSB treats them as unnumbered. **This is the single most common data bug in Bible apps; write tests asserting verse 1 of Psalm 3 does not begin with "A Psalm of David."**
4. Tokenize each verse into words / punctuation / `Selah`.
5. Assign deterministic `maskIndex` values per §7.2.
6. Compute stanza boundaries for psalms over 40 verses; hard-code the 22 acrostic stanzas for Psalm 119.
7. Emit `psalms-bsb.json` plus a manifest with the attribution notice.
8. **Validate:** 150 psalms present, verse counts match the published BSB totals, superscriptions correctly separated on all ~116 psalms that have them, no empty verses, no unparsed markup, no orphaned tokens.

Because the pipeline is keyed on `translationId`, swapping in a licensed NIV later is a content-pack change, not a code change.

---

## 12. Accessibility

- Full **Dynamic Type** support, including accessibility sizes. The layout-stability requirement in §7.2 must hold at every type size.
- **VoiceOver:** masked words announce as "blank". The active verse is a single accessibility element reading the visible text with blanks spoken. Level controls have explicit labels ("Show more words").
- Blank fill against white is deliberately low-contrast (it is a visual absence, not content), so the blank must also carry an underline rule to remain perceivable for low-vision and colorblind users. Never rely on the yellow alone.
- Respect **Reduce Motion** (disable cross-fades).
- Minimum tap target 44×44pt, including individual blanks for the peek gesture — at small type sizes, expand the hit area beyond the visual bounds.

---

## 13. Privacy

- No data collection of any kind. No IDFA, no analytics, no crash reporting SDK.
- All progress in the app container. Included in device backups; not synced.
- App Store privacy label: **Data Not Collected**.
- **Free, no in-app purchases.** No StoreKit integration, no receipt validation, no paywall logic anywhere in the codebase.
- State this plainly on the About screen. It is a genuine differentiator in this category, where most Bible apps are aggressive data collectors.

---

## 14. Milestones

| # | Milestone | Acceptance criteria |
|---|---|---|
| M1 | Content pipeline | `psalms-bsb.json` generated and validated; superscriptions correctly separated; all pipeline tests green |
| M2 | Data + persistence | Progress model round-trips through disk; schema versioned; reset works; provisional state persists across launches |
| M3 | Masking renderer | Levels 0–4 render with zero reflow at all Dynamic Type sizes; deterministic across launches |
| M4 | Session engine | Full read → ladder → provisional → cumulative loop for a short psalm (use Psalm 117, 2 verses, for fast test cycles) |
| M5 | Confirmation pass | Provisional verses surface on a later calendar day; clean pass promotes to mastered; failure demotes without losing high-water mark. Test with an injectable clock, not by waiting overnight |
| M6 | Dashboard + Review | Progress accurate at both levels; provisional excluded from memorized counts; resume lands on exact verse and phase |
| M7 | Psalm 119 | Stanza scoping works; 176-verse psalm is completable without absurd cumulative passes |
| M8 | Notifications + Settings | 24h inactivity rule verified; toggle off cancels pending; no permission prompt at launch; superscription toggle non-destructive both ways |
| M9 | Accessibility + polish | VoiceOver pass, Dynamic Type pass, dark mode, Reduce Motion |
| M10 | TestFlight | Ship to Aaron's device; memorize Psalm 23 end-to-end as the acceptance test |

**Note on M5:** the confirmation rule depends on calendar dates, so the date source must be injectable from day one. An execution agent that hard-codes `Date()` throughout will produce a feature that cannot be tested in under 24 hours per case. Wrap it in a `Clock` protocol before writing any mastery logic.

---

## 15. Decisions log

All six open questions resolved by Aaron, August 18, 2026.

| # | Question | Decision |
|---|---|---|
| 1 | Translation | **Berean Standard Bible.** Free for commercial and offline use. NIV/ESV ruled out on licensing (§4) |
| 2 | App name | **Descriptive**, e.g. "Memorize Psalms". Verify no exact collision in App Store Connect before committing — names are first-come |
| 3 | Monetization | **Free, no IAP.** No StoreKit surface at all |
| 4 | Superscriptions | **Display only by default, with a setting to include.** Toggle must be non-destructive in both directions (§7.5) |
| 5 | Cumulative review | **Core to v1, not skippable.** Largest component of M4 |
| 6 | Mastery strictness | **Next-session confirmation required.** Provisional state modeled from the start; injectable clock mandatory (§7.4, M5) |

### Remaining items for Aaron (non-blocking)

- Final app name string and App Store subtitle.
- Confirm the BSB source edition/file the pipeline should ingest.
- Reminder copy tone — the draft ("Psalm 23 is waiting — 3 of 6 verses") is a placeholder.
