# Content pipeline (milestone M1)

Build-time only. Nothing here ships in the app.

## Run

```sh
python3 build_content.py            # validate + write App/MemorizeBible/Resources/Content
python3 build_content.py --check-only
python3 -m unittest test_content -v
```

## Sources

Both files are checked in so the build is reproducible without network access.

| File | Origin | Role |
|---|---|---|
| `sources/20-PSAengbsb.usfm` | ebible.org `engbsb_usfm.zip` | **structure**: `\d` superscriptions, `\q1`/`\q2` poetic lines, `\qa` acrostic stanzas |
| `sources/bsb-psalms-flat.txt` | bereanbible.com `bsb.txt`, Psalms rows only | **text**: the current BSB wording |

Two sources because neither alone is sufficient:

- The flat edition folds each psalm's superscription into verse 1 ("A Psalm of
  David. The LORD is my shepherd..."). §11 of the design doc names this as the
  single most common data bug in Bible apps, so it cannot be the structural
  source.
- The ebible USFM edition is an older BSB revision. 35 verses differ in wording
  from the current text (Psalm 10:10 "hapless"/"helpless", Psalm 3's heading
  reading "A Psalms of David"), so it cannot be the text source.

`reconcile_lines()` aligns the two word streams and re-cuts the current text at
the structural boundaries the USFM identifies. `validate()` then asserts the
output text matches the flat edition exactly, verse for verse.

The BSB is dedicated to the public domain. The attribution notice emitted into
`manifest.json` is rendered on the About screen (§8.4).

## Output

`App/MemorizeBible/Resources/Content/`

- `manifest.json` — translation metadata plus, for all 150 psalms, verse count,
  whether it has a superscription, its first line, and its stanza table. This is
  everything the dashboard needs; it never touches verse text.
- `psalm-001.json` … `psalm-150.json` — tokens, loaded lazily per psalm (§5).

## Regenerating sources

```sh
curl -L -o engbsb_usfm.zip https://ebible.org/Scriptures/engbsb_usfm.zip
unzip -j engbsb_usfm.zip 20-PSAengbsb.usfm -d sources/
curl -L https://bereanbible.com/bsb.txt | grep -E '^(Psalm [0-9]+:[0-9]+\t|The Holy Bible|This text|Verse\t)' > sources/bsb-psalms-flat.txt
```

Re-run the tests after regenerating: the verse-count and reconciliation
assertions are what catch an upstream edition change.
