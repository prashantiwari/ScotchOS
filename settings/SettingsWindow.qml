// ScotchOS settings: switch widgets and tools on and off and change their settings. Every change is
// written to ~/.config/scotchos/scotchos.conf right away, so the desktop widgets update while you click.
import QtQuick
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: win
    required property var core

    // ---- What can be set, per widget / tool ----
    // Each setting: key in the item's [section], label, type (choice / position / number / flag / text), default.
    readonly property var items: [
        { key: "dashboard", name: "Dashboard", kind: "widget", icon: "\u{F056E}",
          about: "CPU, RAM and temperature rings, 60 s graphs, GPU, disk, battery and top processes.",
          settings: [
              { key: "layout", label: "Layout", type: "choice", options: ["vertical", "horizontal", "square"], def: "vertical" },
              { key: "position", label: "Position", type: "position", auto: true, def: "auto" },
              { key: "margin_x", label: "Margin X", type: "number", def: 20, min: 0, max: 600, step: 5, unit: "px" },
              { key: "margin_y", label: "Margin Y", type: "number", def: 20, min: 0, max: 600, step: 5, unit: "px" },
              { key: "show_disk", label: "Show disk", type: "flag", def: "yes" },
              { key: "show_battery", label: "Show battery", type: "flag", def: "yes" },
          ] },
        { key: "nowplaying", name: "Now playing", kind: "widget", icon: "\u{F075A}",
          about: "The current track from any MPRIS player, with album art and a cava visualizer.",
          settings: [
              { key: "position", label: "Position", type: "position", def: "right" },
              { key: "margin_x", label: "Margin X", type: "number", def: 20, min: 0, max: 600, step: 5, unit: "px" },
              { key: "margin_y", label: "Margin Y", type: "number", def: 20, min: 0, max: 600, step: 5, unit: "px" },
              { key: "show_paused", label: "Show while paused", type: "flag", def: "yes" },
              { key: "layout", label: "Layout", type: "choice", options: ["card", "radial"], def: "card" },
              { key: "visualizer", label: "Visualizer", type: "choice", options: ["middle", "bar"], def: "middle" },
          ] },
        { key: "quote", name: "Hourly quote", kind: "widget", icon: "\u{F027E}",
          about: "A new quote from the web at a set interval.",
          settings: [
              { key: "position", label: "Position", type: "position", def: "bottom-right" },
              { key: "margin_x", label: "Margin X", type: "number", def: 20, min: 0, max: 600, step: 5, unit: "px" },
              { key: "margin_y", label: "Margin Y", type: "number", def: 20, min: 0, max: 600, step: 5, unit: "px" },
              { key: "interval", label: "New quote every", type: "number", def: 60, min: 1, max: 1440, step: 5, unit: "min" },
          ] },
        { key: "claudeusage", name: "Claude usage", kind: "widget", icon: "\u{F06A9}",
          about: "Claude plan usage: the 5-hour and 7-day limits and when they reset. Fetched at login, then every interval.",
          settings: [
              { key: "size", label: "Size", type: "choice", options: ["full", "compact", "minimal"], def: "full" },
              { key: "position", label: "Position", type: "position", def: "top-right" },
              { key: "margin_x", label: "Margin X", type: "number", def: 20, min: 0, max: 600, step: 5, unit: "px" },
              { key: "margin_y", label: "Margin Y", type: "number", def: 20, min: 0, max: 600, step: 5, unit: "px" },
              { key: "interval", label: "Fetch every", type: "number", def: 30, min: 5, max: 1440, step: 5, unit: "min" },
              { key: "warn", label: "Warn at", type: "number", def: 80, min: 1, max: 100, step: 5, unit: "%" },
              { key: "notify", label: "Notify at warn", type: "flag", def: "yes" },
              { key: "refresh", label: "Usage", type: "action", text: "Refresh now", action: "refresh" },
          ] },
        { key: "launcher", name: "Launcher", kind: "tool", icon: "\u{F0349}",
          about: "One box for apps, YouTube search and ScotchOS commands. Type a keyword (yt, >) and press Tab to lock it in, or just type to search apps.",
          settings: [
              { key: "browser", label: "Browser (YouTube)", type: "text", def: "brave --incognito --new-window", placeholder: "brave --incognito --new-window" },
              { key: "browser_class", label: "Browser window class", type: "text", def: "brave-browser", placeholder: "brave-browser" },
              { key: "workspace", label: "Opens on workspace", type: "text", def: "1", placeholder: "1" },
          ] },
        { key: "dailytheory", name: "Daily theory", kind: "tool", icon: "\u{F0335}",
          about: "Short theories with sources, matched to your interests, from a dailyTheory server. Open it from the app launcher (Daily Theory) or `scotchos theory`.",
          settings: [
              { key: "server", label: "Server", type: "text", def: "http://localhost:8080", placeholder: "http://localhost:8080" },
              { key: "registration_key", label: "Registration key", type: "text", def: "", secret: true, placeholder: "only if the server needs one" },
          ] },
        { key: "reader", name: "E-reader", kind: "tool", icon: "\u{F00BA}",
          about: "A minimalist e-book reader in the theme's colors: EPUB, MOBI, AZW3, FB2, TXT and Markdown from one folder. Open it from the app launcher (E-reader) or `scotchos reader`. In a book: T contents, B bookmark, M bookmarks, / search, A fonts and text, W column / full width / two pages, F fullscreen, S pages/scroll, + - [ ] , . adjust.",
          settings: [
              { key: "library_dir", label: "Library folder", type: "text", def: "~/Books", placeholder: "~/Books" },
              { key: "layout", label: "Layout", type: "choice", options: ["pages", "scroll"], def: "pages" },
              { key: "font", label: "Font", type: "text", def: "serif", placeholder: "serif" },
              { key: "font_size", label: "Font size", type: "number", def: 16, min: 10, max: 32, step: 1, unit: "px" },
              { key: "width", label: "Column width", type: "number", def: 720, min: 400, max: 1600, step: 40, unit: "px" },
              { key: "page_layout", label: "Page layout", type: "choice", options: ["column", "full", "two"], def: "column" },
              { key: "line_height", label: "Line spacing", type: "number", def: 150, min: 100, max: 220, step: 10, unit: "%" },
              { key: "justify", label: "Justify text", type: "flag", def: "no" },
              { key: "time_left", label: "Time left", type: "flag", def: "yes" },
          ] },
    ]
    property string selected: items[0].key
    readonly property var item: items.find(i => i.key === selected)

    function value(section, s) { return core.conf[section]?.[s.key] ?? String(s.def) }

    // A fixed size makes Hyprland float the window, so the desktop widgets stay visible behind it.
    implicitWidth: 720
    implicitHeight: 460
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)
    title: "ScotchOS settings"
    color: core.bg
    onClosed: core.settingsOpen = false

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.core.settingsOpen = false

        // ---- Sidebar: every widget and tool with its switch ----
        Rectangle {
            id: sidebar
            width: 270
            height: parent.height
            color: Qt.alpha(win.core.fg, 0.04)

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6

                Text {
                    text: "\u{F0493}  SCOTCHOS"
                    color: win.core.accent
                    font.family: win.core.font
                    font.pixelSize: 14
                    font.bold: true
                    bottomPadding: 10
                }

                Repeater {
                    model: win.items

                    Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool current: modelData.key === win.selected
                        readonly property bool on: win.core.enabled(modelData.key)
                        width: parent.width
                        height: 48
                        radius: 12
                        color: current ? Qt.alpha(win.core.accent, 0.18) : (area.containsMouse ? Qt.alpha(win.core.fg, 0.06) : "transparent")
                        border.width: current ? 1 : 0
                        border.color: Qt.alpha(win.core.accent, 0.35)

                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.selected = row.modelData.key
                        }

                        Text {
                            id: icon
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            text: row.modelData.icon
                            color: row.on ? win.core.accent : win.core.dim
                            font.family: win.core.font
                            font.pixelSize: 18
                        }
                        Column {
                            anchors.left: icon.right
                            anchors.leftMargin: 8
                            anchors.right: toggle.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: parent.width
                                text: row.modelData.name
                                elide: Text.ElideRight
                                color: win.core.fg
                                font.family: win.core.font
                                font.pixelSize: 13
                            }
                            Text {
                                text: row.modelData.kind + " · " + (row.on ? "on" : "off")
                                color: win.core.dim
                                font.family: win.core.font
                                font.pixelSize: 10
                            }
                        }
                        Toggle {
                            id: toggle
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            shell: win.core
                            on: row.on
                            onToggled: win.core.setConf("enabled", row.modelData.key, row.on ? "no" : "yes")
                        }
                    }
                }
            }

            // Opens the file in the default editor, for what the window doesn't cover.
            Choice {
                anchors.left: parent.left
                anchors.bottom: footer.top
                anchors.leftMargin: 16
                anchors.bottomMargin: 10
                shell: win.core
                options: ["Open scotchos.conf"]
                onPicked: openConf.running = true
            }
            Process {
                id: openConf
                command: ["xdg-open", win.core.confPath]
            }

            Text {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                text: "Saved to " + win.core.confPath.replace(Quickshell.env("HOME"), "~") + " as you click.\nEsc closes."
                wrapMode: Text.WordWrap
                color: win.core.dim
                font.family: win.core.font
                font.pixelSize: 10
            }
        }

        // ---- The selected item's settings ----
        Flickable {
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 24
            contentHeight: detail.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: detail
                width: parent.width
                spacing: 18

                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: win.item.icon + "  " + win.item.name
                        color: win.core.fg
                        font.family: win.core.font
                        font.pixelSize: 18
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: win.item.about
                        wrapMode: Text.WordWrap
                        color: win.core.dim
                        font.family: win.core.font
                        font.pixelSize: 12
                    }
                }

                Text {
                    visible: win.item.settings.length === 0
                    width: parent.width
                    text: "Nothing to set here besides the switch."
                    wrapMode: Text.WordWrap
                    color: win.core.dim
                    font.family: win.core.font
                    font.pixelSize: 12
                }

                Repeater {
                    model: win.item.settings

                    Column {
                        id: setting
                        required property var modelData
                        readonly property string current: win.value(win.item.key, modelData)
                        function save(v) { win.core.setConf(win.item.key, modelData.key, v) }
                        // Only for a line the conf holds with a non-default value; buttons have no value.
                        readonly property bool changed: modelData.type !== "action"
                            && win.core.conf[win.item.key]?.[modelData.key] !== undefined
                            && current !== String(modelData.def)
                        spacing: 8

                        Row {
                            spacing: 10
                            Text {
                                text: setting.modelData.label.toUpperCase()
                                color: win.core.accent
                                font.family: win.core.font
                                font.pixelSize: 11
                                font.letterSpacing: 1
                            }
                            // Removes the line, so the widget's fallback (the same as `def`) applies.
                            Text {
                                visible: setting.changed
                                text: "\u{F0E2}  reset"
                                color: resetArea.containsMouse ? win.core.fg : win.core.dim
                                font.family: win.core.font
                                font.pixelSize: 11
                                MouseArea {
                                    id: resetArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.core.removeConf(win.item.key, setting.modelData.key)
                                }
                            }
                        }
                        Loader {
                            sourceComponent: ({ choice: choice, position: position, number: number, flag: flag, text: textField, action: action })[setting.modelData.type]

                            Component {
                                id: choice
                                Choice {
                                    shell: win.core
                                    options: setting.modelData.options
                                    value: setting.current
                                    onPicked: v => setting.save(v)
                                }
                            }
                            Component {
                                id: position
                                PositionGrid {
                                    shell: win.core
                                    positions: win.core.positions
                                    allowAuto: setting.modelData.auto ?? false
                                    value: setting.current
                                    onPicked: v => setting.save(v)
                                }
                            }
                            Component {
                                id: number
                                Stepper {
                                    shell: win.core
                                    value: parseInt(setting.current) || 0
                                    min: setting.modelData.min
                                    max: setting.modelData.max
                                    step: setting.modelData.step
                                    unit: setting.modelData.unit
                                    onEdited: v => setting.save(v)
                                }
                            }
                            Component {
                                id: textField
                                Field {
                                    shell: win.core
                                    value: setting.current
                                    placeholder: setting.modelData.placeholder ?? ""
                                    secret: setting.modelData.secret ?? false
                                    onEdited: v => setting.save(v)
                                }
                            }
                            // A button: no conf value, just tells the widget (root's `action` signal).
                            Component {
                                id: action
                                Choice {
                                    shell: win.core
                                    options: [setting.modelData.text]
                                    onPicked: win.core.action(win.item.key, setting.modelData.action)
                                }
                            }
                            Component {
                                id: flag
                                Toggle {
                                    shell: win.core
                                    on: win.core.isYes(setting.current)
                                    onToggled: setting.save(on ? "no" : "yes")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
