// The open chapter: one read-only TextEdit in a Flickable. In pages mode the Flickable doesn't move by itself:
// contentY jumps to the top of the page and a curtain hides the line the page's bottom edge would cut.
import QtQuick

Item {
    id: v
    required property var reader
    readonly property var core: reader.core
    readonly property bool paged: reader.layout === "pages"
    readonly property int fs: reader.fontSize

    // ---- Pagination ----
    property var starts: [0]            // y of each page's first line
    property int page: 0
    readonly property int pageCount: starts.length
    readonly property real pageEnd: page + 1 < starts.length ? starts[page + 1] : te.height
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
    // Images keep their aspect ratio and fit inside the column and the page.
    function fitImages(html) {
        const maxW = te.width, maxH = Math.max(80, flick.height - 8);
        return html.replace(/<img src="([^"]*)" width="(\d+)" height="(\d+)"/g, (m, src, w, h) => {
            const s = Math.min(1, maxW / w, maxH / h);
            return `<img src="${src}" width="${Math.floor(w * s)}" height="${Math.floor(h * s)}"`;
        });
    }
    readonly property string html: reader.chapterHtml
        ? "<html><head>" + style + "</head><body>" + fitImages(reader.chapterHtml) + "</body></html>" : ""

    // ---- Laying out and placing the position ----
    // Every relayout (new chapter, size, font) recomputes the pages, then puts reader.pos (or the pending anchor,
    // or the chapter's end) back at the top.
    function relayout() {
        if (!reader.chapterHtml || te.text === "" || flick.height < 40) return;
        if (paged) paginate();
        const plain = te.getText(0, te.length);
        const marks = [];
        for (let at = plain.indexOf("\u2060"); at >= 0; at = plain.indexOf("\u2060", at + 1)) marks.push(at);
        reader.marks = marks;
        if (reader.anchor >= 0) {
            const at = marks[reader.anchor] ?? 0;
            reader.anchor = -1;
            show(at, true);
        } else if (reader.atEnd) {
            reader.atEnd = false;
            if (paged) setPage(starts.length - 1);
            else { flick.contentY = Math.max(0, te.height - flick.height); scrolled(); }
        } else {
            show(reader.pos, false);
        }
    }
    // Shows the page (or scroll offset) holding character `p`; `report` saves it as the new position.
    function show(p, report) {
        const y = te.positionToRectangle(Math.min(p, te.length)).y;
        if (paged) {
            let i = 0;
            while (i + 1 < starts.length && starts[i + 1] <= y + 1) i++;
            page = i;
            flick.contentY = starts[i];
            reader.probe = te.positionAt(1, starts[i] + flick.height / 2);
            if (report) reader.report(p, te.length ? p / te.length : 0, te.positionAt(1, starts[i] + flick.height / 2));
        } else {
            flick.contentY = Math.max(0, Math.min(y, te.height - flick.height));
            reader.probe = te.positionAt(1, flick.contentY + flick.height / 2);
            if (report) scrolled();
        }
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
        flick.contentY = starts[page];
        const p = te.positionAt(1, starts[page] + 1);
        reader.report(p, te.length ? p / te.length : 0, te.positionAt(1, starts[page] + flick.height / 2));
    }
    function scrolled() {
        const p = te.positionAt(1, flick.contentY + 1);
        reader.report(p, te.height > flick.height ? Math.min(1, flick.contentY / (te.height - flick.height)) : 1,
                      te.positionAt(1, flick.contentY + flick.height / 2));
    }

    function next() {
        if (paged) {
            if (page + 1 < starts.length) setPage(page + 1);
            else reader.nextChapter();
        } else if (flick.contentY + flick.height >= te.height - 2) {
            reader.nextChapter();
        } else {
            flick.contentY = Math.min(te.height - flick.height, flick.contentY + flick.height - lineStep());
            scrolled();
        }
    }
    function prev() {
        if (paged) {
            if (page > 0) setPage(page - 1);
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

    // ---- The text ----
    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        interactive: !v.paged
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: te.height + (v.paged ? height : 0)
        onHeightChanged: Qt.callLater(v.relayout)
        onMovementEnded: if (!v.paged) v.scrolled()

        TextEdit {
            id: te
            x: Math.max(0, (flick.width - width) / 2)
            width: Math.min(v.reader.columnWidth, flick.width)
            readOnly: true
            selectByMouse: false
            activeFocusOnPress: false
            textFormat: TextEdit.RichText
            wrapMode: TextEdit.Wrap
            color: v.core.fg
            font.family: v.reader.bookFont
            font.pixelSize: v.fs
            text: v.html
            onTextChanged: Qt.callLater(v.relayout)
            onHeightChanged: Qt.callLater(v.relayout)
            onWidthChanged: Qt.callLater(v.relayout)
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
        y: v.pageEnd - v.starts[v.page]
        width: parent.width
        height: Math.max(0, parent.height - y)
        color: v.core.bg
    }

    // ---- Mouse: links, page turns (click a side third, or the wheel) ----
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        property real wheelSum: 0
        function linkAt(x, y) {
            const p = mapToItem(te, x, y);
            return p.y >= 0 && (!v.paged || p.y < v.pageEnd) ? te.linkAt(p.x, p.y) : "";
        }
        onPositionChanged: mouse => cursorShape = linkAt(mouse.x, mouse.y) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouse => {
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
