// The open chapter: one read-only TextEdit in a Flickable. In pages mode the Flickable doesn't move by itself:
// contentY jumps to the top of the page and a curtain hides the line the page's bottom edge would cut.
// Two pages side by side add a second TextEdit with the same text and width, showing the next page.
import QtQuick

Item {
    id: v
    required property var reader
    readonly property var core: reader.core
    readonly property bool paged: reader.layout === "pages"
    readonly property int fs: reader.fontSize

    // ---- Page layout: one column (at most `width`), the whole width, or two pages (pages mode only) ----
    // Full width keeps a margin as wide as the gap between two pages, so the lines don't run to the window's edge.
    readonly property bool spread: paged && reader.pageLayout === "two"
    readonly property int gap: 56
    readonly property real colWidth: reader.pageLayout === "full" ? width - 2 * gap
        : spread ? Math.min(reader.columnWidth, (width - gap) / 2) : Math.min(reader.columnWidth, width)

    // ---- Pagination ----
    property var starts: [0]            // y of each page's first line
    property int page: 0                // the page shown (with two pages: the left one, always even)
    readonly property int pageCount: starts.length
    readonly property int step: spread ? 2 : 1
    readonly property bool hasRight: spread && page + 1 < starts.length
    function endOf(i) { return i + 1 < starts.length ? starts[i + 1] : te.height }
    readonly property real pageEnd: endOf(page)
    readonly property real frac: te.length ? reader.pos / te.length : 0

    // ---- Rich text: the chapter with a stylesheet made from the theme and the reader settings ----
    function css(c) { return `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${c.a.toFixed(2)})` }
    readonly property string style: `<style>
        p, div, li, blockquote, dd, dt, td, th { line-height: ${reader.lineHeight}%; }
        p { margin-top: 0; margin-bottom: ${Math.round(fs * 0.7)}px; ${reader.justify ? "text-align: justify;" : ""} }
        h1, h2, h3, h4, h5, h6 { color: ${css(core.accent)}; margin-top: ${Math.round(fs * 1.2)}px; margin-bottom: ${Math.round(fs * 0.7)}px; }
        h1 { font-size: ${Math.round(fs * 1.6)}px; } h2 { font-size: ${Math.round(fs * 1.4)}px; }
        h3 { font-size: ${Math.round(fs * 1.2)}px; } h4, h5, h6 { font-size: ${Math.round(fs * 1.05)}px; }
        a { color: ${css(core.accent)}; text-decoration: none; }
        blockquote { color: ${css(core.dim)}; margin-left: ${Math.round(fs * 1.5)}px; margin-right: ${Math.round(fs * 1.5)}px; }
        pre, code { font-family: "${core.font}"; font-size: ${Math.round(fs * 0.85)}px; }
        hr { color: ${css(Qt.alpha(core.accent, 0.35))}; }
        td, th { padding: 4px; }
        </style>`
    // Images keep their aspect ratio and fit inside the column and the page. Only chapters with images depend
    // on the size, and only on the settled one: re-parsing a whole chapter on every step of a resize is slow.
    function fitImages(html) {
        const maxW = fitW || te.width, maxH = Math.max(80, (fitH || flick.height) - 8);
        return html.replace(/<img src="([^"]*)" width="(\d+)" height="(\d+)"/g, (m, src, w, h) => {
            const s = Math.min(1, maxW / w, maxH / h);
            return `<img src="${src}" width="${Math.floor(w * s)}" height="${Math.floor(h * s)}"`;
        });
    }
    readonly property string html: reader.chapterHtml
        ? "<html><head>" + style + "</head><body>"
          + (reader.chapterHtml.includes("<img") ? fitImages(reader.chapterHtml) : reader.chapterHtml) + "</body></html>" : ""

    // ---- Resizing: pages are counted again (and images fitted) once the size stops changing ----
    property real fitW: 0
    property real fitH: 0
    Timer {
        id: settle
        interval: 150
        onTriggered: {
            v.fitW = te.width;
            v.fitH = flick.height;
            v.relayout();
        }
    }

    // ---- Laying out and placing the position ----
    // Every relayout (new chapter, size, font) recomputes the pages, then puts reader.pos (or the pending anchor,
    // or the chapter's end) back at the top.
    function relayout() {
        if (!reader.chapterHtml || te.text === "" || flick.height < 40) return;
        if (paged) paginate();
        const plain = te.getText(0, te.length);
        v.plain = plain;
        markHighlights();
        const marks = [];
        for (let at = plain.indexOf("\u2060"); at >= 0; at = plain.indexOf("\u2060", at + 1)) marks.push(at);
        reader.marks = marks;
        if (reader.find) {
            const m = match(plain, reader.find);
            reader.find = null;
            show(m ? m.index : reader.pos, true);
            if (m) {
                te.select(m.index, m.index + m[0].length);
                right.item?.text.select(m.index, m.index + m[0].length);
            }
        } else if (reader.anchor >= 0) {
            const at = marks[reader.anchor] ?? 0;
            reader.anchor = -1;
            show(at, true);
        } else if (reader.atEnd) {
            reader.atEnd = false;
            if (paged) setPage(starts.length - 1);
            else { flick.contentY = Math.max(0, te.height - flick.height); scrolled(); }
        } else {
            show(reader.pos, true);
        }
    }
    // The n-th match of a search in the chapter's text (or the last one, if book.py counted more). The words may
    // be split by any whitespace or anchor marker, like in book.py's copy of the text, which has no markers.
    function pattern(query) {
        const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const words = query.split(/\s+/).filter(w => w);
        return new RegExp(words.map(w => [...w].map(esc).join("\u2060?")).join("[\\s\u2060\ufffc]+"), "gi");
    }
    function match(plain, find) {
        const re = pattern(find.query);
        let m, last = null;
        for (let i = 0; i <= find.n && (m = re.exec(plain)); i++) last = m;
        return last;
    }
    // Shows the page (or scroll offset) holding character `p`; `report` saves it as the new position.
    function show(p, report) {
        const y = te.positionToRectangle(Math.min(p, te.length)).y;
        if (paged) {
            let i = 0;
            while (i + 1 < starts.length && starts[i + 1] <= y + 1) i++;
            page = i - i % step;
            flick.contentY = starts[page];      // the left page (with two pages, `i` may be the right one)
            reader.probe = seen();
            if (report) reader.report(p, te.length ? p / te.length : 0, reader.probe);
        } else {
            flick.contentY = Math.max(0, Math.min(y, te.height - flick.height));
            reader.probe = seen();
            if (report) scrolled();
        }
    }
    // After every move: the last character on screen (which bookmark is on this page), and the one in the middle.
    function seen() {
        const top = flick.contentY, bottom = paged ? endOf(hasRight ? page + 1 : page) : top + flick.height;
        reader.posEnd = te.positionAt(te.width - 1, Math.min(te.height, bottom) - 1);
        return te.positionAt(1, top + Math.min(bottom - top, flick.height) / 2);
    }
    // The start of the first line shown, cut at a word, for a bookmark's label.
    function snippet() {
        const t = te.getText(reader.pos, Math.min(te.length, reader.pos + 200)).replace(/[\u2060\ufffc]/g, "").replace(/\s+/g, " ").trim();
        return t.length <= 100 ? t : t.slice(0, 100).replace(/\s+\S*$/, "") + "…";
    }

    // ---- Highlights ----
    // Drawn as rectangles under the text (from positionToRectangle), not by wrapping the passage in a
    // background-coloured <span>: changing the HTML re-parses and lays out the whole chapter for every new
    // highlight, and a place in the plain text can't be found in the HTML without parsing it a second time.
    // The rectangles are worked out on relayout and when a highlight changes, never on a page turn.
    property string plain: ""           // the chapter's text, as of the last relayout
    property var ranges: []             // { i, start, end }: the chapter's highlights found in the text
    property var boxes: []              // { x, y, w, h, note }: one per line of each, in the text's coordinates
    function markHighlights() {
        const found = [], out = [];
        reader.highlights.forEach((h, i) => {
            if (h.chapter !== reader.chapter) return;
            const m = match(plain, { query: h.text, n: h.n });
            if (!m) return;
            found.push({ i: i, start: m.index, end: m.index + m[0].length });
            out.push(...lineBoxes(m.index, m.index + m[0].length, !!h.note));
        });
        ranges = found;
        boxes = out;
    }
    // The cursor rectangles of every position from a to b, grouped by line: a line runs from its leftmost to its
    // rightmost cursor (so a justified line is covered to its last word).
    function lineBoxes(a, b, note) {
        const out = [];
        let line = null;
        for (let p = a; p <= b; p++) {
            const r = te.positionToRectangle(p);
            if (!line || Math.abs(r.y - line.y) > 1) {
                if (line && line.w > 1) out.push(line);
                line = { x: r.x, y: r.y, w: 0, h: r.height, note: note };
            }
            const right = Math.max(line.x + line.w, r.x);
            line.x = Math.min(line.x, r.x);
            line.w = right - line.x;
        }
        if (line && line.w > 1) out.push(line);
        return out;
    }
    Connections {
        target: v.reader
        function onHighlightsEdited() { v.markHighlights() }
    }

    // ---- Selection (dragging the mouse), the same on both pages ----
    // The TextEdits don't select by themselves: the MouseArea on top takes every press for links and page turns,
    // so it does the dragging too. The ends snap to whole words.
    function select(a, b) {
        let s = Math.min(a, b), e = Math.max(a, b);
        const word = /[^\s\u2060\ufffc.,;:!?"“”‘()\[\]{}…—–-]/;
        while (s > 0 && word.test(plain[s - 1])) s--;
        while (e < plain.length && word.test(plain[e])) e++;
        te.select(s, e);
        right.item?.text.select(s, e);
    }
    function deselect() {
        te.deselect();
        right.item?.text.deselect();
    }
    readonly property bool hasSelection: te.selectionEnd > te.selectionStart
    // { text, n, pos, start, end }: the selected text (whitespace made single spaces), and which of its matches in the
    // chapter it is (the one starting nearest the selection), or null.
    function selection() {
        if (!hasSelection) return null;
        const start = te.selectionStart, end = te.selectionEnd;
        const text = te.selectedText.replace(/\u2060/g, "").replace(/[\s\ufffc]+/g, " ").trim();
        if (!text) return null;
        const re = pattern(text);
        let m, n = 0, best = Infinity;
        for (let i = 0; (m = re.exec(plain)); i++) {
            if (Math.abs(m.index - start) < best) { best = Math.abs(m.index - start); n = i; }
            if (m.index > end) break;
        }
        return { text: text, n: n, pos: start, start: start, end: end };
    }
    // The highlight overlapping [start, end), -1 if none.
    function highlightAt(start, end) { return ranges.find(x => x.start < end && x.end > start)?.i ?? -1 }
    // H: keeps the selection as a highlight. False when nothing is selected (then H turns the page back).
    function highlight() {
        const sel = selection();
        if (!sel) return false;
        if (sel.text.length > 2000) reader.say("That's too long for a highlight (2000 characters at most).");
        else if (highlightAt(sel.start, sel.end) >= 0) reader.say("Already highlighted: N edits its note, Shift+H lists them.");
        else { reader.addHighlight(sel); deselect(); }
        return true;
    }
    // N: the note of the highlight under the selection (made first if there's none). False when nothing is selected.
    function note() {
        const sel = selection();
        if (!sel) return false;
        let i = highlightAt(sel.start, sel.end);
        if (i < 0) {
            if (sel.text.length > 2000) { reader.say("That's too long for a highlight (2000 characters at most)."); return true; }
            i = reader.addHighlight(sel);
        }
        deselect();
        reader.editNote(i, true);
        return true;
    }

    // The next page starts at the top of the line the bottom edge cuts; a line (or image) taller than the page
    // is cut where the page ends.
    function paginate() {
        const H = flick.height, total = te.height;
        const out = [0];
        let y = 0;
        while (y + H < total && out.length < 10000) {
            const bottom = y + H;
            const r = te.positionToRectangle(te.positionAt(1, bottom));
            let next = r.y < bottom && r.y + r.height > bottom ? r.y : bottom;
            if (next <= y + 1) next = bottom;
            out.push(next);
            y = next;
        }
        starts = out;
    }
    function setPage(i) {
        page = Math.max(0, Math.min(starts.length - 1, i));
        page -= page % step;
        flick.contentY = starts[page];
        const p = te.positionAt(1, starts[page] + 1);
        reader.report(p, te.length ? p / te.length : 0, seen());
    }
    function scrolled() {
        const p = te.positionAt(1, flick.contentY + 1);
        reader.report(p, te.height > flick.height ? Math.min(1, flick.contentY / (te.height - flick.height)) : 1, seen());
    }

    function next() {
        deselect();
        if (paged) {
            if (page + step < starts.length) setPage(page + step);
            else reader.nextChapter();
        } else if (flick.contentY + flick.height >= te.height - 2) {
            reader.nextChapter();
        } else {
            flick.contentY = Math.min(te.height - flick.height, flick.contentY + flick.height - lineStep());
            scrolled();
        }
    }
    function prev() {
        deselect();
        if (paged) {
            if (page > 0) setPage(page - step);
            else reader.prevChapter();
        } else if (flick.contentY <= 0) {
            reader.prevChapter();
        } else {
            flick.contentY = Math.max(0, flick.contentY - flick.height + lineStep());
            scrolled();
        }
    }
    // Arrow keys in scroll mode: about two lines.
    function lineStep() { return Math.round(fs * reader.lineHeight / 100) * 2 }
    function scrollBy(dy) {
        if (paged) return dy > 0 ? next() : prev();
        flick.contentY = Math.max(0, Math.min(Math.max(0, te.height - flick.height), flick.contentY + dy));
        scrolled();
    }

    Connections {
        target: v.reader
        function onJumped() { Qt.callLater(v.relayout) }
    }
    onPagedChanged: Qt.callLater(relayout)
    onSpreadChanged: Qt.callLater(relayout)     // the left page must be an even one

    // The highlights, under the text; a line with a note is underlined.
    component Boxes: Repeater {
        model: v.boxes
        Rectangle {
            required property var modelData
            z: -1
            x: modelData.x - 1
            y: modelData.y
            width: modelData.w + 2
            height: modelData.h
            radius: 3
            color: Qt.alpha(v.core.accent, 0.25)
            Rectangle {
                visible: parent.modelData.note
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 2
                color: Qt.alpha(v.core.accent, 0.7)
            }
        }
    }

    component PageText: TextEdit {
        readOnly: true
        selectByMouse: false
        activeFocusOnPress: false
        textFormat: TextEdit.RichText
        wrapMode: TextEdit.Wrap
        color: v.core.fg
        selectionColor: Qt.alpha(v.core.accent, 0.35)       // a search match, or text being selected
        selectedTextColor: v.core.fg
        font.family: v.reader.bookFont
        font.pixelSize: v.fs
        text: v.html
    }

    // ---- The text ----
    Flickable {
        id: flick
        x: Math.max(0, (v.width - (v.spread ? 2 * width + v.gap : width)) / 2)
        width: v.colWidth
        height: parent.height
        clip: true
        interactive: !v.paged
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: te.height + (v.paged ? height : 0)
        onHeightChanged: settle.restart()
        onMovementEnded: if (!v.paged) v.scrolled()

        Boxes {}
        PageText {
            id: te
            width: flick.width
            onTextChanged: Qt.callLater(v.relayout)
            onHeightChanged: settle.restart()
            onWidthChanged: settle.restart()
        }

        // Scroll mode: at the end of the chapter, the way on.
        Text {
            visible: !v.paged && v.reader.book && v.reader.chapter < v.reader.book.chapters.length - 1
            y: te.height + 8
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Next chapter  \u{F0142}"
            color: v.core.accent
            font.family: v.core.font
            font.pixelSize: 12
        }
    }
    // Hides what's below the page's last whole line.
    Rectangle {
        visible: v.paged
        x: flick.x
        y: v.pageEnd - v.starts[v.page]
        width: flick.width
        height: Math.max(0, parent.height - y)
        color: v.core.bg
    }

    // The right page: laid out like the left one (same text, width and font), so `starts` fits it too.
    Loader {
        id: right
        active: v.spread
        x: flick.x + flick.width + v.gap
        width: flick.width
        height: parent.height
        sourceComponent: Item {
            readonly property alias text: te2
            Flickable {
                anchors.fill: parent
                visible: v.hasRight
                clip: true
                interactive: false
                contentWidth: width
                contentHeight: te2.height + height
                contentY: v.hasRight ? v.starts[v.page + 1] : 0
                Boxes {}
                PageText {
                    id: te2
                    width: parent.width
                }
            }
            Rectangle {
                visible: v.hasRight
                y: v.hasRight ? v.endOf(v.page + 1) - v.starts[v.page + 1] : 0
                width: parent.width
                height: Math.max(0, parent.height - y)
                color: v.core.bg
            }
        }
    }

    // ---- Mouse: links, page turns (click a side third, or the wheel), selecting (drag) ----
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        property real wheelSum: 0
        property point pressedAt
        property int from: -1           // the character the drag started on
        property bool dragging: false
        // The character under the mouse: on the left page (or the scrolled column), else on the right one, kept
        // inside the page's lines so a drag past its edge stops at its first or last line.
        function charAt(x, y) {
            const p = mapToItem(te, x, y);
            const left = !v.hasRight || p.x < te.width + v.gap / 2;
            const t = left ? te : right.item.text, i = left ? v.page : v.page + 1;
            const q = left ? p : mapToItem(t, x, y);
            const ty = v.paged ? Math.max(v.starts[i], Math.min(v.endOf(i) - 1, q.y)) : q.y;
            return t.positionAt(Math.max(0, Math.min(t.width - 1, q.x)), ty);
        }
        onPressed: mouse => {
            pressedAt = Qt.point(mouse.x, mouse.y);
            dragging = false;
            from = charAt(mouse.x, mouse.y);
        }
        // The link under the mouse on the left page (or the scrolled column), else on the right page.
        function linkAt(x, y) {
            for (const [t, i] of [[te, v.page], [right.item?.text, v.page + 1]]) {
                if (!t || (t !== te && !v.hasRight)) continue;
                const p = mapToItem(t, x, y);
                if (p.x >= 0 && p.x < t.width && (!v.paged || (p.y >= v.starts[i] && p.y < v.endOf(i)))) return t.linkAt(p.x, p.y);
            }
            return "";
        }
        onPositionChanged: mouse => {
            if (pressed) {
                if (!dragging && Math.hypot(mouse.x - pressedAt.x, mouse.y - pressedAt.y) > 6) dragging = true;
                if (dragging) v.select(from, charAt(mouse.x, mouse.y));
                return;
            }
            cursorShape = linkAt(mouse.x, mouse.y) ? Qt.PointingHandCursor : Qt.ArrowCursor;
        }
        onClicked: mouse => {
            if (dragging) return;
            // A click with text selected only lets go of it.
            if (v.hasSelection) return v.deselect();
            const link = linkAt(mouse.x, mouse.y);
            if (link) return v.reader.follow(link);
            if (!v.paged) {
                if (mouse.y > te.height - flick.contentY) v.reader.nextChapter();
                return;
            }
            if (mouse.x < width / 3) v.prev();
            else if (mouse.x > width * 2 / 3) v.next();
        }
        onWheel: wheel => {
            if (!v.paged) {
                v.scrollBy(-wheel.angleDelta.y / 120 * v.lineStep() * 1.5);
                return;
            }
            // One page per notch; touchpads send many small deltas, so they're summed first.
            wheelSum += wheel.angleDelta.y;
            if (Math.abs(wheelSum) >= 120) {
                wheelSum > 0 ? v.prev() : v.next();
                wheelSum = 0;
            }
        }
    }
}
