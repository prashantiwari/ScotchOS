// The keybinds window: every live Hyprland bind, grouped and searchable, and an editor for the one picked.
// Created only while open. keybinds.py reads the binds and saves the edits (scotchos-binds.lua, then a reload).
import QtQuick
import Quickshell
import Quickshell.Io
import "../../settings"
import "keys.js" as Combo

FloatingWindow {
    id: win
    required property var kb
    readonly property var core: kb.core

    // ---- What keybinds.py reported ----
    property var binds: []          // rows: combo, canon, group, text, description, action, lua, flags, origin, edit…
    property var edits: []          // keybinds.json's list; a row's `edit` indexes it
    property bool wired: true       // hyprland.lua loads scotchos-binds.lua
    property var errors: []         // hyprctl configerrors
    property bool loading: true
    property bool saving: false
    property string message: ""
    property bool failed: false
    function fail(text) { message = text; failed = true }

    readonly property string helper: Quickshell.shellDir + "/tools/keybinds/keybinds.py"

    Process {
        id: listProc
        running: true
        command: ["python3", win.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.binds = d.binds;
                    win.edits = d.edits;
                    win.wired = d.wired;
                    win.errors = d.errors;
                } catch (e) {
                    win.fail("Couldn't read the binds (hyprctl binds -j).");
                }
                win.loading = false;
                win.refilter();
                win.reselect();
            }
        }
    }
    function reload() { loading = true; listProc.running = true }

    // A save writes the whole edit list; keybinds.py puts the old files back if Hyprland rejects it.
    Process {
        id: applyProc
        property string payload
        command: ["python3", win.helper, "apply", payload]
        stdout: StdioCollector {
            onStreamFinished: {
                win.saving = false;
                let d = null;
                try { d = JSON.parse(text) } catch (e) {}
                if (d?.ok) {
                    win.message = "Saved, and Hyprland reloaded.";
                    win.failed = false;
                    win.reload();
                } else {
                    win.fail(d?.error ?? "Saving failed.");
                }
            }
        }
    }
    function save(list) {
        if (saving) return;
        saving = true;
        message = "Saving…";
        failed = false;
        applyProc.payload = JSON.stringify({ binds: list });
        applyProc.running = true;
    }

    // ---- The list: rows that match the search, grouped by the first part of their [Category|…] ----
    property string query: ""
    onQueryChanged: refilter()
    ListModel { id: rows }
    function topGroup(b) { return (b.group || "Other").split("|")[0].trim() }
    function refilter() {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        // Groups in the order they first appear, which is HyDE's order; binds keep theirs inside a group.
        const order = [];
        for (const b of binds) if (!order.includes(topGroup(b))) order.push(topGroup(b));
        const out = [];
        binds.forEach((b, i) => {
            const hay = (Combo.caps(b.combo).join(" ") + " " + b.combo + " " + b.description + " " + b.action).toLowerCase();
            if (words.every(w => hay.includes(w))) out.push({ i, top: topGroup(b), rank: order.indexOf(topGroup(b)) });
        });
        out.sort((a, b) => a.rank - b.rank || a.i - b.i);
        rows.clear();
        for (const r of out) rows.append({ i: r.i, top: r.top });
    }

    // ---- The picked bind and its draft ----
    property int sel: -1            // index in binds, -1 for none or a new bind
    property bool adding: false
    property var draft: null        // { mods, key, mode: command|lua, exec, lua, group, text, flags }
    readonly property var current: sel >= 0 ? binds[sel] ?? null : null
    readonly property bool off: current?.origin === "off"
    function setDraft(change) { draft = Object.assign({}, draft, change) }

    function trueFlags(flags) {
        const out = {};
        for (const [k, v] of Object.entries(flags ?? {})) if (v === true) out[k] = true;
        return out;
    }
    function draftFrom(b) {
        const { mods, key } = Combo.parse(b.combo);
        const e = b.edit >= 0 ? edits[b.edit] : null;
        // A plain exec_cmd("…") is shown as its command; any other portable action as Lua.
        const literal = /^hl\.dsp\.exec_cmd\(\s*"((?:[^"\\]|\\.)*)"\s*\)$/.exec(b.lua ?? "");
        let mode = "command", exec = "", lua = "";
        if (e && !e.off) {
            if (e.lua) { mode = "lua"; lua = e.lua } else exec = e.exec ?? "";
        } else if (literal) {
            exec = literal[1].replace(/\\(.)/g, "$1");
        } else if (b.lua) {
            mode = "lua";
            lua = b.lua;
        }
        return { mods, key, mode, exec, lua, group: b.group, text: b.text, flags: trueFlags(b.flags) };
    }
    // A Field saves on losing focus: moving focus first puts what was typed into the draft it belongs to.
    function settle() { search.forceActiveFocus() }
    function pick(i) {
        settle();
        sel = i;
        adding = false;
        recording = false;
        draft = i >= 0 ? draftFrom(binds[i]) : null;
    }
    function startNew() {
        settle();
        sel = -1;
        adding = true;
        recording = false;
        draft = { mods: ["SUPER"], key: "", mode: "command", exec: "", lua: "", group: "Custom", text: "", flags: {} };
        message = "";
    }

    // After a save the list is new: pick the bind that was saved (by its keys), or the one a reset brought back.
    property string pendingCanon: ""
    function reselect() {
        const c = pendingCanon;
        pendingCanon = "";
        let i = c ? binds.findIndex(b => b.canon === c && b.origin !== "off") : -1;
        if (c && i < 0) i = binds.findIndex(b => b.canon === c);
        adding = false;
        pick(i);
    }

    readonly property string draftCombo: draft ? Combo.format(draft.mods, draft.key.trim()) : ""
    // Other live binds on the keys being edited: saving takes the keys over from them.
    readonly property var clashes: draft && draft.key.trim()
        ? binds.filter((b, i) => i !== sel && b.origin !== "off" && b.canon === Combo.canonical(win.draftCombo)) : []
    readonly property bool canSave: !!draft && !saving && wired && !!draft.key.trim()
        && !!(draft.mode === "lua" ? draft.lua.trim() : draft.exec.trim())

    // ---- Turning the draft into edits ----
    function entry() {
        const group = draft.group.trim();
        const e = { combo: draftCombo, description: (group ? "[" + group + "] " : "") + draft.text.trim(), flags: draft.flags };
        if (draft.mode === "lua") e.lua = draft.lua.trim(); else e.exec = draft.exec.trim();
        return e;
    }
    function commit() {
        settle();
        if (!canSave) return;
        const list = edits.slice();
        const b = current;
        const e = entry();
        if (b && b.edit >= 0) {
            const old = list[b.edit];
            list[b.edit] = Object.assign({ was: old.was ?? "", original: old.original }, e);
        } else {
            // `original` is what a switched-off bind shows, once its own row is gone.
            list.push(Object.assign({ was: b ? b.combo : "", original: b ? { description: b.description, action: b.action } : undefined }, e));
        }
        pendingCanon = Combo.canonical(e.combo);
        save(list);
    }
    function switchOff() {
        settle();
        const b = current, list = edits.slice();
        if (b.edit >= 0) {
            const old = list[b.edit];
            // A bind added here just goes; a changed one leaves its original place switched off.
            if (!old.was) list.splice(b.edit, 1);
            else list[b.edit] = { was: old.was, combo: old.was, off: true,
                                  description: old.original?.description ?? old.description, action: old.original?.action ?? "" };
        } else {
            list.push({ was: b.combo, combo: b.combo, off: true, description: b.description, action: b.action });
        }
        pendingCanon = "";
        save(list);
    }
    // Drops the edit: HyDE's (or hyprland.lua's) bind comes back as it was.
    function reset() {
        settle();
        const b = current, list = edits.slice();
        const old = list[b.edit];
        list.splice(b.edit, 1);
        pendingCanon = Combo.canonical(old.was || old.combo);
        save(list);
    }

    // ---- Recording a key: the next press sets the key, and adds the modifiers held (Super rarely gets here) ----
    property bool recording: false

    // A fixed size makes Hyprland float the window, like the settings window.
    implicitWidth: 900
    implicitHeight: 560
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)
    title: "ScotchOS keybinds"
    color: core.bg
    onClosed: kb.open = false

    Item {
        anchors.fill: parent
        Keys.onEscapePressed: win.kb.open = false

        // ---- Left: search and the list ----
        Rectangle {
            id: side
            width: 520
            anchors.top: parent.top
            anchors.bottom: status.top
            color: Qt.alpha(win.core.fg, 0.04)

            Text {
                id: brand
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 16
                text: "\u{F030C}  KEYBINDS"
                color: win.core.accent
                font.family: win.core.font
                font.pixelSize: 14
                font.bold: true
            }
            Text {
                anchors.left: brand.right
                anchors.leftMargin: 10
                anchors.baseline: brand.baseline
                text: win.loading ? "reading…" : rows.count + " of " + win.binds.length
                color: win.core.dim
                font.family: win.core.font
                font.pixelSize: 11
            }
            Choice {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: brand.verticalCenter
                shell: win.core
                options: ["\u{F0415}  new bind"]
                value: win.adding ? options[0] : ""
                onPicked: win.startNew()
            }

            Rectangle {
                id: searchBox
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: brand.bottom
                anchors.margins: 16
                height: 32
                radius: 8
                color: Qt.alpha(win.core.fg, 0.06)
                border.width: 1
                border.color: search.activeFocus ? win.core.accent : Qt.alpha(win.core.accent, 0.35)

                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 32
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    focus: true
                    color: win.core.fg
                    selectionColor: win.core.accentDim
                    font.family: win.core.font
                    font.pixelSize: 12
                    onTextChanged: win.query = text
                    // ↑ / ↓ walk the list (the editor follows), so keys alone get from a search to a bind.
                    function walk(by) {
                        if (!rows.count) return;
                        const at = Array.from({ length: rows.count }, (_, n) => rows.get(n).i).indexOf(win.sel);
                        const n = Math.max(0, Math.min(rows.count - 1, at < 0 ? 0 : at + by));
                        win.pick(rows.get(n).i);
                        list.positionViewAtIndex(n, ListView.Contain);
                    }
                    Keys.onDownPressed: walk(1)
                    Keys.onUpPressed: walk(-1)
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F0349}"
                    color: win.core.dim
                    font.family: win.core.font
                    font.pixelSize: 14
                }
                Text {
                    anchors.fill: search
                    visible: !search.text
                    verticalAlignment: Text.AlignVCenter
                    text: "Search keys, names, commands"
                    color: win.core.dim
                    font.family: win.core.font
                    font.pixelSize: 12
                }
            }

            ListView {
                id: list
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: searchBox.bottom
                anchors.bottom: parent.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: rows
                section.property: "top"
                section.delegate: Text {
                    required property string section
                    height: 28
                    verticalAlignment: Text.AlignBottom
                    bottomPadding: 6
                    text: section.toUpperCase()
                    color: win.core.accent
                    font.family: win.core.font
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }

                delegate: Rectangle {
                    id: row
                    required property int i
                    readonly property var b: win.binds[i] ?? ({})
                    readonly property bool current: i === win.sel
                    width: ListView.view.width
                    height: 30
                    radius: 8
                    color: current ? Qt.alpha(win.core.accent, 0.18) : (area.containsMouse ? Qt.alpha(win.core.fg, 0.06) : "transparent")
                    border.width: current ? 1 : 0
                    border.color: Qt.alpha(win.core.accent, 0.35)
                    opacity: b.origin === "off" ? 0.55 : 1

                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.pick(row.i)
                    }
                    Row {
                        id: caps
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 190
                        clip: true
                        spacing: 4
                        Repeater {
                            model: Combo.caps(row.b.combo ?? "")
                            KeyCap { shell: win.core; label: modelData }
                        }
                    }
                    Text {
                        anchors.left: caps.right
                        anchors.leftMargin: 8
                        anchors.right: tag.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.b.text || row.b.description || row.b.action || ""
                        elide: Text.ElideRight
                        font.strikeout: row.b.origin === "off"
                        color: win.core.fg
                        font.family: win.core.font
                        font.pixelSize: 12
                    }
                    // Where it comes from, when it isn't HyDE's default.
                    Text {
                        id: tag
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: ({ scotchos: "\u{F03EB} changed", off: "off", user: "hyprland.lua" })[row.b.origin] ?? ""
                        color: row.b.origin === "scotchos" ? win.core.accent : win.core.dim
                        font.family: win.core.font
                        font.pixelSize: 10
                    }
                }
            }
            Scrollbar {
                anchors.left: list.right
                anchors.leftMargin: 6
                anchors.top: list.top
                anchors.bottom: list.bottom
                shell: win.core
                flick: list
            }
        }

        // ---- Right: the editor ----
        Item {
            id: editor
            anchors.left: side.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: status.top
            anchors.margins: 20

            // Nothing picked: what this is.
            Column {
                visible: !win.draft
                width: parent.width
                spacing: 10
                Text {
                    text: "\u{F030C}  Hyprland keybinds"
                    color: win.core.fg
                    font.family: win.core.font
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: win.core.dim
                    font.family: win.core.font
                    font.pixelSize: 12
                    text: "Every bind Hyprland has loaded. Pick one to change its keys, what it runs, its name or flags, or to switch it off; or add a new one.\n\n"
                        + "Changes go to ~/.config/hypr/scotchos-binds.lua, which hyprland.lua loads last. HyDE's files aren't touched, and \"reset\" brings its bind back.\n\n"
                        + "Super combos reach Hyprland before this window: pick Super with its button, then record the key."
                }
            }

            Column {
                id: form
                visible: !!win.draft
                width: parent.width
                spacing: 14

                Column {
                    width: parent.width
                    spacing: 2
                    Text {
                        width: parent.width
                        text: win.adding ? "New bind" : (win.current?.text || win.current?.description || win.current?.combo || "")
                        elide: Text.ElideRight
                        color: win.core.fg
                        font.family: win.core.font
                        font.pixelSize: 16
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideMiddle
                        color: win.core.dim
                        font.family: win.core.font
                        font.pixelSize: 10
                        text: {
                            const b = win.current;
                            if (win.adding || !b) return "added here, in scotchos-binds.lua";
                            const at = b.file ? b.file.split("/").pop() + (b.line ? ":" + b.line : "") : "";
                            return ({ hyde: "HyDE default · " + at, user: "yours · " + at,
                                      scotchos: "changed here · scotchos-binds.lua", off: "switched off here · scotchos-binds.lua" })[b.origin]
                                ?? "not found in the Lua files";
                        }
                    }
                }

                // A switched-off bind: what it was, and the way back.
                Column {
                    visible: win.off
                    width: parent.width
                    spacing: 10
                    Text {
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                        text: win.current?.action ? "It ran:  " + win.current.action : ""
                        color: win.core.dim
                        font.family: win.core.font
                        font.pixelSize: 11
                    }
                    Choice {
                        shell: win.core
                        options: ["\u{F0E2}  switch back on"]
                        onPicked: win.reset()
                    }
                }

                // ---- Keys ----
                Column {
                    visible: !win.off
                    width: parent.width
                    spacing: 6
                    Label { text: "KEYS" }
                    Row {
                        spacing: 6
                        Repeater {
                            model: ["SUPER", "CTRL", "ALT", "SHIFT"]
                            Flag {
                                required property string modelData
                                label: Combo.caps(modelData + " + x")[0]
                                on: win.draft?.mods.includes(modelData) ?? false
                                onToggled: win.setDraft({ mods: on ? win.draft.mods.filter(m => m !== modelData) : win.draft.mods.concat([modelData]) })
                            }
                        }
                    }
                    Row {
                        spacing: 6
                        Field {
                            id: keyField
                            width: form.width - recordBtn.width - 6
                            shell: win.core
                            plain: true
                            value: win.draft?.key ?? ""
                            placeholder: "key: T, slash, F5, Return, XF86AudioPlay, mouse:272"
                            onEdited: v => win.setDraft({ key: v })
                        }
                        Rectangle {
                            id: recordBtn
                            width: recordText.implicitWidth + 20
                            height: 30
                            radius: 8
                            color: win.recording ? win.core.accent : (recordArea.containsMouse ? Qt.alpha(win.core.fg, 0.12) : Qt.alpha(win.core.fg, 0.06))
                            border.width: 1
                            border.color: win.recording ? win.core.accent : Qt.alpha(win.core.accent, 0.35)
                            Text {
                                id: recordText
                                anchors.centerIn: parent
                                text: win.recording ? "press a key…" : "\u{F044A}  record"
                                color: win.recording ? win.core.bg : win.core.fg
                                font.family: win.core.font
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: recordArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    win.settle();
                                    win.recording = !win.recording;
                                    if (win.recording) recorder.forceActiveFocus();
                                }
                            }
                            // Takes the next key press; Esc gives up.
                            Item {
                                id: recorder
                                onActiveFocusChanged: if (!activeFocus) win.recording = false
                                Keys.onPressed: event => {
                                    event.accepted = true;
                                    if (event.key === Qt.Key_Escape) { win.settle(); return; }
                                    const name = Combo.keyName(event.key, event.text);
                                    if (!name) return;      // a modifier on its own: wait for the key
                                    const held = Combo.modsOf(event.modifiers).filter(m => !win.draft.mods.includes(m));
                                    win.setDraft({ key: name, mods: win.draft.mods.concat(held) });
                                    win.settle();
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        visible: win.clashes.length > 0
                        wrapMode: Text.WordWrap
                        text: "\u{F0026}  Also on " + Combo.caps(win.draftCombo).join(" + ") + ": "
                            + win.clashes.map(b => b.text || b.description).join(", ")
                            + ". Saving takes the keys over (reset this one and they come back)."
                        color: win.core.fg
                        font.family: win.core.font
                        font.pixelSize: 11
                    }
                }

                // ---- Action ----
                Column {
                    visible: !win.off
                    width: parent.width
                    spacing: 6
                    Label { text: "ACTION" }
                    Choice {
                        shell: win.core
                        options: ["command", "lua"]
                        value: win.draft?.mode ?? "command"
                        onPicked: v => { win.settle(); win.setDraft({ mode: v }) }
                    }
                    Field {
                        width: form.width
                        shell: win.core
                        plain: true
                        value: (win.draft?.mode === "lua" ? win.draft?.lua : win.draft?.exec) ?? ""
                        placeholder: win.draft?.mode === "lua" ? "hl.dsp.focus({workspace = 3})" : "kitty -e btop"
                        onEdited: v => win.setDraft(win.draft.mode === "lua" ? { lua: v } : { exec: v })
                    }
                    // HyDE's local helpers (move_window, cycle_fullscreen) only exist inside key_binds.lua.
                    Text {
                        width: parent.width
                        visible: !win.adding && !!win.current && !win.current.lua && win.current.origin !== "scotchos"
                        wrapMode: Text.WordWrap
                        text: "It runs " + (win.current?.action || "a Lua function") + ", which only exists inside HyDE's key_binds.lua: "
                            + "give it a command or a Lua action to change it, or switch it off."
                        color: win.core.dim
                        font.family: win.core.font
                        font.pixelSize: 11
                    }
                }

                // ---- Name ----
                Column {
                    visible: !win.off
                    width: parent.width
                    spacing: 6
                    Label { text: "NAME" }
                    Row {
                        spacing: 6
                        Field {
                            width: 120
                            shell: win.core
                            plain: true
                            value: win.draft?.group ?? ""
                            placeholder: "Group|Sub"
                            onEdited: v => win.setDraft({ group: v.replace(/[\[\]]/g, "") })
                        }
                        Field {
                            width: form.width - 126
                            shell: win.core
                            plain: true
                            value: win.draft?.text ?? ""
                            placeholder: "what it does"
                            onEdited: v => win.setDraft({ text: v })
                        }
                    }
                }

                // ---- Flags ----
                Column {
                    visible: !win.off
                    width: parent.width
                    spacing: 6
                    Label { text: "FLAGS" }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [{ key: "locked", label: "on lock screen" }, { key: "repeating", label: "repeat held" },
                                    { key: "release", label: "on release" }]
                            Flag {
                                required property var modelData
                                label: modelData.label
                                on: win.draft?.flags[modelData.key] === true
                                onToggled: {
                                    const f = Object.assign({}, win.draft.flags);
                                    if (on) delete f[modelData.key]; else f[modelData.key] = true;
                                    win.setDraft({ flags: f });
                                }
                            }
                        }
                    }
                }
            }

            // ---- Buttons, at the bottom of the editor ----
            Row {
                visible: !!win.draft && !win.off
                anchors.bottom: parent.bottom
                spacing: 6
                Button {
                    label: "\u{F0193}  save"
                    primary: true
                    enabled: win.canSave
                    onClicked: win.commit()
                }
                Button {
                    visible: !win.adding && !!win.current
                    label: "\u{F0377}  switch off"
                    enabled: !win.saving && win.wired
                    onClicked: win.switchOff()
                }
                Button {
                    visible: !win.adding && (win.current?.edit ?? -1) >= 0 && !!win.edits[win.current.edit]?.was
                    label: "\u{F0E2}  reset"
                    enabled: !win.saving && win.wired
                    onClicked: win.reset()
                }
                Button {
                    label: "cancel"
                    onClicked: win.adding ? win.pick(-1) : win.pick(win.sel)
                }
            }
        }

        // ---- Status line: the last save, config errors, or why nothing can be saved ----
        Rectangle {
            id: status
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: statusText.text ? Math.max(28, statusText.implicitHeight + 12) : 0
            color: Qt.alpha(win.core.fg, 0.06)
            Text {
                id: statusText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                wrapMode: Text.WordWrap
                maximumLineCount: 4
                elide: Text.ElideRight
                text: !win.wired ? "\u{F0026}  hyprland.lua doesn't load scotchos-binds.lua, so edits can't apply (tools/keybinds/README.md)."
                    : win.message ? win.message
                    : win.errors.length ? "\u{F0026}  Hyprland config errors: " + win.errors.join(" · ") : ""
                color: win.failed || !win.wired ? win.core.fg : win.core.dim
                font.bold: win.failed
                font.family: win.core.font
                font.pixelSize: 11
            }
        }
    }

    // ---- Small pieces used above ----
    component Label: Text {
        color: win.core.accent
        font.family: win.core.font
        font.pixelSize: 11
        font.letterSpacing: 1
    }
    // One key of a combo in the list.
    component KeyCap: Rectangle {
        id: cap
        property var shell
        property string label
        width: capText.implicitWidth + 10
        height: 20
        radius: 5
        color: Qt.alpha(win.core.fg, 0.08)
        border.width: 1
        border.color: Qt.alpha(win.core.accent, 0.35)
        Text {
            id: capText
            anchors.centerIn: parent
            text: cap.label
            color: win.core.fg
            font.family: win.core.font
            font.pixelSize: 11
        }
    }
    // A chip that's on or off (modifiers, flags).
    component Flag: Rectangle {
        id: flag
        property string label
        property bool on
        signal toggled()
        width: flagText.implicitWidth + 18
        height: 26
        radius: 8
        color: on ? win.core.accent : (flagArea.containsMouse ? Qt.alpha(win.core.fg, 0.12) : Qt.alpha(win.core.fg, 0.06))
        border.width: 1
        border.color: on ? win.core.accent : Qt.alpha(win.core.accent, 0.35)
        Text {
            id: flagText
            anchors.centerIn: parent
            text: flag.label
            color: flag.on ? win.core.bg : win.core.fg
            font.family: win.core.font
            font.pixelSize: 12
        }
        MouseArea {
            id: flagArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { win.settle(); flag.toggled() }
        }
    }
    component Button: Rectangle {
        id: btn
        property string label
        property bool primary: false
        property bool enabled: true
        signal clicked()
        width: btnText.implicitWidth + 22
        height: 30
        radius: 8
        opacity: enabled ? 1 : 0.4
        color: primary ? win.core.accent : (btnArea.containsMouse ? Qt.alpha(win.core.fg, 0.12) : Qt.alpha(win.core.fg, 0.06))
        border.width: 1
        border.color: primary ? win.core.accent : Qt.alpha(win.core.accent, 0.35)
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? win.core.bg : win.core.fg
            font.family: win.core.font
            font.pixelSize: 12
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.enabled) btn.clicked()
        }
    }
}
