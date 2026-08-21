#!/usr/bin/env python3
"""Build the bundled scripture content from the Berean Standard Bible.

Design doc: psalms-app-design-doc.md §11 (Content pipeline), generalised from
Psalms to the whole Bible.

This script is a BUILD-TIME tool. It is never shipped in the app.

Two sources, because neither alone is sufficient:

  * `sources/usfm/*.usfm` (ebible.org "engbsb") is authoritative for STRUCTURE:
    `\\d` superscriptions, `\\q1`/`\\q2` poetic lines, `\\qa` acrostic stanzas,
    paragraph breaks.
  * `sources/bsb-full.txt` (bereanbible.com) is authoritative for TEXT: it is a
    newer revision, and the USFM edition differs from it in a few dozen verses.

`reconcile_lines()` aligns the two word streams and re-cuts the current text at
the structural boundaries the USFM identifies.

Output is text plus structure only. Tokenisation and mask ordering happen at
runtime in Swift (`Tokenizer.swift`), which keeps the bundle around 6 MB rather
than the ~45 MB a pre-tokenised corpus of 31,000 verses would need.

Usage:
    python3 build_content.py
    python3 build_content.py --check-only
    python3 build_content.py --books PSA,ROM
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_USFM_DIR = os.path.join(HERE, "sources", "usfm")
DEFAULT_FLAT = os.path.join(HERE, "sources", "bsb-full.txt")
DEFAULT_OUT = os.path.abspath(
    os.path.join(HERE, "..", "..", "App", "MemorizeBible", "Resources", "Content")
)

SCHEMA_VERSION = 2
TRANSLATION_ID = "bsb"
TRANSLATION_NAME = "Berean Standard Bible"
ATTRIBUTION_NOTICE = (
    "Scripture quotations are from the Berean Standard Bible (BSB), produced in "
    "cooperation with Bible Hub, Discovery Bible, unfoldingWord, Bible Aquifer, "
    "OpenBible.com, and the Berean Bible Translation Committee. The BSB text has "
    "been dedicated to the public domain. Free resources and databases are "
    "available at BereanBible.com."
)

# §7.6: chapters longer than this have cumulative review scoped to a stanza.
LONG_CHAPTER_VERSE_THRESHOLD = 40
STANZA_BLOCK_SIZE = 8

# Reference figures. The BSB carries 31,102 verse *numbers*, but 16 of them are
# the "omitted verses" of the critical text (Matthew 17:21, Mark 9:44, John 5:4
# and so on), which the BSB prints empty. Those are not shipped, so verse
# numbering inside a handful of New Testament chapters has deliberate gaps.
EXPECTED_BOOK_COUNT = 66
EXPECTED_CHAPTER_COUNT = 1189
EXPECTED_VERSE_COUNT = 31086
EXPECTED_EMPTY_VERSES = 16
# All 116 belong to Psalms. Zechariah 12 carries an empty \d marker in the
# source, which is not a title and is ignored.
EXPECTED_SUPERSCRIPTIONS = 116

OLD_TESTAMENT_BOOKS = 39

# --------------------------------------------------------------------------
# USFM cleaning
# --------------------------------------------------------------------------

FOOTNOTE_RE = re.compile(r"\\f\b.*?\\f\*", re.DOTALL)
WORD_MARKUP_RE = re.compile(r"\\\+?w\s+(.*?)(?:\|[^\\]*?)?\\\+?w\*")
CHARACTER_MARKUP_RE = re.compile(r"\\\+?(?:it|bd|em|nd|add|tl|qs|wj|sc)\s+(.*?)\\\+?\w+\*")
ANY_MARKER_RE = re.compile(r"\\[a-z0-9+]+\*?", re.IGNORECASE)

# Paragraph markers that begin a new rendered line, and the indent they carry.
# 1 is flush left; poetry steps in from there.
LINE_MARKERS = {
    "q1": 1, "q2": 2, "q3": 3, "q4": 4, "qr": 2, "qm1": 1, "qm2": 2, "qc": 1,
    "m": 1, "mi": 2, "p": 1, "pi": 2, "pi1": 2, "pi2": 3, "pmo": 1, "pc": 1,
    "pm": 1, "pr": 1, "nb": 1, "cls": 1,
    "li": 2, "li1": 2, "li2": 3, "li3": 4,
}
# Editorial apparatus: section headings, cross references, running heads. Not
# scripture, and never shown.
EDITORIAL_MARKERS = {
    "id", "ide", "h", "h1", "toc1", "toc2", "toc3", "mt", "mt1", "mt2", "mt3",
    "ms", "ms1", "ms2", "mr", "s", "s1", "s2", "s3", "sr", "r", "sp", "rem",
    "cl", "cp", "periph", "ib",
}


def clean_inline(text: str) -> str:
    """Strip USFM inline markup from a run of text, leaving plain scripture."""
    text = FOOTNOTE_RE.sub("", text)
    for _ in range(4):
        new = WORD_MARKUP_RE.sub(r"\1", text)
        new = CHARACTER_MARKUP_RE.sub(r"\1", new)
        if new == text:
            break
        text = new
    text = text.replace("\u00a0", " ")
    text = re.sub(r"\s+", " ", text)
    # Removing a footnote can leave a space before its trailing punctuation.
    text = re.sub(r"\s+([,.;:!?\u2019\u201d)\]])", r"\1", text)
    text = re.sub(r"([(\[\u201c])\s+", r"\1", text)
    return text.strip()


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------


class ParsedVerse:
    def __init__(self, number, indent, starts_paragraph):
        self.number = number
        self.indent = indent
        self.starts_paragraph = starts_paragraph
        self.lines = []

    def append(self, indent, text, same_line):
        if same_line and self.lines:
            prev_indent, prev_text = self.lines[-1]
            self.lines[-1] = (prev_indent, (prev_text + " " + text).strip())
        else:
            self.lines.append((indent, text))

    @property
    def text(self):
        return " ".join(t for _, t in self.lines if t).strip()


class ParsedChapter:
    def __init__(self, number):
        self.number = number
        self.superscription_lines = []
        self.verses = []
        self.acrostic_marks = []


class ParsedBook:
    def __init__(self, code, name, order):
        self.code = code
        self.name = name
        self.order = order
        self.chapters = []


def parse_usfm(path, code, order):
    with open(path, encoding="utf-8-sig") as fh:
        raw_lines = fh.read().splitlines()

    book = ParsedBook(code, code, order)
    chapter = None
    verse = None
    pending_indent = None
    pending_paragraph = False
    pending_acrostic = None

    for raw in raw_lines:
        line = raw.strip()
        if not line:
            continue
        match = re.match(r"^\\([a-z0-9]+)\*?\s*(.*)$", line)
        if not match:
            if verse is not None:
                verse.append(verse.indent, clean_inline(line), same_line=True)
            continue
        marker, rest = match.group(1), match.group(2)

        if marker == "h" and rest.strip():
            book.name = clean_inline(rest)
            continue

        if marker == "c":
            chapter = ParsedChapter(int(rest.strip().split()[0]))
            book.chapters.append(chapter)
            verse = None
            pending_indent = None
            pending_paragraph = False
            pending_acrostic = None
            continue

        if marker in EDITORIAL_MARKERS:
            continue

        if marker == "qa":
            pending_acrostic = clean_inline(rest)
            continue

        if marker == "d":
            text = clean_inline(rest)
            if text:
                chapter.superscription_lines.append(text)
            continue

        if marker == "b":
            pending_paragraph = True
            continue

        if marker == "v":
            vm = re.match(r"^(\d+)[\s\-]*(.*)$", rest)
            if not vm:
                raise ValueError(f"unparsable verse marker in {code}: {line!r}")
            number = int(vm.group(1))
            indent = pending_indent if pending_indent is not None else 1
            verse = ParsedVerse(number, indent, pending_paragraph)
            chapter.verses.append(verse)
            if pending_acrostic is not None:
                chapter.acrostic_marks.append((pending_acrostic, number))
                pending_acrostic = None
            pending_paragraph = False
            pending_indent = None
            verse.append(indent, clean_inline(vm.group(2)), same_line=False)
            continue

        if marker in LINE_MARKERS:
            indent = LINE_MARKERS[marker]
            text = clean_inline(rest)
            if not text:
                pending_indent = indent
                continue
            if verse is None:
                # Text before the chapter's first \v: not scripture we can key.
                continue
            verse.append(indent, text, same_line=False)
            continue

        raise ValueError(f"unhandled USFM marker \\{marker} in {code}: {line!r}")

    return book


# --------------------------------------------------------------------------
# Reconciliation: USFM structure, flat-edition text
# --------------------------------------------------------------------------


def normalize_for_compare(s):
    s = unicodedata.normalize("NFKC", s)
    s = s.replace("\u2019", "'").replace("\u2018", "'")
    s = s.replace("\u201c", '"').replace("\u201d", '"')
    s = re.sub(r"[\u2010-\u2015]", "-", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def align_index(opcodes, i, len_a, len_b):
    if i >= len_a:
        return len_b
    for tag, i1, i2, j1, j2 in opcodes:
        if i1 <= i < i2:
            return j1 + (i - i1) if tag == "equal" else j1
    return len_b


def reconcile_lines(usfm_lines, flat_text):
    """Re-cut the authoritative flat text along the USFM's line structure.

    Returns one (indent, text) entry per input line; an entry may be empty if
    the flat edition dropped the words that line held.
    """
    line_words = [line.split() for _, line in usfm_lines]
    usfm_words = [w for words in line_words for w in words]
    flat_words = flat_text.split()

    a = [normalize_for_compare(w).lower() for w in usfm_words]
    b = [normalize_for_compare(w).lower() for w in flat_words]
    opcodes = difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes()

    boundaries = []
    running = 0
    for words in line_words[:-1]:
        running += len(words)
        boundaries.append(running)

    cut = 0
    mapped = []
    for boundary in boundaries:
        j = max(align_index(opcodes, boundary, len(a), len(b)), cut)
        mapped.append(j)
        cut = j

    slices = []
    start = 0
    for j in mapped:
        slices.append(flat_words[start : max(j, start)])
        start = max(j, start)
    slices.append(flat_words[start:])

    return [(indent, " ".join(words)) for (indent, _), words in zip(usfm_lines, slices)]


def load_flat(path):
    """Verse text from the flat edition, keyed by (book name, chapter, verse),
    plus the book names in canonical order."""
    text = {}
    order = []
    with open(path, encoding="utf-8-sig") as fh:
        for line in fh:
            m = re.match(r"^(.+?) (\d+):(\d+)\t(.*?)\s*$", line)
            if not m:
                continue
            book = m.group(1)
            if book not in order:
                order.append(book)
            text[(book, int(m.group(2)), int(m.group(3)))] = m.group(4)
    return text, order


# --------------------------------------------------------------------------
# Stanzas (§7.6)
# --------------------------------------------------------------------------


def compute_stanzas(chapter):
    numbers = [v.number for v in chapter.verses]
    if len(numbers) <= LONG_CHAPTER_VERSE_THRESHOLD:
        return None

    if len(chapter.acrostic_marks) >= 2:
        stanzas = []
        for i, (title, start) in enumerate(chapter.acrostic_marks):
            end = (
                chapter.acrostic_marks[i + 1][1] - 1
                if i + 1 < len(chapter.acrostic_marks)
                else numbers[-1]
            )
            stanzas.append({"i": i, "t": title.title(), "a": start, "b": end})
        return stanzas

    stanzas = []
    for i in range(0, len(numbers), STANZA_BLOCK_SIZE):
        chunk = numbers[i : i + STANZA_BLOCK_SIZE]
        stanzas.append({"i": len(stanzas), "t": None, "a": chunk[0], "b": chunk[-1]})
    if len(stanzas) >= 2 and stanzas[-1]["b"] == stanzas[-1]["a"]:
        tail = stanzas.pop()
        stanzas[-1]["b"] = tail["b"]
    return stanzas


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------


class ValidationError(Exception):
    pass


def first_line(verse_payload):
    lines = verse_payload.get("lines") or []
    return lines[0][1] if lines else ""


def build(usfm_dir, flat_path, only=None):
    flat_text, flat_order = load_flat(flat_path)

    files = sorted(f for f in os.listdir(usfm_dir) if f.endswith(".usfm"))
    if len(files) != len(flat_order):
        raise ValidationError(
            f"{len(files)} USFM books but {len(flat_order)} in the flat edition"
        )

    books = []
    empty_verses = []
    for order, (filename, flat_name) in enumerate(zip(files, flat_order), start=1):
        code = filename[3:6].upper()
        if only and code not in only:
            continue
        parsed = parse_usfm(os.path.join(usfm_dir, filename), code, order)

        chapters = []
        for chapter in parsed.chapters:
            superscription = None
            verses = []
            for verse in chapter.verses:
                flat = flat_text.get((flat_name, chapter.number, verse.number))
                if flat is None:
                    raise ValidationError(
                        f"{flat_name} {chapter.number}:{verse.number} missing from the flat edition"
                    )
                if not flat.strip():
                    # An omitted verse the BSB prints empty; nothing to memorize.
                    empty_verses.append(f"{flat_name} {chapter.number}:{verse.number}")
                    continue

                usfm_lines = [(i, t) for i, t in verse.lines if t]
                if not usfm_lines:
                    usfm_lines = [(verse.indent, flat)]

                is_first = verse.number == chapter.verses[0].number
                if is_first and chapter.superscription_lines:
                    combined = [(0, " ".join(chapter.superscription_lines))] + usfm_lines
                    out = reconcile_lines(combined, flat)
                    superscription = out[0][1]
                    lines = [(i, t) for i, t in out[1:] if t]
                else:
                    lines = [(i, t) for i, t in reconcile_lines(usfm_lines, flat) if t]
                if not lines:
                    lines = [(verse.indent, flat)]

                payload = {"n": verse.number, "lines": [[i, t] for i, t in lines]}
                if verse.starts_paragraph:
                    payload["p"] = 1
                verses.append(payload)

            entry = {"n": chapter.number, "verses": verses}
            if superscription:
                entry["d"] = superscription
            stanzas = compute_stanzas(chapter)
            if stanzas:
                entry["stanzas"] = stanzas
            chapters.append(entry)

        books.append(
            {
                "id": code,
                "name": parsed.name,
                "order": order,
                "testament": "old" if order <= OLD_TESTAMENT_BOOKS else "new",
                "chapters": chapters,
            }
        )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "translationId": TRANSLATION_ID,
        "name": TRANSLATION_NAME,
        "attributionNotice": ATTRIBUTION_NOTICE,
        "longChapterVerseThreshold": LONG_CHAPTER_VERSE_THRESHOLD,
        "books": books,
        "_emptyVerses": empty_verses,
    }


# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------


def validate(doc, flat_text, flat_order, partial=False):
    errors = []
    books = doc["books"]

    if not partial:
        if len(books) != EXPECTED_BOOK_COUNT:
            errors.append(f"expected {EXPECTED_BOOK_COUNT} books, got {len(books)}")
        chapters = sum(len(b["chapters"]) for b in books)
        if chapters != EXPECTED_CHAPTER_COUNT:
            errors.append(f"expected {EXPECTED_CHAPTER_COUNT} chapters, got {chapters}")
        verses = sum(len(c["verses"]) for b in books for c in b["chapters"])
        if verses != EXPECTED_VERSE_COUNT:
            errors.append(f"expected {EXPECTED_VERSE_COUNT} verses, got {verses}")
        supers = sum(1 for b in books for c in b["chapters"] if c.get("d"))
        if supers != EXPECTED_SUPERSCRIPTIONS:
            errors.append(f"expected {EXPECTED_SUPERSCRIPTIONS} superscriptions, got {supers}")

    by_id = {b["id"]: b for b in books}
    flat_name_by_order = {i + 1: name for i, name in enumerate(flat_order)}

    # Anything the flat edition numbers but we do not ship must be one of the
    # omitted verses, and must be empty there. This is what stops a parsing
    # slip from silently dropping real scripture.
    if not partial:
        shipped = {
            (flat_name_by_order[b["order"]], c["n"], v["n"])
            for b in books
            for c in b["chapters"]
            for v in c["verses"]
        }
        dropped = sorted(set(flat_text) - shipped)
        non_empty = [ref for ref in dropped if flat_text[ref].strip()]
        if non_empty:
            errors.append(
                f"{len(non_empty)} verses with text were dropped, e.g. {non_empty[:5]}"
            )
        if len(dropped) != EXPECTED_EMPTY_VERSES:
            errors.append(
                f"expected {EXPECTED_EMPTY_VERSES} omitted verses, got {len(dropped)}"
            )

    for book in books:
        flat_name = flat_name_by_order[book["order"]]
        chapter_numbers = [c["n"] for c in book["chapters"]]
        if chapter_numbers != list(range(1, len(chapter_numbers) + 1)):
            errors.append(f"{book['id']}: chapters are not 1..n in order")

        for chapter in book["chapters"]:
            label = f"{book['id']} {chapter['n']}"
            if not chapter["verses"]:
                errors.append(f"{label}: no verses")
                continue

            numbers = [v["n"] for v in chapter["verses"]]
            if numbers != sorted(numbers) or len(set(numbers)) != len(numbers):
                errors.append(f"{label}: verse numbers are not strictly increasing")

            for verse in chapter["verses"]:
                text = " ".join(t for _, t in verse["lines"]).strip()
                vlabel = f"{label}:{verse['n']}"
                if not text:
                    errors.append(f"{vlabel}: empty text")
                if ANY_MARKER_RE.search(text):
                    errors.append(f"{vlabel}: unstripped USFM markup: {text[:60]!r}")
                if "|strong=" in text:
                    errors.append(f"{vlabel}: leftover Strong's attribute")

                # The text must match the flat edition exactly, verse for verse.
                flat = flat_text.get((flat_name, chapter["n"], verse["n"]))
                ours = text
                if verse["n"] == chapter["verses"][0]["n"] and chapter.get("d"):
                    ours = chapter["d"] + " " + ours
                if flat is None:
                    errors.append(f"{vlabel}: missing from the flat edition")
                elif normalize_for_compare(ours) != normalize_for_compare(flat):
                    errors.append(
                        f"{vlabel} differs from the flat edition\n"
                        f"    ours: {ours[:100]!r}\n    flat: {flat[:100]!r}"
                    )

            stanzas = chapter.get("stanzas")
            if len(chapter["verses"]) > doc["longChapterVerseThreshold"]:
                if not stanzas:
                    errors.append(f"{label}: {len(chapter['verses'])} verses but no stanzas")
                else:
                    # Stanza bounds are inclusive ranges, and a few New
                    # Testament chapters have gaps where an omitted verse sits,
                    # so compare the verses actually covered.
                    present = set(numbers)
                    covered = []
                    for stanza in stanzas:
                        covered.extend(
                            n for n in range(stanza["a"], stanza["b"] + 1) if n in present
                        )
                    if covered != numbers:
                        errors.append(f"{label}: stanzas do not tile the chapter")
                    bounds = [(stanza["a"], stanza["b"]) for stanza in stanzas]
                    if any(a > b for a, b in bounds) or bounds != sorted(bounds):
                        errors.append(f"{label}: stanza bounds are not ordered")
            elif stanzas:
                errors.append(f"{label}: short chapter should not carry stanzas")

    if partial:
        return errors

    # Psalms specifics, unchanged from when this shipped Psalms alone.
    psalms = by_id.get("PSA")
    if not psalms:
        errors.append("Psalms is missing")
        return errors
    if len(psalms["chapters"]) != 150:
        errors.append(f"expected 150 psalms, got {len(psalms['chapters'])}")
    if psalms["name"] != "Psalms":
        errors.append(f"Psalms is named {psalms['name']!r}")

    chapter_by_number = {c["n"]: c for c in psalms["chapters"]}
    for number, expected in ((117, 2), (119, 176), (23, 6), (1, 6)):
        actual = len(chapter_by_number[number]["verses"])
        if actual != expected:
            errors.append(f"Psalm {number}: expected {expected} verses, got {actual}")

    # THE bug §11 warns about: a superscription absorbed into verse 1.
    for number in (3, 4, 5, 23, 51, 90, 142):
        first = chapter_by_number[number]["verses"][0]
        text = " ".join(t for _, t in first["lines"])
        if re.match(r"^(A |For the choirmaster|A Psalm|A Song|A prayer|A Maskil)", text):
            errors.append(f"Psalm {number}:1 begins with superscription text: {text[:50]!r}")
    if not chapter_by_number[3].get("d"):
        errors.append("Psalm 3 has no superscription")
    for number in (1, 2, 33, 91):
        if chapter_by_number[number].get("d"):
            errors.append(f"Psalm {number} should have no superscription")

    st119 = chapter_by_number[119].get("stanzas") or []
    if len(st119) != 22:
        errors.append(f"Psalm 119: expected 22 acrostic stanzas, got {len(st119)}")
    elif any(s["b"] - s["a"] + 1 != 8 for s in st119):
        errors.append("Psalm 119: every acrostic stanza must be exactly 8 verses")
    elif st119[0]["t"] != "Aleph":
        errors.append(f"Psalm 119: first stanza is {st119[0]['t']!r}")

    # Superscriptions belong to Psalms alone.
    stray = [
        f"{b['id']} {c['n']}"
        for b in books
        if b["id"] != "PSA"
        for c in b["chapters"]
        if c.get("d")
    ]
    if stray:
        errors.append(f"superscriptions outside Psalms: {stray}")

    return errors


# --------------------------------------------------------------------------
# Emission
# --------------------------------------------------------------------------


def write_bundle(doc, out_dir, pretty=False):
    """Emit a manifest plus one file per book.

    The manifest carries everything a list screen needs — book names, chapter
    and verse counts, first lines, stanza tables — without touching a single
    verse. Book files hold the text, loaded lazily.
    """
    dump = dict(ensure_ascii=False)
    if pretty:
        dump["indent"] = 2
    else:
        dump["separators"] = (",", ":")

    os.makedirs(out_dir, exist_ok=True)
    for stale in os.listdir(out_dir):
        if re.match(r"^(book-[A-Z0-9]{3}|manifest|psalm-\d{3})\.json$", stale):
            os.remove(os.path.join(out_dir, stale))

    entries = []
    total_bytes = 0
    for book in doc["books"]:
        path = os.path.join(out_dir, f"book-{book['id']}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({"id": book["id"], "chapters": book["chapters"]}, fh, **dump)
        total_bytes += os.path.getsize(path)

        entries.append(
            {
                "id": book["id"],
                "name": book["name"],
                "order": book["order"],
                "testament": book["testament"],
                "chapters": [
                    {
                        "n": chapter["n"],
                        "verseCount": len(chapter["verses"]),
                        "firstVerse": chapter["verses"][0]["n"],
                        "hasSuperscription": bool(chapter.get("d")),
                        "firstLine": first_line(chapter["verses"][0])[:80],
                        "stanzas": chapter.get("stanzas"),
                    }
                    for chapter in book["chapters"]
                ],
            }
        )

    manifest = {
        "schemaVersion": doc["schemaVersion"],
        "translationId": doc["translationId"],
        "name": doc["name"],
        "attributionNotice": doc["attributionNotice"],
        "longChapterVerseThreshold": doc["longChapterVerseThreshold"],
        "bookCount": len(doc["books"]),
        "chapterCount": sum(len(b["chapters"]) for b in doc["books"]),
        "verseCount": sum(len(c["verses"]) for b in doc["books"] for c in b["chapters"]),
        "books": entries,
    }
    manifest_path = os.path.join(out_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, **dump)

    print(
        f"    wrote {out_dir}: manifest.json ({os.path.getsize(manifest_path) / 1024:.0f} KB)"
        f" + {len(doc['books'])} book files ({total_bytes / 1024 / 1024:.1f} MB)"
    )


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--usfm", default=DEFAULT_USFM_DIR)
    ap.add_argument("--flat", default=DEFAULT_FLAT)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--books", help="comma-separated book codes, for quick iteration")
    ap.add_argument("--pretty", action="store_true")
    ap.add_argument("--check-only", action="store_true")
    args = ap.parse_args(argv)

    only = {b.strip().upper() for b in args.books.split(",")} if args.books else None
    doc = build(args.usfm, args.flat, only=only)
    flat_text, flat_order = load_flat(args.flat)
    errors = validate(doc, flat_text, flat_order, partial=bool(only))
    if errors:
        print(f"VALIDATION FAILED ({len(errors)} problems):", file=sys.stderr)
        for error in errors[:40]:
            print("  - " + error, file=sys.stderr)
        return 1

    books = len(doc["books"])
    chapters = sum(len(b["chapters"]) for b in doc["books"])
    verses = sum(len(c["verses"]) for b in doc["books"] for c in b["chapters"])
    print(f"OK  {books} books · {chapters} chapters · {verses} verses")
    if doc["_emptyVerses"]:
        print(f"    omitted (empty in the BSB): {len(doc['_emptyVerses'])}")

    if not args.check_only:
        write_bundle(doc, args.out, pretty=args.pretty)
    return 0


if __name__ == "__main__":
    sys.exit(main())
