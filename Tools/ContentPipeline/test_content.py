#!/usr/bin/env python3
"""Tests for the content pipeline (design doc §11).

The pipeline is responsible for STRUCTURE and TEXT only — tokenisation and mask
ordering moved into Swift when the app grew from Psalms to the whole Bible, and
are covered by `MaskingTests` and `CorpusTests` there.

Run:  python3 -m unittest discover -s Tools/ContentPipeline -v
"""

import os
import unittest

import build_content as bc


class CleanInlineTests(unittest.TestCase):
    def test_strips_strongs_markup(self):
        self.assertEqual(
            bc.clean_inline('Blessed \\w is|strong="H1870"\\w* \\w the|strong="H1870"\\w* man'),
            "Blessed is the man",
        )

    def test_strips_footnotes_without_leaving_a_space(self):
        self.assertEqual(
            bc.clean_inline("and seek after lies \\f + \\fr 4:2 \\ft A note.\\f*?"),
            "and seek after lies?",
        )

    def test_strips_character_markup(self):
        self.assertEqual(bc.clean_inline("the \\it Selah\\it* here"), "the Selah here")

    def test_collapses_whitespace(self):
        self.assertEqual(bc.clean_inline("  two   spaces  "), "two spaces")


class ParseTests(unittest.TestCase):
    """Parsing rules exercised on inline USFM fixtures."""

    def parse(self, text, code="TST"):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".fixture.usfm")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        try:
            return bc.parse_usfm(path, code, 1)
        finally:
            os.remove(path)

    def test_reads_the_book_name_from_the_running_head(self):
        book = self.parse("\\id TST\n\\h Psalms\n\\c 1\n\\q1\n\\v 1 Blessed.\n")
        self.assertEqual(book.name, "Psalms")

    def test_superscription_is_separated_from_verse_one(self):
        book = self.parse(
            "\\c 23\n\\s1 The LORD Is My Shepherd\n\\d A Psalm of David.\n"
            "\\q1\n\\v 1 The LORD is my shepherd;\n\\q2 I shall not want.\n"
        )
        chapter = book.chapters[0]
        self.assertEqual(chapter.superscription_lines, ["A Psalm of David."])
        self.assertEqual(chapter.verses[0].text, "The LORD is my shepherd; I shall not want.")

    def test_an_empty_descriptive_title_is_not_a_superscription(self):
        # Zechariah 12 carries a bare \d in the source.
        book = self.parse("\\c 12\n\\d\n\\m\n\\v 1 This is the burden.\n")
        self.assertEqual(book.chapters[0].superscription_lines, [])

    def test_section_headings_are_not_scripture(self):
        book = self.parse("\\c 1\n\\s1 The Two Paths\n\\r (Matthew 5:3-12)\n\\q1\n\\v 1 Blessed.\n")
        self.assertEqual(book.chapters[0].verses[0].text, "Blessed.")

    def test_prose_and_poetry_carry_different_indents(self):
        book = self.parse("\\c 1\n\\m\n\\v 1 Prose here.\n\\q2 Poetry here.\n")
        verse = book.chapters[0].verses[0]
        self.assertEqual([indent for indent, _ in verse.lines], [1, 2])

    def test_acrostic_headings_mark_stanza_starts(self):
        book = self.parse("\\c 119\n\\qa ALEPH\n\\q1\n\\v 1 Blessed.\n\\qa BETH\n\\q1\n\\v 9 How can?\n")
        self.assertEqual(book.chapters[0].acrostic_marks, [("ALEPH", 1), ("BETH", 9)])

    def test_list_items_are_line_markers(self):
        book = self.parse("\\c 1\n\\li1\n\\v 1 An item.\n")
        self.assertEqual(book.chapters[0].verses[0].text, "An item.")

    def test_unknown_marker_is_a_hard_error(self):
        with self.assertRaises(ValueError):
            self.parse("\\c 1\n\\q1\n\\v 1 Blessed.\n\\zz something new\n")


class ReconcileTests(unittest.TestCase):
    def test_flat_text_wins_but_usfm_line_breaks_are_kept(self):
        out = bc.reconcile_lines(
            [(1, "They are crushed and beaten down;"), (2, "the hapless fall prey.")],
            "They are crushed and beaten down; the helpless fall prey.",
        )
        self.assertEqual(
            out, [(1, "They are crushed and beaten down;"), (2, "the helpless fall prey.")]
        )

    def test_line_count_is_preserved(self):
        out = bc.reconcile_lines([(1, "a b"), (2, "c d"), (1, "e f")], "a b c d e f")
        self.assertEqual([text for _, text in out], ["a b", "c d", "e f"])

    def test_a_single_line_passes_through(self):
        self.assertEqual(bc.reconcile_lines([(1, "old words")], "new words"), [(1, "new words")])


class StanzaTests(unittest.TestCase):
    def chapter(self, verse_count, acrostic=None):
        chapter = bc.ParsedChapter(1)
        for number in range(1, verse_count + 1):
            chapter.verses.append(bc.ParsedVerse(number, 1, False))
        chapter.acrostic_marks = acrostic or []
        return chapter

    def test_short_chapters_have_no_stanzas(self):
        self.assertIsNone(bc.compute_stanzas(self.chapter(6)))
        self.assertIsNone(bc.compute_stanzas(self.chapter(40)))

    def test_long_chapters_chunk_into_blocks_of_eight(self):
        stanzas = bc.compute_stanzas(self.chapter(50))
        self.assertEqual((stanzas[0]["a"], stanzas[0]["b"]), (1, 8))
        self.assertEqual(stanzas[-1]["b"], 50)

    def test_acrostic_boundaries_win_when_present(self):
        marks = [(f"S{i}", 1 + i * 8) for i in range(22)]
        stanzas = bc.compute_stanzas(self.chapter(176, marks))
        self.assertEqual(len(stanzas), 22)
        self.assertTrue(all(s["b"] - s["a"] == 7 for s in stanzas))

    def test_stanzas_tile_the_chapter(self):
        for count in range(41, 90):
            covered = []
            for stanza in bc.compute_stanzas(self.chapter(count)):
                covered.extend(range(stanza["a"], stanza["b"] + 1))
            self.assertEqual(covered, list(range(1, count + 1)), f"{count} verses")


@unittest.skipUnless(
    os.path.isdir(bc.DEFAULT_USFM_DIR) and os.path.exists(bc.DEFAULT_FLAT),
    "BSB sources not present",
)
class CorpusTests(unittest.TestCase):
    """The §11 acceptance criteria, run against the whole Bible."""

    @classmethod
    def setUpClass(cls):
        cls.doc = bc.build(bc.DEFAULT_USFM_DIR, bc.DEFAULT_FLAT)
        cls.flat_text, cls.flat_order = bc.load_flat(bc.DEFAULT_FLAT)
        cls.by_id = {b["id"]: b for b in cls.doc["books"]}

    def test_full_validation_passes(self):
        errors = bc.validate(self.doc, self.flat_text, self.flat_order)
        self.assertEqual(errors, [], "\n".join(errors[:20]))

    def test_reference_figures(self):
        self.assertEqual(len(self.doc["books"]), 66)
        self.assertEqual(sum(len(b["chapters"]) for b in self.doc["books"]), 1189)
        self.assertEqual(
            sum(len(c["verses"]) for b in self.doc["books"] for c in b["chapters"]), 31086
        )

    def test_books_are_in_canonical_order(self):
        self.assertEqual([b["order"] for b in self.doc["books"]], list(range(1, 67)))
        self.assertEqual(self.doc["books"][0]["name"], "Genesis")
        self.assertEqual(self.doc["books"][-1]["name"], "Revelation")
        self.assertEqual(sum(1 for b in self.doc["books"] if b["testament"] == "old"), 39)

    def test_psalm_3_verse_1_does_not_begin_with_a_psalm_of_david(self):
        """§11: the single most common data bug in Bible apps."""
        psalms = {c["n"]: c for c in self.by_id["PSA"]["chapters"]}
        first = " ".join(t for _, t in psalms[3]["verses"][0]["lines"])
        self.assertFalse(first.startswith("A Psalm of David"))
        self.assertEqual(psalms[3]["d"], "A Psalm of David, when he fled from his son Absalom.")

    def test_superscriptions_belong_to_psalms_alone(self):
        count = 0
        for book in self.doc["books"]:
            for chapter in book["chapters"]:
                if chapter.get("d"):
                    count += 1
                    self.assertEqual(book["id"], "PSA", f"{book['id']} {chapter['n']}")
        self.assertEqual(count, 116)

    def test_omitted_verses_are_absent_rather_than_empty(self):
        shipped = {
            (self.flat_order[b["order"] - 1], c["n"], v["n"])
            for b in self.doc["books"]
            for c in b["chapters"]
            for v in c["verses"]
        }
        dropped = set(self.flat_text) - shipped
        self.assertEqual(len(dropped), 16)
        for ref in dropped:
            self.assertEqual(self.flat_text[ref].strip(), "", f"{ref} had text and was dropped")

    def test_no_verse_is_empty_and_no_markup_survives(self):
        for book in self.doc["books"]:
            for chapter in book["chapters"]:
                for verse in chapter["verses"]:
                    text = " ".join(t for _, t in verse["lines"])
                    self.assertTrue(text.strip())
                    self.assertNotIn("\\", text)
                    self.assertNotIn("|strong=", text)

    def test_psalm_119_has_twenty_two_acrostic_stanzas(self):
        psalms = {c["n"]: c for c in self.by_id["PSA"]["chapters"]}
        stanzas = psalms[119]["stanzas"]
        self.assertEqual(len(stanzas), 22)
        self.assertEqual(stanzas[0]["t"], "Aleph")
        self.assertTrue(all(s["b"] - s["a"] == 7 for s in stanzas))

    def test_long_chapters_everywhere_are_stanza_scoped(self):
        for book in self.doc["books"]:
            for chapter in book["chapters"]:
                if len(chapter["verses"]) > bc.LONG_CHAPTER_VERSE_THRESHOLD:
                    self.assertIn("stanzas", chapter, f"{book['id']} {chapter['n']}")

    def test_output_is_deterministic(self):
        again = bc.build(bc.DEFAULT_USFM_DIR, bc.DEFAULT_FLAT, only={"ROM"})
        first = [b for b in self.doc["books"] if b["id"] == "ROM"]
        self.assertEqual(again["books"], first)


if __name__ == "__main__":
    unittest.main()
