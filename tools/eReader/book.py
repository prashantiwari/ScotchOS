#!/usr/bin/env python3
"""ScotchOS e-reader helper: lists the library and converts books into theme-free HTML chapters.

  book.py scan <library_dir> <cache_dir>   JSON list of books (metadata and covers cached)
  book.py open <file> <cache_dir>          converts once into <cache_dir>/<id>/, prints {"dir": ...}

Errors are printed as {"error": "..."} with exit code 0, so the shell can show them.
Stdlib only; MOBI/AZW3 text needs the `mobi` package (AUR python-mobi).
"""
import base64
import hashlib
import html
import json
import os
import posixpath
import re
import shutil
import struct
import sys
import tempfile
import zipfile
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit

VERSION = 2                     # bump to rebuild every cached book after a converter change
SPLIT = 100_000                 # a chapter over this many bytes of HTML is split between blocks
MARK = "\u2060"                 # invisible marker standing where an element id was (QML finds anchors by it)
FORMATS = (".epub", ".mobi", ".azw3", ".azw", ".fb2", ".fb2.zip", ".txt", ".md", ".markdown")


class BookError(Exception):
    pass


def book_id(path):
    return hashlib.sha1(os.path.realpath(path).encode()).hexdigest()[:16]


def fmt_of(path):
    low = path.lower()
    return next((f for f in sorted(FORMATS, key=len, reverse=True) if low.endswith(f)), "")


def stamp(path):
    st = os.stat(path)
    return [st.st_size, int(st.st_mtime), VERSION]


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


# ---- Image sizes (PNG, JPEG, GIF headers) ----

def image_size(data):
    try:
        if data[:8] == b"\x89PNG\r\n\x1a\n":
            return struct.unpack(">II", data[16:24])
        if data[:6] in (b"GIF87a", b"GIF89a"):
            return struct.unpack("<HH", data[6:10])
        if data[:2] == b"\xff\xd8":
            i = 2
            while i < len(data) - 9:
                if data[i] != 0xFF:
                    i += 1
                    continue
                marker = data[i + 1]
                if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                    h, w = struct.unpack(">HH", data[i + 5:i + 9])
                    return w, h
                i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    except (struct.error, IndexError):
        pass
    return None


def image_ext(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return ".png"
    if data[:3] == b"GIF":
        return ".gif"
    if data[:2] == b"\xff\xd8":
        return ".jpg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ".webp"
    if b"<svg" in data[:512]:
        return ".svg"
    return ".img"


# ---- HTML sanitizer: keeps structure, drops every style ----

BLOCKS = {"p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "ul", "ol", "li", "pre", "hr", "table",
          "dl", "dt", "dd", "figure", "figcaption", "section", "article", "aside", "header", "footer", "center",
          "tr", "td", "th", "thead", "tbody", "tfoot", "caption", "nav", "main"}
# Tag -> what Qt's rich text gets (None = drop the tag, keep its content).
TAGS = {"p": "p", "div": "div", "h1": "h1", "h2": "h2", "h3": "h3", "h4": "h4", "h5": "h5", "h6": "h6",
        "blockquote": "blockquote", "ul": "ul", "ol": "ol", "li": "li", "pre": "pre", "code": "code",
        "em": "i", "i": "i", "cite": "i", "dfn": "i", "var": "i", "strong": "b", "b": "b", "u": "u",
        "s": "s", "strike": "s", "del": "s", "sup": "sup", "sub": "sub", "small": "small", "big": "big",
        "br": "br", "hr": "hr", "table": "table", "tr": "tr", "td": "td", "th": "th", "thead": None,
        "tbody": None, "tfoot": None, "caption": "p", "dl": "dl", "dt": "dt", "dd": "dd", "a": "a",
        "figure": "div", "figcaption": "p", "section": "div", "article": "div", "aside": "blockquote",
        "header": "div", "footer": "div", "center": "div", "nav": "div", "main": "div", "tt": "code",
        "kbd": "code", "samp": "code", "q": None, "span": None, "abbr": None, "font": None, "body": None}
SKIP = {"head", "script", "style", "title", "noscript", "template", "math"}
VOID = {"br", "hr", "img", "image", "meta", "link", "input", "col", "wbr", "area", "base", "source"}


class Sanitizer(HTMLParser):
    """Turns one (X)HTML document into Qt-friendly HTML.

    resolve_img(src) -> (url, w, h) or None; resolve_link(href) -> placeholder or "" (drop) or a web URL.
    """

    def __init__(self, resolve_img, resolve_link):
        super().__init__(convert_charrefs=True)
        self.resolve_img, self.resolve_link = resolve_img, resolve_link
        self.out = []
        self.size = 0
        self.stack = []             # (tag, emitted) of open elements
        self.skip = 0
        self.depth = 0              # open block elements
        self.cuts = []              # output offsets where a top-level block starts (chapter split points)
        self.anchors = []           # [(offset, id)]
        self.breaks = []            # offsets of mbp:pagebreak (forced splits)
        self.headings = []          # [(offset, level, text, id)]
        self._heading = None

    def emit(self, s):
        self.out.append(s)
        self.size += len(s)
        if self._heading is not None and not s.startswith("<"):
            self._heading[2].append(s)

    def mark(self, ident):
        self.anchors.append((self.size, ident))
        self.emit(MARK)

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag in SKIP:
            if tag not in VOID:
                self.skip += 1
            return
        if self.skip:
            return
        a = dict(attrs)
        if tag == "mbp:pagebreak":
            self.breaks.append(self.size)
            return
        if tag in BLOCKS and self.depth == 0:
            self.cuts.append(self.size)
        ident = a.get("id") or (a.get("name") if tag == "a" else None)
        if tag in ("img", "image"):
            src = a.get("src") or a.get("xlink:href") or a.get("href")
            if ident:
                self.mark(ident)
            img = self.resolve_img(src) if src else None
            if img:
                url, w, h = img
                alt = html.escape(a.get("alt", ""), quote=True)
                self.emit(f'<img src="{html.escape(url, quote=True)}" width="{w}" height="{h}" alt="{alt}">'
                          if w else f'<img src="{html.escape(url, quote=True)}" alt="{alt}">')
            return
        out = TAGS.get(tag)
        if tag == "a":
            href = a.get("href")
            link = self.resolve_link(href) if href else ""
            out = "a" if link else None
            if out:
                self.stack.append((tag, out, tag in BLOCKS))
                self.emit(f'<a href="{html.escape(link, quote=True)}">')
                if ident:
                    self.mark(ident)
                return
        if tag in VOID:
            if ident:
                self.mark(ident)
            if out:
                self.emit(f"<{out}>")
            return
        block = tag in BLOCKS
        self.stack.append((tag, out, block))
        if block:
            self.depth += 1
        if out:
            align = a.get("align", "").lower()
            if tag == "center":
                align = "center"
            self.emit(f'<{out} align="{align}">' if align in ("center", "right") and out in ("p", "div") else f"<{out}>")
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self._heading = [self.size, int(tag[1]), [], ident]
        if ident:
            self.mark(ident)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag.lower() not in VOID and tag.lower() not in SKIP:
            self.handle_endtag(tag)
        elif tag.lower() in SKIP and tag.lower() not in VOID:
            self.skip -= 1

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag in SKIP:
            if tag not in VOID:
                self.skip = max(0, self.skip - 1)
            return
        if self.skip or tag in VOID:
            return
        # Close up to the matching tag (tolerates unclosed elements in sloppy HTML).
        if not any(t == tag for t, _, _ in self.stack):
            return
        while self.stack:
            t, out, block = self.stack.pop()
            if out:
                self.emit(f"</{out}>")
            if block:
                self.depth -= 1
            if t in ("h1", "h2", "h3", "h4", "h5", "h6") and self._heading is not None:
                off, level, parts, ident = self._heading
                text = re.sub(r"\s+", " ", html.unescape("".join(parts))).replace(MARK, "").strip()
                if text:
                    self.headings.append((off, level, text, ident))
                self._heading = None
            if t == tag:
                break

    def handle_data(self, data):
        if self.skip:
            return
        self.emit(html.escape(data.replace(MARK, ""), quote=False))

    def result(self):
        while self.stack:
            self.handle_endtag(self.stack[-1][0])
        return "".join(self.out)


# ---- Book writer: chapters, anchors, links, images, TOC ----

class Builder:
    """Collects documents in reading order, splits big ones, and writes book.json + cNNN.html."""

    def __init__(self, outdir):
        self.outdir = outdir
        self.imgdir = os.path.join(outdir, "img")
        os.makedirs(self.imgdir, exist_ok=True)
        self.chapters = []          # {"html", "anchors": [ids], "title", "doc"}
        self.where = {}             # (doc, id) -> (chapter, anchor index); (doc, "") -> chapter start
        self.headings = []          # [(chapter, level, text, anchor index or -1)]
        self.images = {}            # key -> (url, w, h)

    def image(self, key, data):
        if key not in self.images:
            if not data:
                return None
            name = f"{len(self.images):04d}{image_ext(data)}"
            path = os.path.join(self.imgdir, name)
            with open(path, "wb") as f:
                f.write(data)
            w, h = image_size(data) or (0, 0)
            self.images[key] = ("file://" + path, w, h)
        return self.images[key]

    def add(self, doc, text, resolve_img, resolve_link, title=""):
        """doc: a name links use; text: the document's HTML."""
        s = Sanitizer(resolve_img, resolve_link)
        s.feed(text)
        s.close()
        body = s.result()
        if not re.sub(r"<[^>]+>|\s|" + MARK, "", body) and "<img" not in body:
            # Empty page: links to it land on the next chapter.
            self.where.setdefault((doc, ""), (len(self.chapters), -1))
            for _, ident in s.anchors:
                self.where.setdefault((doc, ident), (len(self.chapters), -1))
            return
        # Split points: forced page breaks, then top-level blocks once a piece grows past SPLIT.
        forced = sorted(set(s.breaks))
        pieces, start = [], 0
        cuts = sorted(set(s.cuts + forced))
        for c in cuts:
            if c <= start:
                continue
            if c in forced or c - start >= SPLIT:
                pieces.append((start, c))
                start = c
        pieces.append((start, len(body)))
        first = len(self.chapters)
        self.where.setdefault((doc, ""), (first, -1))
        for a, b in pieces:
            chunk = body[a:b]
            if not re.sub(r"<[^>]+>|\s|" + MARK, "", chunk) and "<img" not in chunk:
                continue
            idx = len(self.chapters)
            ids = [ident for off, ident in s.anchors if a <= off < b]
            for n, ident in enumerate(ids):
                self.where.setdefault((doc, ident), (idx, n))
            for off, level, text, ident in s.headings:
                if a <= off < b:
                    n = ids.index(ident) if ident in ids else -1
                    self.headings.append((idx, level, text, n))
            self.chapters.append({"html": chunk, "anchors": ids, "title": title if idx == first else ""})

    def locate(self, doc, ident=""):
        return self.where.get((doc, ident)) or self.where.get((doc, ""))

    def finish(self, meta, toc):
        """toc: [(level, title, doc, id)]; falls back to the headings when it's empty."""
        entries = []
        for level, title, doc, ident in toc:
            loc = self.locate(doc, ident)
            if loc and title:
                entries.append({"title": title, "level": level, "chapter": loc[0], "anchor": loc[1]})
        if not entries:
            levels = sorted({lv for _, lv, _, _ in self.headings})[:2]
            entries = [{"title": t, "level": levels.index(lv) + 1, "chapter": c, "anchor": n}
                       for c, lv, t, n in self.headings if lv in levels]
        # Chapter titles: the last TOC entry pointing at or before each chapter.
        last = ""
        for i, ch in enumerate(self.chapters):
            here = [e["title"] for e in entries if e["chapter"] == i]
            if here:
                last = here[0]
            ch["title"] = ch["title"] or last
        link = re.compile(r'href="@@([^"]*)@@"')

        def fix(m):
            doc, _, ident = html.unescape(m.group(1)).partition("#")
            loc = self.locate(doc, ident)
            return f'href="scotchos:{loc[0]}:{loc[1]}"' if loc else 'href="scotchos:-1:-1"'

        chapters = []
        for i, ch in enumerate(self.chapters):
            text = link.sub(fix, ch["html"])
            name = f"c{i:04d}.html"
            with open(os.path.join(self.outdir, name), "w", encoding="utf-8") as f:
                f.write(text)
            chapters.append({"file": name, "title": ch["title"], "size": len(re.sub(r"<[^>]+>", "", text)) or 1,
                             "anchors": len(ch["anchors"])})
        if not chapters:
            raise BookError("This book has no readable text.")
        meta = dict(meta, chapters=chapters, toc=entries)
        write_json(os.path.join(self.outdir, "book.json"), meta)


# ---- EPUB ----

def zread(z, name):
    try:
        return z.read(name)
    except KeyError:
        # Some books get the case of their own paths wrong.
        low = name.lower()
        for n in z.namelist():
            if n.lower() == low:
                return z.read(n)
    return None


def decode(data):
    for enc in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", "replace")


def local(tag):
    return tag.rsplit("}", 1)[-1]


def epub_opf(z):
    if "META-INF/encryption.xml" in z.namelist():
        enc = ET.fromstring(z.read("META-INF/encryption.xml"))
        algos = [e.get("Algorithm", "") for e in enc.iter() if local(e.tag) == "EncryptionMethod"]
        # Font obfuscation (IDPF / Adobe) is harmless; anything else is DRM.
        if any("font" not in a.lower() and "obfuscation" not in a.lower() for a in algos):
            raise BookError("This EPUB is DRM-protected.")
    root = ET.fromstring(zread(z, "META-INF/container.xml"))
    path = next(e.get("full-path") for e in root.iter() if local(e.tag) == "rootfile")
    opf = ET.fromstring(zread(z, path))
    base = posixpath.dirname(path)
    manifest = {}
    for e in opf.iter():
        if local(e.tag) == "item":
            manifest[e.get("id")] = {"href": posixpath.normpath(posixpath.join(base, unquote(e.get("href", "")))),
                                     "type": e.get("media-type", ""), "props": e.get("properties", "")}
    spine = [e.get("idref") for e in opf.iter() if local(e.tag) == "itemref" and e.get("linear") != "no"]
    spine += [e.get("idref") for e in opf.iter() if local(e.tag) == "itemref" and e.get("linear") == "no"]
    toc_id = next((e.get("toc") for e in opf.iter() if local(e.tag) == "spine"), None)
    meta = {"title": "", "author": ""}
    cover_id = None
    for e in opf.iter():
        t = local(e.tag)
        if t == "title" and not meta["title"]:
            meta["title"] = (e.text or "").strip()
        elif t == "creator" and not meta["author"]:
            meta["author"] = (e.text or "").strip()
        elif t == "meta" and e.get("name") == "cover":
            cover_id = e.get("content")
    cover = None
    for k, v in manifest.items():
        if "cover-image" in v["props"]:
            cover = v["href"]
    if not cover and cover_id in manifest:
        cover = manifest[cover_id]["href"]
    if not cover:
        cover = next((v["href"] for k, v in manifest.items()
                      if v["type"].startswith("image/") and "cover" in (k + v["href"]).lower()), None)
    return opf, manifest, spine, toc_id, meta, cover


def epub_meta(path):
    with zipfile.ZipFile(path) as z:
        _, _, _, _, meta, cover = epub_opf(z)
        data = zread(z, cover) if cover else None
    return meta, data


class NavParser(HTMLParser):
    """The EPUB 3 nav document's toc: nested <ol><li><a href>."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.in_toc = 0
        self.level = 0
        self.entries = []
        self.cur = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "nav" and ("toc" in a.get("epub:type", "") or ("toc" == a.get("id") and not self.entries)):
            self.in_toc = 1
        elif self.in_toc:
            if tag == "nav":
                self.in_toc += 1
            elif tag == "ol":
                self.level += 1
            elif tag in ("a", "span") and self.cur is None:
                self.cur = [self.level, a.get("href", ""), []]

    def handle_endtag(self, tag):
        if not self.in_toc:
            return
        if tag == "nav":
            self.in_toc -= 1
        elif tag == "ol":
            self.level -= 1
        elif tag in ("a", "span") and self.cur is not None:
            self.entries.append((self.cur[0], " ".join("".join(self.cur[2]).split()), self.cur[1]))
            self.cur = None

    def handle_data(self, data):
        if self.cur is not None:
            self.cur[2].append(data)


def epub_build(path, outdir, meta_override=None):
    b = Builder(outdir)
    with zipfile.ZipFile(path) as z:
        opf, manifest, spine, toc_id, meta, cover = epub_opf(z)
        if meta_override:
            meta = {k: meta.get(k) or v for k, v in meta_override.items()}
        docs = [manifest[i]["href"] for i in spine if i in manifest]
        docset = set(docs)

        for doc in docs:
            data = zread(z, doc)
            if data is None:
                continue
            base = posixpath.dirname(doc)

            def img(src, base=base):
                if re.match(r"^[a-z]+:", src, re.I):
                    return None     # remote or data: images are dropped
                key = posixpath.normpath(posixpath.join(base, unquote(src.split("#")[0])))
                return b.image(key, zread(z, key))

            def link(href, base=base, doc=doc):
                if re.match(r"^https?://", href, re.I):
                    return href
                if re.match(r"^[a-z]+:", href, re.I):
                    return ""
                parts = urlsplit(href)
                target = posixpath.normpath(posixpath.join(base, unquote(parts.path))) if parts.path else doc
                if target not in docset:
                    return ""
                return f"@@{target}#{parts.fragment}@@"

            b.add(doc, decode(data), img, link)

        toc = []
        nav = next((v["href"] for v in manifest.values() if "nav" in v["props"].split()), None)
        if nav and zread(z, nav):
            p = NavParser()
            p.feed(decode(zread(z, nav)))
            base = posixpath.dirname(nav)
            for level, title, href in p.entries:
                parts = urlsplit(href)
                if parts.path:
                    toc.append((level, title, posixpath.normpath(posixpath.join(base, unquote(parts.path))),
                                parts.fragment))
        ncx = manifest.get(toc_id, {}).get("href") or next(
            (v["href"] for v in manifest.values() if v["type"] == "application/x-dtbncx+xml"), None)
        if not toc and ncx and zread(z, ncx):
            base = posixpath.dirname(ncx)

            def walk(node, level):
                for e in node:
                    if local(e.tag) != "navPoint":
                        continue
                    label = next((t.text or "" for t in e.iter() if local(t.tag) == "text"), "")
                    src = next((c.get("src", "") for c in e if local(c.tag) == "content"), "")
                    parts = urlsplit(src)
                    toc.append((level, " ".join(label.split()),
                                posixpath.normpath(posixpath.join(base, unquote(parts.path))), parts.fragment))
                    walk(e, level + 1)

            navmap = next((e for e in ET.fromstring(zread(z, ncx)).iter() if local(e.tag) == "navMap"), None)
            if navmap is not None:
                walk(navmap, 1)
    b.finish(meta, toc)


# ---- MOBI / AZW3 headers (stdlib): metadata, cover, DRM ----

def mobi_headers(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[60:68] not in (b"BOOKMOBI", b"TEXtREAd"):
        raise BookError("Not a MOBI/AZW file.")
    n = struct.unpack(">H", data[76:78])[0]
    offsets = [struct.unpack(">I", data[78 + i * 8:82 + i * 8])[0] for i in range(n)] + [len(data)]
    rec0 = data[offsets[0]:offsets[1]]
    meta = {"title": data[:32].split(b"\0")[0].decode("latin-1").replace("_", " "), "author": ""}
    encrypted = struct.unpack(">H", rec0[12:14])[0] != 0
    cover = None
    if rec0[16:20] == b"MOBI":
        hlen = struct.unpack(">I", rec0[20:24])[0]
        enc = "utf-8" if struct.unpack(">I", rec0[28:32])[0] == 65001 else "cp1252"
        name_off, name_len = struct.unpack(">II", rec0[84:92])
        if name_len:
            meta["title"] = rec0[name_off:name_off + name_len].decode(enc, "replace")
        first_img = struct.unpack(">I", rec0[108:112])[0]
        if struct.unpack(">I", rec0[128:132])[0] & 0x40:
            ex = 16 + hlen
            if rec0[ex:ex + 4] == b"EXTH":
                count = struct.unpack(">I", rec0[ex + 8:ex + 12])[0]
                p = ex + 12
                for _ in range(count):
                    typ, ln = struct.unpack(">II", rec0[p:p + 8])
                    val = rec0[p + 8:p + ln]
                    if typ == 100 and not meta["author"]:
                        meta["author"] = val.decode(enc, "replace").strip()
                    elif typ == 503:
                        meta["title"] = val.decode(enc, "replace").strip()
                    elif typ == 201 and first_img != 0xFFFFFFFF:
                        idx = first_img + struct.unpack(">I", val[:4])[0]
                        if idx < n:
                            cover = data[offsets[idx]:offsets[idx + 1]]
                    p += ln
    return meta, cover, encrypted


def mobi_build(path, outdir):
    meta, _, encrypted = mobi_headers(path)
    if encrypted:
        raise BookError("This book is DRM-protected.")
    try:
        import mobi
    except ImportError:
        raise BookError("MOBI/AZW3 needs the mobi library: yay -S python-mobi")
    tmp, out = mobi.extract(path)
    try:
        if out.lower().endswith(".epub"):
            return epub_build(out, outdir, meta)
        # Old MOBI: one HTML file (split at mbp:pagebreak) with its images beside it.
        base = os.path.dirname(out)
        b = Builder(outdir)

        def img(src):
            if re.match(r"^[a-z]+:", src, re.I):
                return None
            p = os.path.normpath(os.path.join(base, unquote(src)))
            if not p.startswith(tmp) or not os.path.isfile(p):
                return None
            with open(p, "rb") as f:
                return b.image(p, f.read())

        def link(href):
            if re.match(r"^https?://", href, re.I):
                return href
            return f"@@book#{href[1:]}@@" if href.startswith("#") else ""

        with open(out, "rb") as f:
            b.add("book", decode(f.read()), img, link)
        b.finish(meta, [])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---- FB2 ----

def fb2_root(path):
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            name = next((n for n in z.namelist() if n.lower().endswith(".fb2")), None)
            if not name:
                raise BookError("No .fb2 inside this zip.")
            data = z.read(name)
    else:
        with open(path, "rb") as f:
            data = f.read()
    return ET.fromstring(data)


def fb2_href(e):
    return next((v for k, v in e.attrib.items() if local(k) == "href"), "")


def fb2_meta(root):
    meta = {"title": "", "author": ""}
    cover = None
    binaries = {e.get("id"): e.text or "" for e in root if local(e.tag) == "binary"}
    info = next((e for e in root.iter() if local(e.tag) == "title-info"), None)
    if info is not None:
        for e in info:
            t = local(e.tag)
            if t == "book-title":
                meta["title"] = (e.text or "").strip()
            elif t == "author" and not meta["author"]:
                meta["author"] = " ".join((c.text or "").strip() for c in e
                                          if local(c.tag) in ("first-name", "middle-name", "last-name")).strip()
            elif t == "coverpage":
                img = next((c for c in e.iter() if local(c.tag) == "image"), None)
                if img is not None:
                    try:
                        cover = base64.b64decode(binaries.get(fb2_href(img).lstrip("#"), ""))
                    except ValueError:
                        pass
    return meta, cover, binaries


def fb2_title(section):
    t = next((c for c in section if local(c.tag) == "title"), None)
    return " ".join(" ".join(t.itertext()).split()) if t is not None else ""


def fb2_build(path, outdir):
    root = fb2_root(path)
    meta, _, binaries = fb2_meta(root)
    b = Builder(outdir)
    ids = {}                    # element id -> doc name, filled before links are resolved

    def inline(e):
        out = []
        tag = local(e.tag)
        wrap = {"emphasis": "i", "strong": "b", "strikethrough": "s", "sub": "sub", "sup": "sup", "code": "code"}.get(tag)
        if tag == "a":
            href = fb2_href(e)
            target = ("@@" + ids[href[1:]] + "#" + href[1:] + "@@") if href.startswith("#") and href[1:] in ids \
                else (href if re.match(r"^https?://", href) else "")
            if target:
                out.append(f'<a href="{html.escape(target, quote=True)}">')
                wrap = "/a"
        elif tag == "image":
            out.append(f'<img src="#{html.escape(fb2_href(e).lstrip("#"))}">')
        elif wrap:
            out.append(f"<{wrap}>")
        if e.get("id"):
            out.append(f'<span id="{html.escape(e.get("id"), quote=True)}"></span>')
        out.append(html.escape(e.text or "", quote=False))
        for c in e:
            out.append(inline(c))
            out.append(html.escape(c.tail or "", quote=False))
        if wrap == "/a":
            out.append("</a>")
        elif wrap:
            out.append(f"</{wrap}>")
        return "".join(out)

    def block(e, depth):
        tag = local(e.tag)
        ident = f' id="{html.escape(e.get("id"), quote=True)}"' if e.get("id") else ""
        if tag == "p" or tag == "v" or tag == "subtitle" or tag == "text-author":
            align = ' align="center"' if tag == "subtitle" else (' align="right"' if tag == "text-author" else "")
            return f"<p{ident}{align}>{inline(e)}</p>"
        if tag == "title":
            h = min(depth + 1, 6)
            return f"<h{h}{ident}>" + " ".join(inline(c) for c in e if local(c.tag) == "p") + f"</h{h}>"
        if tag == "empty-line":
            return "<br>"
        if tag == "image":
            return f'<p align="center"{ident}><img src="#{html.escape(fb2_href(e).lstrip("#"))}"></p>'
        if tag in ("epigraph", "cite", "annotation"):
            return f"<blockquote{ident}>" + "".join(block(c, depth) for c in e) + "</blockquote>"
        if tag in ("poem", "stanza"):
            return f"<div{ident}>" + "".join(block(c, depth) for c in e) + "</div>"
        if tag == "table":
            rows = "".join("<tr>" + "".join(f"<{local(c.tag)}>{inline(c)}</{local(c.tag)}>" for c in r) + "</tr>"
                           for r in e)
            return f"<table{ident}>{rows}</table>"
        if tag == "section":
            return f"<div{ident}>" + "".join(block(c, depth + 1) for c in e) + "</div>"
        return ""

    def img(src):
        data = binaries.get(src.lstrip("#"))
        if not data:
            return None
        try:
            return b.image(src, base64.b64decode(data))
        except ValueError:
            return None

    link = lambda href: href if href.startswith("@@") or re.match(r"^https?://", href) else ""
    bodies = [e for e in root if local(e.tag) == "body"]
    # Each top-level section is a chapter (doc name "sN"); a notes body is one "Notes" chapter.
    docs = []
    for bi, body in enumerate(bodies):
        notes = body.get("name") in ("notes", "comments")
        sections = [c for c in body if local(c.tag) == "section"]
        lead = "".join(block(c, 1) for c in body if local(c.tag) not in ("section",))
        if notes or not sections:
            docs.append((f"b{bi}", lead + "".join(block(s, 1) for s in sections), "Notes" if notes else ""))
            for s in body.iter():
                if s.get("id"):
                    ids[s.get("id")] = f"b{bi}"
            continue
        for si, s in enumerate(sections):
            name = f"b{bi}s{si}"
            for e in s.iter():
                if e.get("id"):
                    ids[e.get("id")] = name
            docs.append((name, None, s))
        if lead.strip():
            docs.insert(len(docs) - len(sections), (f"b{bi}lead", lead, ""))
    toc = []
    for name, text, extra in docs:
        if text is None:
            s = extra
            title = fb2_title(s)
            text = block(s, 1)
            if title:
                toc.append((1, title, name, ""))
                for sub in s:
                    if local(sub.tag) == "section":
                        st = fb2_title(sub)
                        if st and sub.get("id"):
                            toc.append((2, st, name, sub.get("id")))
            b.add(name, text, img, link)
        else:
            if extra == "Notes":
                toc.append((1, "Notes", name, ""))
            b.add(name, text, img, link)
    b.finish(meta, toc)


# ---- TXT and Markdown ----

HEADING_TXT = re.compile(r"^((?i:chapter|part|book|prologue|epilogue|act)\b.{0,60}|[IVXLC]{1,7}\.\s+[^a-z]{1,60})$")


def read_text(path):
    with open(path, "rb") as f:
        return decode(f.read()).replace("\r\n", "\n").replace("\r", "\n")


def txt_build(path, outdir, meta):
    b = Builder(outdir)
    paras = [p.strip() for p in re.split(r"\n\s*\n", read_text(path)) if p.strip()]
    doc, parts, n = None, [], 0

    def flush():
        if parts:
            b.add(f"t{n}", "".join(parts), lambda s: None, lambda h: "")

    for p in paras:
        if "\n" not in p and HEADING_TXT.match(p):
            flush()
            parts, n = [f"<h2>{html.escape(p)}</h2>"], n + 1
        else:
            lines = p.split("\n")
            # Short lines (a contents list, verse, an address) keep their breaks; wrapped prose is rejoined.
            sep = "<br>" if len(lines) > 1 and max(len(l) for l in lines) < 55 else " "
            parts.append("<p>" + sep.join(html.escape(l.strip()) for l in lines) + "</p>")
    flush()
    b.finish(meta, [])


def md_inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)[^)]*\)", r'<img src="\2" alt="\1">', s)
    s = re.sub(r"\[([^\]]+)\]\(([^)\s]+)[^)]*\)", r'<a href="\2">\1</a>', s)
    s = re.sub(r"(\*\*|__)(.+?)\1", r"<b>\2</b>", s)
    s = re.sub(r"(?<![\w*])([*_])(?!\s)(.+?)(?<!\s)\1(?![\w*])", r"<i>\2</i>", s)
    return s


def md_to_html(text):
    out, para, lst, quote, code = [], [], None, [], None

    def end_para():
        if para:
            out.append("<p>" + md_inline(" ".join(para)) + "</p>")
            para.clear()

    def end_list():
        nonlocal lst
        if lst:
            out.append(f"</{lst}>")
            lst = None

    def end_quote():
        if quote:
            out.append("<blockquote>" + md_to_html("\n".join(quote)) + "</blockquote>")
            quote.clear()

    for line in text.split("\n"):
        if code is not None:
            if line.strip().startswith("```"):
                out.append("<pre>" + html.escape("\n".join(code)) + "</pre>")
                code = None
            else:
                code.append(line)
            continue
        if line.strip().startswith("```"):
            end_para(); end_list(); end_quote()
            code = []
            continue
        if line.startswith(">"):
            end_para(); end_list()
            quote.append(line[1:].removeprefix(" "))
            continue
        end_quote()
        m = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", line)
        if m:
            end_para(); end_list()
            n = len(m.group(1))
            out.append(f"<h{n}>{md_inline(m.group(2))}</h{n}>")
            continue
        if re.match(r"^\s*([-*_])(\s*\1){2,}\s*$", line):
            end_para(); end_list()
            out.append("<hr>")
            continue
        m = re.match(r"^\s*([-*+]|\d+[.)])\s+(.*)$", line)
        if m:
            end_para()
            kind = "ol" if m.group(1)[0].isdigit() else "ul"
            if lst != kind:
                end_list()
                out.append(f"<{kind}>")
                lst = kind
            out.append(f"<li>{md_inline(m.group(2))}</li>")
            continue
        if not line.strip():
            end_para(); end_list()
            continue
        para.append(line.strip())
    end_para(); end_list(); end_quote()
    if code is not None:
        out.append("<pre>" + html.escape("\n".join(code)) + "</pre>")
    return "\n".join(out)


def md_build(path, outdir, meta):
    b = Builder(outdir)
    base = os.path.dirname(os.path.realpath(path))

    def img(src):
        if re.match(r"^[a-z]+:", src, re.I):
            return None
        p = os.path.normpath(os.path.join(base, unquote(src)))
        if not os.path.isfile(p):
            return None
        with open(p, "rb") as f:
            return b.image(p, f.read())

    def link(href):
        return href if re.match(r"^https?://", href, re.I) else ""

    # A new chapter at every # or ## heading outside code blocks.
    chunks, cur, fence = [], [], False
    for line in read_text(path).split("\n"):
        if line.strip().startswith("```"):
            fence = not fence
        if not fence and re.match(r"^#{1,2}\s", line) and any(l.strip() for l in cur):
            chunks.append(cur)
            cur = []
        cur.append(line)
    chunks.append(cur)
    for i, c in enumerate(chunks):
        b.add(f"m{i}", md_to_html("\n".join(c)), img, link)
    b.finish(meta, [])


# ---- Commands ----

def file_meta(path):
    """(meta, cover bytes) without converting the book."""
    f = fmt_of(path)
    name = re.sub(r"[_]+", " ", os.path.basename(path)[:-len(f)] if f else os.path.basename(path)).strip()
    if f == ".epub":
        meta, cover = epub_meta(path)
    elif f in (".mobi", ".azw3", ".azw"):
        meta, cover, _ = mobi_headers(path)
    elif f in (".fb2", ".fb2.zip"):
        meta, cover, _ = fb2_meta(fb2_root(path))
    elif f == ".txt":
        # Project Gutenberg texts start with "Title: ..." and "Author: ..." lines.
        with open(path, "rb") as fh:
            head = decode(fh.read(8192))
        t = re.search(r"^Title:[ \t]*(.+)$", head, re.M)
        a = re.search(r"^Author:[ \t]*(.+)$", head, re.M)
        meta, cover = {"title": t.group(1).strip() if t else "", "author": a.group(1).strip() if a else ""}, None
    else:
        meta, cover = {"title": "", "author": ""}, None
    meta["title"] = meta.get("title") or name
    return meta, cover


def scan(library, cache):
    library = os.path.expanduser(library)
    os.makedirs(cache, exist_ok=True)
    covers = os.path.join(cache, "covers")
    os.makedirs(covers, exist_ok=True)
    index_path = os.path.join(cache, "library.json")
    try:
        with open(index_path, encoding="utf-8") as f:
            index = json.load(f)
    except (OSError, ValueError):
        index = {}
    books, fresh = [], {}
    for dirpath, dirnames, files in os.walk(library, followlinks=True):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in files:
            if name.startswith(".") or not fmt_of(name):
                continue
            path = os.path.join(dirpath, name)
            try:
                st = stamp(path)
            except OSError:
                continue
            bid = book_id(path)
            entry = index.get(bid)
            if not entry or entry.get("stamp") != st:
                try:
                    meta, cover = file_meta(path)
                except Exception as e:    # a broken file still shows up, by its name
                    print(f"book.py: {path}: {e}", file=sys.stderr)
                    meta, cover = {"title": os.path.basename(path), "author": ""}, None
                cover_path = ""
                for old in os.listdir(covers):
                    if old.startswith(bid):
                        os.remove(os.path.join(covers, old))
                if cover and image_size(cover):
                    cover_path = os.path.join(covers, bid + image_ext(cover))
                    with open(cover_path, "wb") as f:
                        f.write(cover)
                entry = {"stamp": st, "title": meta["title"], "author": meta.get("author", ""), "cover": cover_path}
            fresh[bid] = entry
            books.append({"id": bid, "path": path, "format": fmt_of(name).lstrip(".").split(".")[0],
                          "title": entry["title"], "author": entry["author"], "cover": entry["cover"]})
    write_json(index_path, fresh)
    books.sort(key=lambda b: b["title"].lower())
    return books


def open_book(path, cache):
    if not os.path.isfile(path):
        raise BookError("File not found: " + path)
    outdir = os.path.join(cache, book_id(path))
    st = stamp(path)
    try:
        with open(os.path.join(outdir, "book.json"), encoding="utf-8") as f:
            if json.load(f).get("stamp") == st:
                return outdir
    except (OSError, ValueError):
        pass
    # Built in a temp dir and swapped in, so a failed conversion never leaves half a book.
    os.makedirs(cache, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=".build-", dir=cache)
    try:
        f = fmt_of(path)
        meta, _ = file_meta(path)
        if f == ".epub":
            epub_build(path, tmp)
        elif f in (".mobi", ".azw3", ".azw"):
            mobi_build(path, tmp)
        elif f in (".fb2", ".fb2.zip"):
            fb2_build(path, tmp)
        elif f == ".txt":
            txt_build(path, tmp, meta)
        elif f in (".md", ".markdown"):
            md_build(path, tmp, meta)
        else:
            raise BookError("Unsupported format.")
        bj = os.path.join(tmp, "book.json")
        with open(bj, encoding="utf-8") as fh:
            data = json.load(fh)
        data["title"] = data.get("title") or meta["title"]
        data["author"] = data.get("author") or meta.get("author", "")
        data["stamp"] = st
        # Image URLs were written for the temp dir.
        for name in os.listdir(tmp):
            if name.endswith(".html"):
                p = os.path.join(tmp, name)
                with open(p, encoding="utf-8") as fh:
                    text = fh.read()
                with open(p, "w", encoding="utf-8") as fh:
                    fh.write(text.replace("file://" + tmp + "/", "file://" + outdir + "/"))
        write_json(bj, data)
        shutil.rmtree(outdir, ignore_errors=True)
        os.replace(tmp, outdir)
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    return outdir


def main(argv):
    if len(argv) != 4 or argv[1] not in ("scan", "open"):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        if argv[1] == "scan":
            print(json.dumps({"books": scan(argv[2], argv[3])}, ensure_ascii=False))
        else:
            print(json.dumps({"dir": open_book(argv[2], argv[3])}, ensure_ascii=False))
    except BookError as e:
        print(json.dumps({"error": str(e)}))
    except Exception as e:
        print(f"book.py: {type(e).__name__}: {e}", file=sys.stderr)
        print(json.dumps({"error": f"Couldn't read this book ({type(e).__name__}: {e})."}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
