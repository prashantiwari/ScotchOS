// dailyTheory window: signup, the current theory with its sources, history and interests. Created only while
// open; the state and the API calls live in DailyTheory.qml (`client`).
import QtQuick
import Quickshell
import "../../settings"

FloatingWindow {
    id: win
    required property var client
    readonly property var core: client.core

    // A fixed size makes Hyprland float the window, like the settings window.
    implicitWidth: 860
    implicitHeight: 580
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)
    title: "Daily theory"
    color: core.bg
    onClosed: client.open = false
    Component.onCompleted: client.refresh()

    // ---- Time ----
    // Minute steps are enough for "resets in 3 h 20 min"; the timer only runs while the quota is used up.
    property double now: Date.now()
    // Refreshes asked for since the reset time passed. Each one doubles the wait (30 s … 8 min), so a server whose
    // reset runs late isn't asked twice every 30 s.
    property int resetTries: 0
    Connections {
        target: win.client
        function onOutOfQuotaChanged() { win.now = Date.now(); win.resetTries = 0; }
    }
    Timer {
        interval: 30000 * Math.pow(2, Math.min(win.resetTries, 4))
        repeat: true
        running: win.client.outOfQuota
        onTriggered: {
            win.now = Date.now();
            if (win.now >= Date.parse(win.client.quota.resets_at)) { win.resetTries++; win.client.refresh(); }
        }
    }
    function clock(iso) { return Qt.formatDateTime(new Date(iso), "HH:mm") }
    function day(iso) { return Qt.formatDateTime(new Date(iso), "d MMM, HH:mm") }
    function until(iso) {
        const m = Math.max(0, Math.ceil((Date.parse(iso) - now) / 60000));
        return m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min";
    }

    // ---- Links ----
    // The site a search link goes to, from its host ("scholar.google.com" → "Google Scholar"); "" without a link.
    function site(url) {
        const m = String(url ?? "").match(/^https?:\/\/(?:www\.)?([^\/?#:]+)/i);
        const host = m ? m[1].toLowerCase() : "";
        return ({ "scholar.google.com": "Google Scholar", "openlibrary.org": "Open Library" })[host]
               ?? (host.endsWith("wikipedia.org") ? "Wikipedia" : host);
    }

    // ---- Small parts ----
    component Label: Text {
        color: win.core.accent
        font.family: win.core.font
        font.pixelSize: 11
        font.letterSpacing: 1
    }
    // Plain text, so server or model text with a "<" can't be read as rich text; "\n\n" still breaks paragraphs.
    component Body: Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: win.core.fg
        font.family: win.core.font
        font.pixelSize: 12
    }
    component Btn: Rectangle {
        id: b
        property string label
        property bool primary: false
        signal clicked()
        width: btnText.implicitWidth + 28
        height: 32
        radius: 10
        opacity: enabled ? 1 : 0.45
        color: primary ? (area.containsMouse && enabled ? Qt.alpha(win.core.accent, 0.85) : win.core.accent)
                       : (area.containsMouse && enabled ? Qt.alpha(win.core.fg, 0.12) : Qt.alpha(win.core.fg, 0.06))
        border.width: primary ? 0 : 1
        border.color: Qt.alpha(win.core.accent, 0.35)
        Text {
            id: btnText
            anchors.centerIn: parent
            text: b.label
            color: b.primary ? win.core.bg : win.core.fg
            font.family: win.core.font
            font.pixelSize: 12
            font.bold: b.primary
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: b.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (b.enabled) b.clicked()
        }
    }
    component Chip: Rectangle {
        id: c
        property string label
        property bool clickable: false
        signal clicked()
        width: chipText.implicitWidth + 18
        height: 24
        radius: 12
        color: chipArea.containsMouse ? Qt.alpha(win.core.accent, 0.25) : Qt.alpha(win.core.accent, 0.12)
        Text {
            id: chipText
            anchors.centerIn: parent
            text: c.label
            color: win.core.fg
            font.family: win.core.font
            font.pixelSize: 11
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            enabled: c.clickable
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: c.clicked()
        }
    }
    // A source or reading item. Its url is a search link the server built from the citation: it always opens, but
    // may land on search results, so the right side names the site it searches rather than claiming a match.
    component LinkRow: Item {
        id: lr
        property string text
        property string url
        property string hint: win.site(url)
        width: parent.width
        height: linkText.implicitHeight
        Text {
            id: linkText
            anchors.left: parent.left
            anchors.right: hintText.left
            anchors.rightMargin: 12
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: lr.text
            color: linkArea.containsMouse ? win.core.accent : win.core.fg
            font.family: win.core.font
            font.pixelSize: 12
        }
        Text {
            id: hintText
            anchors.right: parent.right
            anchors.baseline: linkText.baseline
            text: lr.hint ? "\u{F0349} " + lr.hint : ""
            color: linkArea.containsMouse ? win.core.accent : win.core.dim
            font.family: win.core.font
            font.pixelSize: 10
        }
        MouseArea {
            id: linkArea
            anchors.fill: parent
            enabled: lr.url !== ""
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: win.client.openLink(lr.url)
        }
    }
    // Multi-line text box for the interests (3-1000 characters).
    component InterestsBox: Rectangle {
        property alias text: edit.text
        width: parent.width
        height: 96
        radius: 12
        color: Qt.alpha(win.core.fg, 0.06)
        border.width: 1
        border.color: edit.activeFocus ? win.core.accent : Qt.alpha(win.core.accent, 0.35)
        Flickable {
            id: scroll
            anchors.fill: parent
            anchors.margins: 10
            contentHeight: edit.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            TextEdit {
                id: edit
                width: scroll.width
                wrapMode: TextEdit.Wrap
                color: win.core.fg
                selectionColor: win.core.accentDim
                font.family: win.core.font
                font.pixelSize: 12
                onCursorRectangleChanged: {
                    if (cursorRectangle.y < scroll.contentY) scroll.contentY = cursorRectangle.y;
                    else if (cursorRectangle.y + cursorRectangle.height > scroll.contentY + scroll.height)
                        scroll.contentY = cursorRectangle.y + cursorRectangle.height - scroll.height;
                }
            }
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8
            text: edit.text.trim().length + " / 1000"
            color: edit.text.trim().length > 1000 ? win.core.accent : win.core.dim
            font.family: win.core.font
            font.pixelSize: 10
        }
    }
    // Catalog subtopics as chips; a click appends one to the interests text (the server only takes text).
    component Suggestions: Flow {
        id: sug
        required property var box
        width: parent.width
        spacing: 6
        Repeater {
            model: win.client.topics.reduce((all, t) => all.concat(t.subtopics ?? []), [])
            Chip {
                required property string modelData
                label: "+ " + modelData
                clickable: true
                onClicked: {
                    const cur = sug.box.text.trim();
                    sug.box.text = cur ? cur.replace(/[,;.\s]*$/, "") + ", " + modelData : modelData;
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.client.open = false

        // ---- Sidebar: pages, quota, server ----
        Rectangle {
            id: sidebar
            width: 230
            height: parent.height
            color: Qt.alpha(win.core.fg, 0.04)

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6

                Text {
                    text: "\u{F0335}  DAILY THEORY"
                    color: win.core.accent
                    font.family: win.core.font
                    font.pixelSize: 14
                    font.bold: true
                    bottomPadding: 10
                }

                Repeater {
                    model: win.client.signedIn ? [
                        { key: "theory", name: "Theory", icon: "\u{F0335}" },
                        { key: "history", name: "History", icon: "\u{F02DA}" },
                        { key: "profile", name: "Interests", icon: "\u{F0004}" },
                    ] : [{ key: "theory", name: "Sign up", icon: "\u{F0013}" }]

                    Rectangle {
                        id: page
                        required property var modelData
                        readonly property bool current: modelData.key === win.client.view
                        width: parent.width
                        height: 40
                        radius: 12
                        color: current ? Qt.alpha(win.core.accent, 0.18) : (pageArea.containsMouse ? Qt.alpha(win.core.fg, 0.06) : "transparent")
                        border.width: current ? 1 : 0
                        border.color: Qt.alpha(win.core.accent, 0.35)
                        MouseArea {
                            id: pageArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { win.client.view = page.modelData.key; win.client.error = null; }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.modelData.icon + "  " + page.modelData.name
                            color: page.current ? win.core.fg : win.core.dim
                            font.family: win.core.font
                            font.pixelSize: 13
                        }
                    }
                }
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                spacing: 6

                Column {
                    visible: !!win.client.quota
                    width: parent.width
                    spacing: 6
                    Label { text: "TODAY" }
                    Text {
                        text: win.client.quota ? win.client.quota.used + " / " + win.client.quota.limit : ""
                        color: win.core.fg
                        font.family: win.core.font
                        font.pixelSize: 18
                        font.bold: true
                    }
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.alpha(win.core.fg, 0.1)
                        Rectangle {
                            height: parent.height
                            radius: 2
                            color: win.core.accent
                            width: win.client.quota ? parent.width * Math.min(1, win.client.quota.used / Math.max(1, win.client.quota.limit)) : 0
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: !win.client.quota ? "" : "resets at " + win.clock(win.client.quota.resets_at)
                              + (win.client.outOfQuota ? " (in " + win.until(win.client.quota.resets_at) + ")" : "")
                        color: win.core.dim
                        font.family: win.core.font
                        font.pixelSize: 10
                    }
                }
                Text {
                    width: parent.width
                    topPadding: 8
                    text: win.client.server.replace(/^https?:\/\//, "")
                          + (win.client.insecure ? "\nnot encrypted (http)" : "") + "\nEsc closes."
                    elide: Text.ElideRight
                    color: win.client.insecure ? "#f0b429" : win.core.dim
                    font.family: win.core.font
                    font.pixelSize: 10
                }
            }
        }

        // ---- Main pane: error banner over the current page ----
        Column {
            id: main
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 24
            spacing: 14

            Rectangle {
                visible: !!win.client.error
                width: parent.width
                height: errRow.implicitHeight + 20
                radius: 12
                color: Qt.alpha(win.core.accent, 0.12)
                border.width: 1
                border.color: Qt.alpha(win.core.accent, 0.35)
                Row {
                    id: errRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (retry.visible ? retry.width + 10 : 0)
                        wrapMode: Text.WordWrap
                        text: "\u{F0028}  " + (win.client.error?.text ?? "")
                              + (win.client.outOfQuota && win.client.error?.text.startsWith("You've had")
                                 ? " Next one in " + win.until(win.client.quota.resets_at) + "." : "")
                        color: win.core.fg
                        font.family: win.core.font
                        font.pixelSize: 12
                    }
                    Btn {
                        id: retry
                        visible: !!win.client.error?.retry
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Retry"
                        enabled: !win.client.busy
                        onClicked: win.client.error.retry()
                    }
                }
            }

            Loader {
                width: parent.width
                height: parent.height - y
                sourceComponent: !win.client.tokenRead ? null
                    : !win.client.signedIn ? signupPage
                    : ({ theory: theoryPage, history: historyPage, profile: profilePage })[win.client.view]
            }
        }
    }

    // ---- Sign up ----
    Component {
        id: signupPage
        Flickable {
            contentHeight: signup.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: signup
                width: parent.width
                spacing: 14
                Text {
                    text: "What are you curious about?"
                    color: win.core.fg
                    font.family: win.core.font
                    font.pixelSize: 18
                    font.bold: true
                }
                Body {
                    text: "Describe your interests in your own words. You'll get short theories with sources, matched to them, up to your daily limit (it resets at 00:00 UTC)."
                    color: win.core.dim
                }
                InterestsBox { id: interests }
                Suggestions { box: interests }
                Label { text: "THEORIES PER DAY" }
                Stepper { id: limit; shell: win.core; value: 5; min: 1; max: 10; onEdited: v => value = v }
                Row {
                    spacing: 12
                    Btn {
                        primary: true
                        label: win.client.busy === "signup" ? "Reading your interests…" : "Sign up"
                        enabled: !win.client.busy && interests.text.trim().length >= 3 && interests.text.trim().length <= 1000
                        onClicked: win.client.signup(interests.text.trim(), limit.value)
                    }
                    Text {
                        visible: win.client.busy === "signup"
                        anchors.verticalCenter: parent.verticalCenter
                        text: "usually 3–10 s"
                        color: win.core.dim
                        font.family: win.core.font
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    // ---- Theory ----
    Component {
        id: theoryPage
        Item {
            id: theoryRoot
            readonly property var th: win.client.current

            Row {
                id: bar
                width: parent.width
                spacing: 12
                Btn {
                    primary: true
                    label: win.client.busy === "next" ? "Generating…" : "\u{F0142}  Next theory"
                    enabled: !win.client.busy && !win.client.outOfQuota
                    onClicked: win.client.next()
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.client.busy === "next" ? "usually 4–12 s"
                        : win.client.outOfQuota && !win.client.error ? "All done for today, next in " + win.until(win.client.quota.resets_at)
                        : theoryRoot.th && theoryRoot.th.id !== win.client.history[0]?.id ? "From history · " + win.day(theoryRoot.th.generated_at)
                        : ""
                    color: win.core.dim
                    font.family: win.core.font
                    font.pixelSize: 11
                }
            }

            Body {
                visible: !theoryRoot.th
                anchors.top: bar.bottom
                anchors.topMargin: 24
                text: "No theories yet. Press Next theory to get your first one."
                color: win.core.dim
            }

            Flickable {
                id: theoryScroll
                visible: !!theoryRoot.th
                anchors.top: bar.bottom
                anchors.topMargin: 18
                width: parent.width
                height: parent.height - y
                contentHeight: card.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // Back to the top when another theory is shown.
                onVisibleChanged: contentY = 0
                Connections {
                    target: win.client
                    function onCurrentChanged() { theoryScroll.contentY = 0 }
                }

                Column {
                    id: card
                    readonly property var th: theoryRoot.th ?? ({})
                    width: parent.width
                    spacing: 12

                    Label { text: ((card.th.topic ?? "") + (card.th.subtopic ? "  ›  " + card.th.subtopic : "")).toUpperCase() }
                    Column {
                        width: parent.width
                        spacing: 2
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: card.th.title ?? ""
                            color: win.core.fg
                            font.family: win.core.font
                            font.pixelSize: 20
                            font.bold: true
                        }
                        Text {
                            visible: !!card.th.originator
                            text: card.th.originator ?? ""
                            color: win.core.dim
                            font.family: win.core.font
                            font.pixelSize: 12
                        }
                    }
                    Body {
                        text: card.th.theory ?? ""
                        font.pixelSize: 13
                        lineHeight: 1.2
                    }
                    Rectangle {
                        visible: !!card.th.key_takeaway
                        width: parent.width
                        height: takeaway.implicitHeight + 24
                        radius: 12
                        color: Qt.alpha(win.core.accent, 0.12)
                        border.width: 1
                        border.color: Qt.alpha(win.core.accent, 0.35)
                        Text {
                            id: takeaway
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 12
                            wrapMode: Text.WordWrap
                            text: "\u{F0335}  " + (card.th.key_takeaway ?? "")
                            color: win.core.fg
                            font.family: win.core.font
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    Label { text: "SOURCES"; topPadding: 4 }
                    Repeater {
                        model: card.th.sources ?? []
                        LinkRow {
                            required property var modelData
                            text: "•  " + modelData.title + (modelData.author ? ", " + modelData.author : "")
                                  + (modelData.year ? " (" + modelData.year + ")" : "")
                                  + (modelData.type ? "  · " + modelData.type : "")
                            url: modelData.url ?? ""
                        }
                    }

                    Label { visible: (card.th.related ?? []).length > 0; text: "RELATED"; topPadding: 4 }
                    Flow {
                        visible: (card.th.related ?? []).length > 0
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: card.th.related ?? []
                            Chip { required property string modelData; label: modelData }
                        }
                    }

                    Label { visible: (card.th.further_reading ?? []).length > 0; text: "FURTHER READING"; topPadding: 4 }
                    Repeater {
                        model: card.th.further_reading ?? []
                        LinkRow {
                            required property var modelData
                            // The server always ends the list with the theory's Wikipedia entry (author "Wikipedia").
                            readonly property bool wiki: modelData.author === "Wikipedia"
                            text: wiki ? "\u{F05AC}  Read more on Wikipedia"
                                       : "•  " + modelData.title + (modelData.author ? ", " + modelData.author : "")
                            url: modelData.url ?? ""
                            hint: wiki ? "" : win.site(url)
                        }
                    }

                    // The sources are AI-claimed and unverified, so the disclaimer is always shown.
                    Body {
                        topPadding: 6
                        text: (card.th.disclaimer || "AI-generated; verify sources before citing.")
                              + "\n" + (card.th.model ?? "") + (card.th.generated_at ? " · " + win.day(card.th.generated_at) : "")
                        color: win.core.dim
                        font.pixelSize: 10
                        font.italic: true
                        bottomPadding: 8
                    }
                }
            }
        }
    }

    // ---- History ----
    Component {
        id: historyPage
        Item {
            Body {
                visible: win.client.history.length === 0
                text: "Nothing yet. Theories you get show up here, newest first."
                color: win.core.dim
            }
            ListView {
                anchors.fill: parent
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: win.client.history
                delegate: Rectangle {
                    id: entry
                    required property var modelData
                    width: ListView.view.width
                    height: 56
                    radius: 12
                    color: entryArea.containsMouse ? Qt.alpha(win.core.fg, 0.08) : Qt.alpha(win.core.fg, 0.04)
                    border.width: modelData.id === win.client.current?.id ? 1 : 0
                    border.color: Qt.alpha(win.core.accent, 0.35)
                    MouseArea {
                        id: entryArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { win.client.current = entry.modelData; win.client.view = "theory"; }
                    }
                    Column {
                        anchors.left: parent.left
                        anchors.right: when.left
                        anchors.leftMargin: 14
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: entry.modelData.title
                            color: win.core.fg
                            font.family: win.core.font
                            font.pixelSize: 13
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: entry.modelData.topic + "  ›  " + entry.modelData.subtopic
                                  + (entry.modelData.originator ? "  ·  " + entry.modelData.originator : "")
                            color: win.core.dim
                            font.family: win.core.font
                            font.pixelSize: 10
                        }
                    }
                    Text {
                        id: when
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.day(entry.modelData.generated_at)
                        color: win.core.dim
                        font.family: win.core.font
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    // ---- Interests and account ----
    Component {
        id: profilePage
        Flickable {
            contentHeight: profile.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: profile
                readonly property var me: win.client.me ?? ({})
                property bool confirmForget: false
                width: parent.width
                spacing: 14

                Label { text: "YOUR INTERESTS" }
                InterestsBox { id: interests; text: profile.me.interests ?? "" }
                Suggestions { box: interests }
                Label { text: "THEORIES PER DAY" }
                Stepper { id: limit; shell: win.core; value: profile.me.daily_limit ?? 5; min: 1; max: 10; onEdited: v => value = v }
                Row {
                    spacing: 12
                    Btn {
                        readonly property bool changed: interests.text.trim() !== profile.me.interests || limit.value !== profile.me.daily_limit
                        primary: true
                        label: win.client.busy === "save" ? "Saving…" : "Save"
                        enabled: !win.client.busy && changed && interests.text.trim().length >= 3 && interests.text.trim().length <= 1000
                        onClicked: win.client.save(interests.text.trim(), limit.value)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.client.busy === "save" ? "re-reading your interests, usually 3–10 s"
                            : "Changing interests keeps your history; theories still never repeat."
                        color: win.core.dim
                        font.family: win.core.font
                        font.pixelSize: 11
                    }
                }

                Label { text: "WHAT THE SERVER MADE OF THEM"; topPadding: 6 }
                Repeater {
                    model: profile.me.profile?.topics ?? []
                    Column {
                        id: topic
                        required property var modelData
                        width: profile.width
                        spacing: 2
                        Text {
                            text: topic.modelData.name + "  " + "●".repeat(topic.modelData.weight ?? 0)
                            color: win.core.fg
                            font.family: win.core.font
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Repeater {
                            model: topic.modelData.subtopics ?? []
                            Body {
                                required property var modelData
                                text: "   " + modelData.name + ((modelData.seeds ?? []).length ? ": " + modelData.seeds.join(", ") : "")
                                color: win.core.dim
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Label { text: "ACCOUNT"; topPadding: 6 }
                Body {
                    text: (profile.me.user_id ?? "") + (profile.me.created_at ? " · since " + win.day(profile.me.created_at) : "")
                          + "\nToken: " + win.client.tokenPath.replace(Quickshell.env("HOME"), "~")
                    color: win.core.dim
                    font.pixelSize: 11
                }
                Row {
                    spacing: 12
                    Btn {
                        label: profile.confirmForget ? "Yes, delete the token" : "Forget token (log out)"
                        enabled: !win.client.busy
                        onClicked: profile.confirmForget ? win.client.forget() : profile.confirmForget = true
                    }
                    Btn {
                        visible: profile.confirmForget
                        label: "Cancel"
                        onClicked: profile.confirmForget = false
                    }
                }
                Body {
                    visible: profile.confirmForget
                    text: "The server can't give the token back: you'd have to sign up again, and the history stays with the old account."
                    color: win.core.dim
                    font.pixelSize: 11
                    bottomPadding: 8
                }
            }
        }
    }
}
