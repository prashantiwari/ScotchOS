// Launcher window: a full-screen click-to-close layer holding one card (chip + input + result rows).
// Created only while open; the providers live in Launcher.qml (`launcher`).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win
    required property var launcher
    readonly property var core: launcher.core

    // On the monitor with focus, above windows, and the only thing that gets the keyboard while it's open.
    screen: launcher.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "scotchos-launcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    color: Qt.alpha("black", 0.25)

    // ---- State ----
    property var mode: null         // the provider locked in as a chip, or null
    property int sel: 0
    readonly property int maxRows: 9
    // Nothing typed: the recent apps as square icons, wrapping onto new rows (tile 56 + gap 8 = 9 per row in the card).
    readonly property bool grid: !mode && !input.text.trim()
    readonly property int maxTiles: 18
    readonly property int perRow: 9

    // The provider a typed keyword selects ("yt cats", "> restart"); `tab` also accepts the bare word.
    function parse(raw, tab) {
        if (mode) return { provider: mode, query: raw };
        for (const p of launcher.providers) {
            for (const k of p.keywords) {
                const symbol = !/\w/.test(k);
                if (raw.startsWith(k + " ") || (symbol && raw.startsWith(k)) || (tab && raw === k))
                    return { provider: p, query: raw.slice(k.length).trimStart() };
            }
        }
        return { provider: null, query: raw };
    }

    // Plain text searches every inDefault provider, then the fallbacks (never cut off); a keyword or chip searches one.
    function compute(raw) {
        const { provider, query } = parse(raw, false);
        if (provider) return provider.search(query).slice(0, maxRows);
        if (!query.trim()) {
            const recent = [];
            for (const p of launcher.providers) recent.push(...p.recents());
            return recent.slice(0, maxTiles);
        }
        const rows = [];
        for (const p of launcher.providers) if (p.inDefault) rows.push(...p.search(query).slice(0, 5));
        const tail = [];
        for (const p of launcher.providers) tail.push(...p.fallback(query));
        return rows.slice(0, maxRows - tail.length).concat(tail);
    }
    readonly property var results: compute(input.text)
    readonly property var picked: results[sel] ?? null
    onResultsChanged: sel = 0

    // Tab: a typed keyword becomes the chip; otherwise it steps through the providers (and back to none).
    function tab(step) {
        if (!mode && step > 0) {
            const { provider, query } = parse(input.text, true);
            if (provider) { mode = provider; input.text = query; return; }
        }
        const order = [null, ...launcher.providers];
        const i = order.indexOf(mode);
        mode = order[(i + step + order.length) % order.length];
    }

    function run(alt) {
        const r = picked;
        if (!r) return;
        const f = alt ? r.alt : r.run;
        if (!f) return;
        f();
        launcher.open = false;
    }

    // ---- Click outside the card closes ----
    MouseArea {
        anchors.fill: parent
        onClicked: win.launcher.open = false
    }

    // ---- Card ----
    Rectangle {
        id: card
        width: 640
        height: column.implicitHeight
        x: (parent.width - width) / 2
        y: parent.height * 0.2
        radius: 18
        color: Qt.alpha(win.core.bg, 0.94)
        border.width: 1
        border.color: Qt.alpha(win.core.accent, 0.35)

        MouseArea { anchors.fill: parent }      // clicks on the card don't reach the closing area

        Column {
            id: column
            width: parent.width

            // ---- Input ----
            Item {
                width: parent.width
                height: 60

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12

                    Text {
                        visible: !win.mode
                        text: ""
                        color: win.core.accent
                        font.family: win.core.font
                        font.pixelSize: 18
                    }
                    Rectangle {
                        visible: !!win.mode
                        Layout.preferredWidth: chipText.implicitWidth + 20
                        Layout.preferredHeight: 30
                        radius: 9
                        color: Qt.alpha(win.core.accent, 0.2)
                        border.width: 1
                        border.color: Qt.alpha(win.core.accent, 0.5)
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: (win.mode?.glyph ?? "") + "  " + (win.mode?.name ?? "")
                            color: win.core.accent
                            font.family: win.core.font
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }
                    Item {
                        Layout.fillWidth: true      // the input takes what's left of the row
                        Layout.fillHeight: true
                        TextInput {
                            id: input
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            color: win.core.fg
                            selectionColor: win.core.accent
                            selectedTextColor: win.core.bg
                            font.family: win.core.font
                            font.pixelSize: 18
                            clip: true
                            focus: true
                            Component.onCompleted: forceActiveFocus()

                            Text {
                                visible: !input.text
                                text: win.mode ? win.mode.placeholder : "Search apps and commands, or yt …"
                                color: win.core.dim
                                font: input.font
                            }

                            Keys.onPressed: e => {
                                const alt = e.modifiers & Qt.ShiftModifier;
                                const ctrl = e.modifiers & Qt.ControlModifier;
                                if (e.key === Qt.Key_Escape) win.launcher.open = false;
                                else if (e.key === Qt.Key_Tab) win.tab(1);
                                else if (e.key === Qt.Key_Backtab) win.tab(-1);
                                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.run(alt);
                                else if (win.grid && e.key === Qt.Key_Left) win.sel = Math.max(win.sel - 1, 0);
                                else if (win.grid && e.key === Qt.Key_Right) win.sel = Math.min(win.sel + 1, win.results.length - 1);
                                else if (win.grid && (e.key === Qt.Key_Down || (ctrl && (e.key === Qt.Key_J || e.key === Qt.Key_N))))
                                    win.sel = Math.min(win.sel + win.perRow, win.results.length - 1);
                                else if (win.grid && (e.key === Qt.Key_Up || (ctrl && (e.key === Qt.Key_K || e.key === Qt.Key_P))))
                                    win.sel = Math.max(win.sel - win.perRow, 0);
                                else if (e.key === Qt.Key_Down || (ctrl && (e.key === Qt.Key_J || e.key === Qt.Key_N)))
                                    win.sel = Math.min(win.sel + 1, win.results.length - 1);
                                else if (e.key === Qt.Key_Up || (ctrl && (e.key === Qt.Key_K || e.key === Qt.Key_P)))
                                    win.sel = Math.max(win.sel - 1, 0);
                                else if (e.key === Qt.Key_Backspace && !input.text && win.mode) win.mode = null;
                                else return;
                                e.accepted = true;
                            }
                        }
                    }
                }
            }

            // ---- Results: a fixed set of rows, shown or hidden, so typing doesn't rebuild anything ----
            Rectangle {
                visible: win.results.length > 0
                width: parent.width - 40
                x: 20
                height: 1
                color: Qt.alpha(win.core.accent, 0.25)
            }
            // ---- Recent apps: icon tiles, the picked one's name underneath ----
            Column {
                visible: win.grid && win.results.length > 0
                width: parent.width
                topPadding: 10
                bottomPadding: 4
                leftPadding: 20
                spacing: 6
                Flow {
                    width: parent.width - 40
                    spacing: 8
                    Repeater {
                        model: win.maxTiles
                        delegate: Rectangle {
                            id: tile
                            required property int index
                            readonly property var r: win.results[index] ?? null
                            visible: !!r
                            width: 56
                            height: 56
                            radius: 12
                            color: index === win.sel ? Qt.alpha(win.core.accent, 0.22)
                                                     : (tileArea.containsMouse ? Qt.alpha(win.core.fg, 0.07) : Qt.alpha(win.core.fg, 0.04))
                            border.width: index === win.sel ? 1 : 0
                            border.color: Qt.alpha(win.core.accent, 0.6)
                            Image {
                                anchors.centerIn: parent
                                width: 36
                                height: 36
                                source: tile.r?.iconName ? Quickshell.iconPath(tile.r.iconName, "application-x-executable") : ""
                                sourceSize: Qt.size(36, 36)     // decoded at display size
                                asynchronous: true
                            }
                            MouseArea {
                                id: tileArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: win.sel = tile.index
                                onClicked: win.run(false)
                            }
                        }
                    }
                }
                Text {
                    width: parent.width - 40
                    text: win.picked?.title ?? ""
                    elide: Text.ElideRight
                    color: win.core.dim
                    font.family: win.core.font
                    font.pixelSize: 11
                }
            }

            Column {
                visible: !win.grid
                width: parent.width
                topPadding: win.results.length ? 6 : 0
                Repeater {
                    model: win.maxRows
                    delegate: Rectangle {
                        id: rowItem
                        required property int index
                        readonly property var r: win.results[index] ?? null
                        readonly property bool current: index === win.sel
                        visible: !!r
                        x: 8
                        width: parent.width - 16
                        height: visible ? 46 : 0
                        radius: 10
                        color: current ? Qt.alpha(win.core.accent, 0.22)
                                       : (rowArea.containsMouse ? Qt.alpha(win.core.fg, 0.07) : "transparent")

                        Item {
                            id: iconBox
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            Image {
                                anchors.fill: parent
                                visible: !!rowItem.r?.iconName
                                source: rowItem.r?.iconName ? Quickshell.iconPath(rowItem.r.iconName, "application-x-executable") : ""
                                sourceSize: Qt.size(28, 28)     // decoded at display size
                                asynchronous: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !rowItem.r?.iconName
                                text: rowItem.r?.glyph ?? ""
                                color: win.core.accent
                                font.family: win.core.font
                                font.pixelSize: 20
                            }
                        }
                        Column {
                            anchors.left: iconBox.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: parent.width
                                text: rowItem.r?.title ?? ""
                                elide: Text.ElideRight
                                color: win.core.fg
                                font.family: win.core.font
                                font.pixelSize: 14
                            }
                            Text {
                                width: parent.width
                                visible: !!rowItem.r?.subtitle
                                text: rowItem.r?.subtitle ?? ""
                                elide: Text.ElideRight
                                color: win.core.dim
                                font.family: win.core.font
                                font.pixelSize: 11
                            }
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: win.sel = rowItem.index
                            onClicked: win.run(false)
                        }
                    }
                }
            }

            // ---- Key hints ----
            Text {
                x: 20
                width: parent.width - 40
                height: 30
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                color: win.core.dim
                font.family: win.core.font
                font.pixelSize: 10
                text: "↵ open"
                      + (win.picked?.alt ? "   ⇧↵ " + win.picked.altHint : "")
                      + "   ⇥ " + (win.mode ? "next mode" : "pick a mode")
                      + "   esc close"
            }
        }
    }
}
