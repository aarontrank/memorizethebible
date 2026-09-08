# App Review Information — Notes

Paste this into **App Store Connect → App Review Information → Notes**, and send
the same text as the reply to the Guideline 2.1 message. Apple asked for it in
Notes "for future submissions", so it should live there permanently, not only in
the reply.

The device list in item 2 is filled in with the real devices and is ready to
send as written. The reply below is **3954 characters**, inside the Notes
field's 4,000 limit — keep it under that if you edit it. It has very little
room left: adding a sentence means cutting one.

---

## Reply text

```
Answers to each item below.

1. SCREEN RECORDING
Attached, captured on a physical iPhone 17 running iOS 26.5.2. From the Home Screen it walks the core flow: the walkthrough, a verse taken through every masking level (including tapping a blank to peek), the cumulative recitation, plans, sharing a plan, and turning on the daily reminder — including the notification prompt, the only permission the app requests.

2. DEVICES AND OS TESTED
Physical: iPhone 17, iOS 26.5.2.
Simulator (Xcode 26.6): iPhone 17 Pro Max and 13 Pro Max on iOS 26.2; iPad Pro 13-inch (M5) on iPadOS 26.5 and (M4) on iPadOS 17.5.
Minimum supported OS is iOS 17.0. iPad has been exercised in Simulator at both ends of that range, but not on physical iPad hardware.

3. PURPOSE AND TARGET AUDIENCE
The app helps people commit scripture to memory.

Rereading tests recognition rather than recall, so this app removes the words instead: a verse is read aloud a few times, then a quarter of its words become blanks, then half, then three quarters, then all of them, reciting aloud at each level. Tapping a blank briefly reveals its first letter, or the whole word if tapped again. After each verse the user recites everything so far together.

Audience: anyone memorizing scripture, from personal study to teaching to family use. A study aid with no social layer.

4. SETUP AND ACCESS
No setup, account, or credentials — every feature works immediately on first launch.

On first launch the app offers a short optional walkthrough built on a two-verse demo plan that shows the whole loop in a minute. It can be skipped, and rerun from Settings > Walkthrough.

Direct routes: a chapter is All books > book > chapter, which opens it to read with Start memorizing at the foot. A plan is All plans > plan > Start memorizing. To create one: New plan > add passages > Save, then the share button. Completed items reopen in Review. Settings holds the daily reminder and iCloud sync.

5. EXTERNAL SERVICES, TOOLS, AND PLATFORMS
None. No backend, API, data provider, authentication, payment processor, ad network, analytics, crash reporting, or AI service. Only Apple's own frameworks are linked, and the app has no networking code of its own: every screen works in airplane mode.

The one thing that leaves the device is the user's progress record, and only into their own iCloud account, through iCloud key-value storage (Settings > iCloud, on by default, one tap from off). It is a single small value written by iOS on the app's behalf; there is no server on our side to receive it and no way for us to read it. Progress is stored on the device either way, and the app is fully functional with the setting off or nobody signed in.

Scripture is bundled in the binary, so no text is fetched. Shared plan links carry the plan encoded in the URL — no server there either.

6. REGIONAL DIFFERENCES
None. Identical in every region and storefront: no geo-gating, no region-specific content, no regional pricing (free, no in-app purchases), and no server that could vary. English-only.

7. PROTECTED THIRD-PARTY MATERIAL
The text is the Berean Standard Bible, formally dedicated to the public domain by its publisher and free to use without permission, licence, or royalty; the statement and the text are at https://bereanbible.com. The requested attribution appears in Settings > About and in the App Store description. No other third-party material is included, and the app is not in a regulated industry.

ALSO WORTH KNOWING
No account exists, so no demo credentials are possible. No user-generated content is shared anywhere, so reporting and blocking do not apply. Notification authorization is the only permission requested; iCloud sync uses the account already on the device.

App Privacy is "Data Not Collected": the only thing that leaves the device is the progress record, into the user's own iCloud account, which we cannot access — Apple's definition of collection excludes exactly that.
```

---

## The screen recording — what to film

Apple requires this on a **physical device**, not the Simulator. Record with
iOS's built-in screen recorder (Control Centre), then trim. Two to four minutes
is plenty; do not rush past the masking levels, which are the point of the app.

1. Start on the Home Screen and tap the app icon, so the launch is captured.
2. Take the walkthrough when it offers — the two-verse demo shows the entire
   loop quickly, and it is the clearest possible demonstration of the concept.
3. Then open a real chapter: All books → Psalms → Psalm 23.
4. Work one verse the whole way: Read ×3, then each masking level. **Tap a blank
   to show the peek behaviour.** Finish at "I know it".
5. Let the cumulative recitation step appear and confirm it.
6. All plans → The Roman Road → Start, so plans are shown as distinct from
   chapters.
7. New plan → add a passage → Save → open it → share button, so the share sheet
   and the generated link are on camera.
8. Settings → Daily reminder on → **let the iOS notification prompt appear on
   camera.** Apple explicitly asked for permission prompts to be shown.
9. Finish on a completed chapter opening into Review.

## Before you resubmit

- Item 2 is filled in with the real devices. It states plainly that iPad has
  been tested in Simulator only — say nothing stronger, because Apple reviews on
  physical hardware and will find out.
- **The iPad decision is the one open risk.** See below.
- Nothing about the app itself needs changing for this rejection. It is an
  information request, not a defect.

## The iPad risk, stated plainly

Shipping iPad support means Apple reviews the iPad experience on a physical
iPad. Two things work against that right now:

1. The layout is adapted, not designed. On a 13" iPad the home screen fills
   about a third of the height and leaves the rest empty. It is not broken, but
   it is not a considered iPad app either.
2. It has never run on physical iPad hardware, so nothing has been validated
   against real touch targets, real memory, or real rotation.

Neither is automatically a rejection, but this submission has already been
bounced once, and iPad doubles the surface being judged for no gain on a 1.0.

The lower-risk path is to ship iPhone-only now and add iPad in 1.1, once there
is a device to test on and a layout worth showing:

```
TARGETED_DEVICE_FAMILY = 1;      // in both build configurations
```

Then drop `AppStore/screenshots/ipad-13/` from the listing. The iPad screenshots
are already made and will keep, so nothing is wasted by waiting.
