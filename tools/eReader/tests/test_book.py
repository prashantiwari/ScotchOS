"""book.py on tiny fixtures: chapters, TOC, anchors, links, images, search, the library scan and the cache.

Run: python3 -m unittest discover -s tools/eReader/tests   (or `scotchos test`)
The EPUB fixtures are folders, zipped here, and the images are made here, so the repo holds no binaries.
"""
import base64
import contextlib
import importlib.util
import io
import json
import os
import re
import shutil
import struct
import sys
import tempfile
import time
import unittest
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "fixtures")
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("book", os.path.join(HERE, "..", "book.py"))
book = importlib.util.module_from_spec(spec)
spec.loader.exec_module(book)


def png(w, h):
    """A valid w x h grey PNG."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\x00" + b"\x80" * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def zip_folder(folder, out, extra=None):
    """An EPUB from a fixture folder: `mimetype` first and stored, as the spec wants; `extra` adds files."""
    with zipfile.ZipFile(out, "w") as z:
        z.write(os.path.join(folder, "mimetype"), "mimetype", compress_type=zipfile.ZIP_STORED)
        for dirpath, _, files in os.walk(folder):
            for name in sorted(files):
                rel = os.path.relpath(os.path.join(dirpath, name), folder)
                if rel != "mimetype":
                    z.write(os.path.join(dirpath, name), rel, compress_type=zipfile.ZIP_DEFLATED)
        for name, data in (extra or {}).items():
            z.writestr(name, data)
    return out


def chapters(outdir):
    """book.json, and each chapter's HTML."""
    with open(os.path.join(outdir, "book.json"), encoding="utf-8") as f:
        meta = json.load(f)
    texts = []
    for ch in meta["chapters"]:
        with open(os.path.join(outdir, ch["file"]), encoding="utf-8") as f:
            texts.append(f.read())
    return meta, texts


def plain(html_text):
    return " ".join(re.sub(r"<[^>]+>|" + book.MARK, " ", html_text).split())


def p_depth(html_text):
    """The deepest nesting of <p> elements."""
    depth = deepest = 0
    for close in re.findall(r"<(/?)p\b", html_text):
        depth += -1 if close else 1
        deepest = max(deepest, depth)
    return deepest


def toc(meta):
    return [(e["level"], e["title"], e["chapter"], e["anchor"]) for e in meta["toc"]]


class Fixture(unittest.TestCase):
    """A temp library with every fixture in it, and a temp cache."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="scotchos-book-test-")
        self.lib = os.path.join(self.tmp, "library")
        self.cache = os.path.join(self.tmp, "cache")
        os.makedirs(os.path.join(self.lib, "notes"))
        self.epub3 = zip_folder(os.path.join(FIXTURES, "epub3"), os.path.join(self.lib, "three.epub"),
                                {"OEBPS/img/cover.png": png(60, 90), "OEBPS/img/pic.png": png(20, 10)})
        self.epub2 = zip_folder(os.path.join(FIXTURES, "epub2"), os.path.join(self.lib, "two.epub"),
                                {"cover.png": png(30, 45)})
        with open(os.path.join(FIXTURES, "book.fb2"), encoding="utf-8") as f:
            fb2 = f.read().replace("@COVER@", base64.b64encode(png(40, 60)).decode()) \
                          .replace("@PIC@", base64.b64encode(png(8, 4)).decode())
        self.fb2 = os.path.join(self.lib, "book.fb2")
        with open(self.fb2, "w", encoding="utf-8") as f:
            f.write(fb2)
        self.txt = shutil.copy(os.path.join(FIXTURES, "gutenberg.txt"), os.path.join(self.lib, "plain_tale.txt"))
        # The Markdown book is in a folder with its picture; a "secret" image sits next to that folder.
        self.md = shutil.copy(os.path.join(FIXTURES, "notes.md"), os.path.join(self.lib, "notes", "notes.md"))
        with open(os.path.join(self.lib, "notes", "pic.png"), "wb") as f:
            f.write(png(12, 6))
        with open(os.path.join(self.lib, "secret.png"), "wb") as f:
            f.write(png(1, 1))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def open(self, path):
        return chapters(book.open_book(path, self.cache))


# ---- Formats ----

class Epub3(Fixture):
    def test_chapters_follow_the_spine_with_non_linear_last(self):
        meta, texts = self.open(self.epub3)
        self.assertEqual((meta["title"], meta["author"]), ("Test EPUB Three", "Ada Author"))
        self.assertEqual(len(texts), 3)
        self.assertIn("Chapter One", texts[0])
        self.assertIn("Opening words", texts[1])
        self.assertIn("The note's text", texts[2])

    def test_nav_toc_with_a_nested_entry_and_its_anchor(self):
        meta, _ = self.open(self.epub3)
        # The landmarks nav is ignored; "Section   Two" has its spaces collapsed.
        self.assertEqual(toc(meta), [(1, "Chapter One", 0, -1), (1, "Chapter Two", 1, -1), (2, "Section Two", 1, 0)])
        self.assertEqual([c["anchors"] for c in meta["chapters"]], [1, 1, 1])

    def test_links_between_documents_and_to_the_web(self):
        _, texts = self.open(self.epub3)
        self.assertIn('<a href="scotchos:1:0">section two</a>', texts[0])     # ch%202.xhtml#sec2
        self.assertIn('<a href="scotchos:2:0">', texts[0])                    # the note
        self.assertIn('<a href="scotchos:0:0">1</a>', texts[2])               # and back
        self.assertIn('<a href="https://example.com/">web</a>', texts[0])
        self.assertNotIn("mailto", texts[0])
        self.assertIn("or mail.", plain(texts[0]))

    def test_styles_scripts_and_classes_are_dropped(self):
        _, texts = self.open(self.epub3)
        for bad in ("style", "class", "script", "color", "dropped", "<head", "<title"):
            self.assertNotIn(bad, texts[0])

    def test_images_are_copied_with_their_size_and_remote_ones_dropped(self):
        outdir = book.open_book(self.epub3, self.cache)
        _, texts = chapters(outdir)
        imgs = re.findall(r'<img src="file://([^"]+)" width="(\d+)" height="(\d+)" alt="([^"]*)">', texts[0])
        self.assertEqual(len(imgs), 1)
        path, w, h, alt = imgs[0]
        self.assertEqual((w, h, alt), ("20", "10", "A picture"))
        # The URL points into the cache, not the temp dir the book was built in.
        self.assertTrue(path.startswith(outdir + "/img/") and os.path.isfile(path))
        self.assertNotIn("remote", texts[0])

    def test_cover(self):
        meta, cover = book.file_meta(self.epub3)
        self.assertEqual(book.image_size(cover), (60, 90))

    def test_search(self):
        r = book.search(book.open_book(self.epub3, self.cache), "quick   BROWN fox")
        self.assertEqual(r["total"], 2)
        first, second = r["results"]
        # Across an <i> and a line break, any case; `n` counts within the chapter.
        self.assertEqual((first["chapter"], first["n"], first["where"], first["match"]),
                         (1, 0, "Section Two", "quick brown fox"))
        self.assertEqual((second["n"], second["match"], second["after"]), (1, "QUICK brown fox", " sleeps."))
        self.assertTrue(first["before"].endswith("The "))
        self.assertEqual(book.search(book.open_book(self.epub3, self.cache), "  ")["total"], 0)
        self.assertEqual(book.search(book.open_book(self.epub3, self.cache), "absent")["total"], 0)


class Epub2(Fixture):
    def test_ncx_toc_and_metadata(self):
        meta, texts = self.open(self.epub2)
        self.assertEqual((meta["title"], meta["author"]), ("Test EPUB Two", "Bo Writer"))
        # The blank first document makes no chapter.
        self.assertEqual(len(texts), 2)
        self.assertEqual(toc(meta), [(1, "Part One", 0, -1), (2, "The Middle", 0, 0), (1, "Part Two", 1, -1)])
        self.assertEqual([c["title"] for c in meta["chapters"]], ["Part One", "Part Two"])

    def test_sloppy_html(self):
        _, texts = self.open(self.epub2)
        self.assertIn("<b>bold <i>and italic</i></b>", texts[0])
        self.assertIn('<p align="center">Centred</p>', texts[0])
        self.assertIn("The end &amp; that’s all.", texts[1])
        # Each unclosed <p> is closed by the next block, so paragraphs never nest.
        self.assertEqual([p_depth(t) for t in texts], [1, 1])
        self.assertIn("<p>Unclosed paragraph one\n</p><p>Unclosed paragraph two", texts[0])

    def test_a_block_closes_an_open_paragraph_but_not_across_a_table_cell(self):
        s = book.Sanitizer(lambda src: None, lambda href: "")
        s.feed("<p>a<div>b</div><p>c<ul><li>d</li></ul><p>e<table><tr><td><div>f</div></td></tr></table>"
               "<table><tr><td><p>g<blockquote>h</blockquote></td></tr></table>")
        self.assertEqual(s.result(), "<p>a</p><div>b</div><p>c</p><ul><li>d</li></ul><p>e</p><table><tr><td>"
                                     "<div>f</div></td></tr></table><table><tr><td><p>g</p><blockquote>h</blockquote>"
                                     "</td></tr></table>")

    def test_a_link_to_a_blank_page_lands_on_the_next_chapter(self):
        _, texts = self.open(self.epub2)
        self.assertIn('<a href="scotchos:0:-1">blank page</a>', texts[0])

    def test_cover_from_meta_name(self):
        _, cover = book.file_meta(self.epub2)
        self.assertEqual(book.image_size(cover), (30, 45))

    def test_drm_is_refused_and_font_obfuscation_is_not(self):
        enc = ('<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
               'xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData>'
               '<enc:EncryptionMethod Algorithm="%s"/></enc:EncryptedData></encryption>')
        drm = zip_folder(os.path.join(FIXTURES, "epub2"), os.path.join(self.tmp, "drm.epub"),
                         {"META-INF/encryption.xml": enc % "http://www.w3.org/2001/04/xmlenc#aes128-cbc"})
        with self.assertRaisesRegex(book.BookError, "DRM"):
            book.open_book(drm, self.cache)
        fonts = zip_folder(os.path.join(FIXTURES, "epub2"), os.path.join(self.tmp, "fonts.epub"),
                           {"META-INF/encryption.xml": enc % "http://www.idpf.org/2008/embedding"})
        self.assertEqual(len(chapters(book.open_book(fonts, self.cache))[1]), 2)


class Fb2(Fixture):
    def check(self, path):
        meta, texts = self.open(path)
        self.assertEqual((meta["title"], meta["author"]), ("Test FB2", "Fyodor M. Fixture"))
        # The body's title and epigraph, two top-level sections, the notes body.
        self.assertEqual(len(texts), 4)
        self.assertEqual(toc(meta), [(1, "First Chapter", 1, -1), (2, "Inner Part", 1, 1),
                                     (1, "Second Chapter", 2, -1), (1, "Notes", 3, -1)])
        self.assertIn("A lead epigraph", texts[0])
        self.assertIn('<a href="scotchos:3:0">[1]</a>', texts[1])       # the note
        self.assertIn('<a href="scotchos:2:0">the second</a>', texts[1])
        self.assertIn('<a href="https://example.com/">web</a>', texts[1])
        self.assertIn("<i>words</i>", texts[1])
        self.assertRegex(texts[1], r'<img src="file://[^"]+/img/0000\.png" width="8" height="4"')
        self.assertIn("<p>A line of verse,</p><p>and another.</p>", texts[2])
        self.assertIn("The note's text", texts[3])
        self.assertEqual(book.image_size(book.file_meta(path)[1]), (40, 60))

    def test_fb2(self):
        self.check(self.fb2)

    def test_fb2_zip(self):
        zipped = os.path.join(self.lib, "book.fb2.zip")
        with zipfile.ZipFile(zipped, "w") as z:
            z.write(self.fb2, "inside.fb2")
        self.assertEqual(book.fmt_of(zipped), ".fb2.zip")
        self.check(zipped)


class Txt(Fixture):
    def test_gutenberg_header_and_chapters(self):
        self.assertEqual(book.file_meta(self.txt)[0], {"title": "A Plain Tale", "author": "Tex Teller"})
        meta, texts = self.open(self.txt)
        self.assertEqual(meta["title"], "A Plain Tale")
        self.assertEqual(len(texts), 3)
        self.assertEqual(toc(meta), [(1, "CHAPTER I. THE START", 1, -1), (1, "CHAPTER II. THE END", 2, -1)])

    def test_wrapped_prose_is_joined_and_short_lines_kept(self):
        _, texts = self.open(self.txt)
        self.assertIn("seventy characters per line", texts[1])
        self.assertIn("<p>A short verse<br>kept on its lines<br>as it was written</p>", texts[1])
        # A contents list is a paragraph of short lines, not headings.
        self.assertIn("CONTENTS<br>I. The Start<br>II. The End", texts[0])


class Markdown(Fixture):
    def test_chapters_at_level_one_and_two_headings(self):
        meta, texts = self.open(self.md)
        self.assertEqual(meta["title"], "Markdown Notes")     # the first "# " heading
        self.assertEqual(len(texts), 2)
        self.assertEqual(toc(meta), [(1, "Markdown Notes", 0, -1), (2, "Second Part", 1, -1)])
        # A "#" line inside a code fence is not a heading.
        self.assertIn("<pre># not a heading inside a fence</pre>", texts[1])

    def test_inline_markup_lists_and_quotes(self):
        _, texts = self.open(self.md)
        for s in ("<b>bold</b>", "<i>italic</i>", "<code>code</code>", "<ul>\n<li>one</li>",
                  "<blockquote><p>A quote</p></blockquote>", '<a href="https://example.com/">web link</a>'):
            self.assertIn(s, texts[0])
        self.assertIn("<ol>\n<li>first</li>", texts[1])
        self.assertIn("and a local link.", texts[0])         # a link to a file is dropped, its text kept

    def test_title_is_the_first_level_one_heading_else_the_file_name(self):
        other = os.path.join(self.lib, "my_draft.md")
        with open(other, "w", encoding="utf-8") as f:
            f.write("```\n# in a fence\n```\n## Not level one\n\nText.\n\n# The *Real* Title ##\n")
        self.assertEqual(book.file_meta(other)[0]["title"], "The Real Title")
        with open(other, "w", encoding="utf-8") as f:
            f.write("## Only a level two\n\nText.\n")
        self.assertEqual(book.file_meta(other)[0]["title"], "my draft")

    def test_images_only_from_the_books_folder(self):
        _, texts = self.open(self.md)
        self.assertEqual(len(re.findall(r"<img ", texts[0])), 1)
        self.assertIn('width="12" height="6" alt="A picture"', texts[0])
        self.assertNotIn("Outside", texts[0])


# ---- Library and cache ----

class Library(Fixture):
    def test_scan_lists_every_book_sorted_by_title(self):
        books = book.scan(self.lib, self.cache)
        self.assertEqual([(b["title"], b["format"]) for b in books],
                         [("A Plain Tale", "txt"), ("Markdown Notes", "md"), ("Test EPUB Three", "epub"),
                          ("Test EPUB Two", "epub"), ("Test FB2", "fb2")])
        covers = {b["title"]: b["cover"] for b in books}
        self.assertTrue(os.path.isfile(covers["Test EPUB Three"]))
        self.assertEqual(covers["A Plain Tale"], "")

    def test_scan_skips_hidden_files_and_folders_and_link_cycles(self):
        os.makedirs(os.path.join(self.lib, ".hidden"))
        shutil.copy(self.txt, os.path.join(self.lib, ".hidden", "x.txt"))
        shutil.copy(self.txt, os.path.join(self.lib, ".x.txt"))
        os.symlink(self.lib, os.path.join(self.lib, "notes", "loop"))
        self.assertEqual(len(book.scan(self.lib, self.cache)), 5)

    def test_a_broken_book_is_listed_by_its_name(self):
        with open(os.path.join(self.lib, "broken.epub"), "wb") as f:
            f.write(b"not a zip")
        with contextlib.redirect_stderr(io.StringIO()):     # scan reports the file on stderr
            books = book.scan(self.lib, self.cache)
        self.assertIn("broken.epub", [b["title"] for b in books])
        self.assertIn("error", book_cli("open", os.path.join(self.lib, "broken.epub"), self.cache))

    def test_a_removed_book_loses_its_cover(self):
        book.scan(self.lib, self.cache)
        covers = os.path.join(self.cache, "covers")
        self.assertEqual(len(os.listdir(covers)), 3)
        os.remove(self.epub3)
        book.scan(self.lib, self.cache)
        self.assertEqual(len(os.listdir(covers)), 2)

    def test_a_moved_book_keeps_its_position(self):
        books = book.scan(self.lib, self.cache)
        old = next(b for b in books if b["format"] == "fb2")
        progress = os.path.join(self.tmp, "progress.json")
        with open(progress, "w") as f:
            json.dump({old["id"]: {"path": old["path"], "title": old["title"], "size": old["size"], "chapter": 2}}, f)
        os.rename(self.fb2, os.path.join(self.lib, "notes", "renamed.fb2"))
        books = book.scan(self.lib, self.cache)
        new = next(b for b in books if b["format"] == "fb2")
        self.assertEqual(book.moved(books, progress), {new["id"]: old["id"]})

    def test_open_converts_once_and_again_when_the_file_changes(self):
        outdir = book.open_book(self.txt, self.cache)
        first = os.path.join(outdir, "c0000.html")
        os.utime(first, (0, 0))
        self.assertEqual(book.open_book(self.txt, self.cache), outdir)
        self.assertEqual(os.stat(first).st_mtime, 0)            # not rebuilt
        later = time.time() + 10
        os.utime(self.txt, (later, later))
        book.open_book(self.txt, self.cache)
        self.assertNotEqual(os.stat(first).st_mtime, 0)         # rebuilt
        self.assertFalse([n for n in os.listdir(self.cache) if n.startswith(".build-")])

    def test_a_failed_conversion_leaves_nothing(self):
        bad = os.path.join(self.lib, "empty.txt")
        open(bad, "w").close()
        with self.assertRaisesRegex(book.BookError, "no readable text"):
            book.open_book(bad, self.cache)
        self.assertEqual(os.listdir(self.cache), [])


class Export(Fixture):
    def test_every_bookmark_with_its_chapter_and_text(self):
        outdir = book.open_book(self.epub2, self.cache)
        entry = {"title": "ignored", "bookmarks": [
            {"chapter": 0, "pos": 10, "percent": 12.4, "text": "Unclosed  paragraph\none", "where": "The Middle"},
            {"chapter": 1, "pos": 0, "percent": 80, "text": "", "where": ""},
            {"chapter": 7, "pos": 0, "percent": 99.6, "text": "Out of range"}]}
        out = os.path.join(self.tmp, "notes dir", "Test EPUB Two.md")
        self.assertEqual(book_cli("export", outdir, json.dumps(entry), out), {"path": out})
        with open(out, encoding="utf-8") as f:
            self.assertEqual(f.read(), "# Test EPUB Two\n\n*Bo Writer*\n\n## Bookmarks\n\n"
                                       "### The Middle · 12%\n\n> Unclosed paragraph one\n\n"
                                       "### Part Two · 80%\n\n> (page without text)\n\n"
                                       "### Chapter 8 · 100%\n\n> Out of range\n")

    def test_no_bookmarks(self):
        out = os.path.join(self.tmp, "x.md")
        book.export(book.open_book(self.md, self.cache), {}, out)
        with open(out, encoding="utf-8") as f:
            self.assertEqual(f.read(), "# Markdown Notes\n\n## Bookmarks\n\nNone.\n")


def book_cli(*args):
    """book.py's output as the shell gets it."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        code = book.main(["book.py", *args])
    assert code == 0
    return json.loads(out.getvalue())


class Cli(unittest.TestCase):
    def test_errors_are_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(book_cli("open", os.path.join(tmp, "missing.epub"), tmp),
                             {"error": "File not found: " + os.path.join(tmp, "missing.epub")})
            other = os.path.join(tmp, "a.pdf")
            open(other, "w").close()
            self.assertEqual(book_cli("open", other, tmp), {"error": "Unsupported format."})


if __name__ == "__main__":
    unittest.main()
