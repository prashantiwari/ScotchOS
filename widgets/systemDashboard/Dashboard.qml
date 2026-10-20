// The dashboard card: rings, history graphs (CPU, temperature, network), GPU and top processes.
// Stacked in one column (vertical), side by side in one row (horizontal), or rings on top of
// two columns split by a divider: CPU and top processes | network and GPU (square).
// The square layout also has a clock beside the rings.
import QtQuick
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: card
    required property var shell
    readonly property var s: shell.stats
    readonly property bool horizontal: shell.layout === "horizontal"
    readonly property bool square: shell.layout === "square"
    readonly property real sectionWidth: horizontal ? 200 : 260
    readonly property real netWidth: horizontal ? 250 : 260   // room for both readings beside the title
    readonly property real graphHeight: horizontal ? 132 : 64

    // Where each section sits in each layout: [row, column, rowSpan, columnSpan].
    readonly property var cells: ({
        vertical:   { rings: [0, 0, 1, 1], cpu: [1, 0, 1, 1], temp: [2, 0, 1, 1], net: [3, 0, 1, 1], gpu: [4, 0, 1, 1], top: [5, 0, 1, 1] },
        horizontal: { rings: [0, 0, 2, 1], cpu: [0, 1, 2, 1], temp: [0, 2, 2, 1], net: [0, 3, 2, 1], gpu: [0, 4, 1, 1], top: [1, 4, 1, 1] },
        square:     { rings: [0, 0, 1, 1], clock: [0, 2, 1, 1], cpu: [1, 0, 1, 1], temp: [2, 0, 1, 1], top: [3, 0, 1, 1], divider: [1, 1, 3, 1],
                      net: [1, 2, 2, 1], gpu: [3, 2, 1, 1] },
    })[shell.layout]
    function cell(name) { return cells[name] || [0, 0, 1, 1] }

    width: content.width + 40
    height: content.implicitHeight + 40
    radius: 18
    color: Qt.alpha(shell.bg, 0.78)
    border { width: 1; color: Qt.alpha(shell.accent, 0.35) }

    function fmtUptime(sec) {
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        return "up " + (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
    }
    function fmtTemp(t) { return t === null || t === undefined ? "--" : Math.round(t) + "°C" }

    component SectionTitle: Text {
        color: card.shell.dim
        font { family: card.shell.font; pixelSize: 10; bold: true; letterSpacing: 1.5 }
    }

    // Graph title on the left, live readings on the right.
    component GraphHeader: Item {
        property alias title: titleText.text
        default property alias readings: readingsRow.data
        width: parent.width
        height: titleText.height
        SectionTitle { id: titleText }
        Row {
            id: readingsRow
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 10
        }
    }

    // A reading in a graph header: a colored dot (the legend), a name and the current value.
    component LegendItem: Row {
        property string name
        property string value
        property color tint: card.shell.fg
        spacing: 4
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 6; height: 6; radius: 3
            color: parent.tint
        }
        Text {
            text: parent.name
            visible: text !== ""
            color: card.shell.dim
            font { family: card.shell.font; pixelSize: 10 }
        }
        Text {
            text: parent.value
            color: parent.tint
            font { family: card.shell.font; pixelSize: 10; bold: true }
        }
    }

    // A labelled horizontal bar for `value` (0..1), with its reading on the right.
    component Meter: Item {
        property string name
        property real value
        property string valueText
        width: parent.width
        height: 16
        Text {
            id: meterName
            width: 38
            anchors.verticalCenter: parent.verticalCenter
            text: parent.name
            color: card.shell.dim
            font { family: card.shell.font; pixelSize: 10; bold: true; letterSpacing: 1 }
        }
        Text {
            id: meterValue
            width: 92
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            horizontalAlignment: Text.AlignRight
            text: parent.valueText
            color: card.shell.fg
            font { family: card.shell.font; pixelSize: 11; bold: true }
        }
        Rectangle {
            anchors { left: meterName.right; right: meterValue.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            height: 6
            radius: 3
            color: Qt.alpha(card.shell.accentDim, 0.5)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, parent.parent.value))
                height: parent.height
                radius: 3
                color: card.shell.accent
            }
        }
    }

    // A name on the left and a value on the right.
    component StatRow: Item {
        property string name
        property string value
        width: parent.width
        height: 17
        Text {
            width: parent.width - 60
            elide: Text.ElideRight
            text: parent.name
            color: card.shell.fg
            font { family: card.shell.font; pixelSize: 11 }
        }
        Text {
            anchors.right: parent.right
            text: parent.value
            color: card.shell.accent
            font { family: card.shell.font; pixelSize: 11; bold: true }
        }
    }

    Column {
        id: content
        x: 20; y: 20
        width: body.implicitWidth
        spacing: 14

        // Header
        Item {
            width: parent.width
            height: 22
            Text {
                text: "\uf2db  SYSTEM"
                color: card.shell.accent
                font { family: card.shell.font; pixelSize: 14; bold: true; letterSpacing: 2 }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: card.s ? card.fmtUptime(card.s.uptime) : ""
                color: card.shell.dim
                font { family: card.shell.font; pixelSize: 11 }
            }
        }

        // The sections, placed by `cells`
        GridLayout {
            id: body
            columnSpacing: card.square ? 20 : 18
            rowSpacing: 14

            // Rings
            Row {
                id: rings
                Layout.row: card.cell("rings")[0]; Layout.column: card.cell("rings")[1]
                Layout.rowSpan: card.cell("rings")[2]; Layout.columnSpan: card.cell("rings")[3]
                Layout.alignment: Qt.AlignCenter
                spacing: 14
                Ring {
                    value: card.s ? card.s.cpu / 100 : 0
                    valueText: card.s ? Math.round(card.s.cpu) + "%" : "--"
                    label: "CPU"
                    subText: card.s && card.s.mhz ? (card.s.mhz / 1000).toFixed(1) + " GHz" : ""
                    color: card.shell.accent; trackColor: Qt.alpha(card.shell.accentDim, 0.5)
                    textColor: card.shell.fg; dimColor: card.shell.dim; font: card.shell.font
                }
                Ring {
                    value: card.s ? card.s.mem.used / card.s.mem.total : 0
                    valueText: card.s ? Math.round(100 * card.s.mem.used / card.s.mem.total) + "%" : "--"
                    label: "RAM"
                    subText: card.s ? card.s.mem.used.toFixed(1) + " / " + Math.round(card.s.mem.total) + " G" : ""
                    color: card.shell.accent; trackColor: Qt.alpha(card.shell.accentDim, 0.5)
                    textColor: card.shell.fg; dimColor: card.shell.dim; font: card.shell.font
                }
                Ring {
                    readonly property var t: card.s ? card.s.temps.cpu : null
                    value: t === null ? 0 : (t - 30) / 70           // 30..100 °C
                    valueText: card.fmtTemp(t)
                    label: "TEMP"
                    subText: "package"
                    color: card.shell.tempColor(t); trackColor: Qt.alpha(card.shell.accentDim, 0.5)
                    textColor: card.shell.fg; dimColor: card.shell.dim; font: card.shell.font
                }
            }

            // Clock (square layout only): 24-hour time in the space of a ring's circle, then the
            // day and date in the place of a ring's label and sub-text, so it's as tall as the rings.
            Item {
                visible: card.square
                Layout.row: card.cell("clock")[0]; Layout.column: card.cell("clock")[1]
                Layout.preferredWidth: card.netWidth
                Layout.preferredHeight: rings.height

                SystemClock {
                    id: clock
                    enabled: card.square
                    precision: SystemClock.Minutes
                }

                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.top; verticalCenterOffset: 38 }
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: card.shell.accent   // the wallbash accent, like the rings' arcs
                    font { family: card.shell.font; pixelSize: 74; bold: true }
                }
                Column {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    spacing: 1
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "dddd").toUpperCase()
                        color: card.shell.fg
                        font { family: card.shell.font; pixelSize: 11; bold: true; letterSpacing: 1.5 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "d MMMM yyyy")
                        color: card.shell.dim
                        font { family: card.shell.font; pixelSize: 10 }
                    }
                }
            }

            // CPU history
            Column {
                id: cpuSection
                Layout.row: card.cell("cpu")[0]; Layout.column: card.cell("cpu")[1]
                Layout.rowSpan: card.cell("cpu")[2]; Layout.columnSpan: card.cell("cpu")[3]
                Layout.preferredWidth: card.sectionWidth
                spacing: 6
                GraphHeader {
                    title: "CPU USAGE · 60s"
                    LegendItem {
                        value: card.s ? Math.round(card.s.cpu) + "%" : "--"
                        tint: card.shell.accent
                    }
                }
                Graph {
                    width: parent.width; height: card.graphHeight
                    values: card.shell.cpuHistory
                    label: v => Math.round(v) + "%"
                    color: card.shell.accent
                    gridColor: Qt.alpha(card.shell.fg, 0.08)
                    labelColor: card.shell.dim
                    fontFamily: card.shell.font
                }
            }

            // Temperature history
            Column {
                id: tempSection
                Layout.row: card.cell("temp")[0]; Layout.column: card.cell("temp")[1]
                Layout.rowSpan: card.cell("temp")[2]; Layout.columnSpan: card.cell("temp")[3]
                Layout.preferredWidth: card.sectionWidth
                spacing: 6
                GraphHeader {
                    title: "CPU TEMP · 60s"
                    LegendItem {
                        value: card.fmtTemp(card.s ? card.s.temps.cpu : null)
                        tint: card.shell.tempColor(card.s ? card.s.temps.cpu : null)
                    }
                }
                Graph {
                    width: parent.width; height: card.graphHeight
                    values: card.shell.tempHistory
                    min: 30; max: 100
                    label: v => Math.round(v) + "°C"
                    color: card.shell.tempColor(card.s ? card.s.temps.cpu : null)
                    gridColor: Qt.alpha(card.shell.fg, 0.08)
                    labelColor: card.shell.dim
                    fontFamily: card.shell.font
                }
            }

            // Network history: download in the accent color, upload in the text color
            Column {
                Layout.row: card.cell("net")[0]; Layout.column: card.cell("net")[1]
                Layout.rowSpan: card.cell("net")[2]; Layout.columnSpan: card.cell("net")[3]
                Layout.preferredWidth: card.netWidth
                spacing: 6
                GraphHeader {
                    id: netHeader
                    title: "NET · 60s"
                    LegendItem {
                        name: "down"
                        value: card.s ? card.shell.fmtRate(card.s.net.rx) : "--"
                        tint: card.shell.accent
                    }
                    LegendItem {
                        name: "up"
                        value: card.s ? card.shell.fmtRate(card.s.net.tx) : "--"
                        tint: card.shell.fg
                    }
                }
                Graph {
                    width: parent.width
                    // In the square layout it fills the height of the CPU and temperature graphs beside it.
                    height: card.square ? cpuSection.height + tempSection.height + body.rowSpacing - netHeader.height - 6
                                        : card.graphHeight
                    values: card.shell.rxHistory
                    values2: card.shell.txHistory
                    max: 64 * 1024                                  // scale floor, so idle traffic stays flat
                    autoMax: true
                    label: v => v ? card.shell.fmtRate(v).replace(" ", "").replace("/s", "") : "0"
                    color: card.shell.accent
                    color2: Qt.alpha(card.shell.fg, 0.8)
                    gridColor: Qt.alpha(card.shell.fg, 0.08)
                    labelColor: card.shell.dim
                    fontFamily: card.shell.font
                }
            }

            // Divider between CPU and top processes | network and GPU (square layout only)
            Rectangle {
                visible: card.square
                Layout.row: card.cell("divider")[0]; Layout.column: card.cell("divider")[1]
                Layout.rowSpan: card.cell("divider")[2]
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: Qt.alpha(card.shell.accent, 0.35)
            }

            // NVIDIA GPU (hidden when there's no NVIDIA driver; "asleep" while the card is runtime-suspended)
            Column {
                readonly property var g: card.s ? card.s.gpu : null
                id: gpuSection
                visible: g !== null
                Layout.row: card.cell("gpu")[0]; Layout.column: card.cell("gpu")[1]
                Layout.alignment: card.square ? Qt.AlignTop : Qt.AlignVCenter   // lines up with TOP PROCESSES
                Layout.preferredWidth: card.sectionWidth
                spacing: 6
                GraphHeader {
                    title: "GPU" + (gpuSection.g?.name ? " · " + gpuSection.g.name.toUpperCase() : "")
                    LegendItem {
                        value: card.fmtTemp(gpuSection.g ? gpuSection.g.temp : null)
                        tint: card.shell.tempColor(gpuSection.g ? gpuSection.g.temp : null)
                    }
                    LegendItem {
                        value: gpuSection.g && gpuSection.g.watts != null ? gpuSection.g.watts.toFixed(1) + " W" : "--"
                        tint: card.shell.fg
                    }
                }
                Meter {
                    name: "LOAD"
                    value: gpuSection.g && gpuSection.g.util != null ? gpuSection.g.util / 100 : 0
                    valueText: gpuSection.g?.asleep ? "asleep"
                               : gpuSection.g && gpuSection.g.util != null
                               ? gpuSection.g.util + "%" + (gpuSection.g.mhz ? " · " + (gpuSection.g.mhz / 1000).toFixed(1) + " GHz" : "")
                               : "--"
                }
                Meter {
                    name: "VRAM"
                    value: gpuSection.g && gpuSection.g.memUsed != null ? gpuSection.g.memUsed / gpuSection.g.memTotal : 0
                    valueText: gpuSection.g && gpuSection.g.memUsed != null
                               ? gpuSection.g.memUsed.toFixed(1) + " / " + Math.round(gpuSection.g.memTotal) + " G"
                               : "--"
                }
            }

            // Busiest processes (same-named processes summed), as % of the whole CPU
            Column {
                Layout.row: card.cell("top")[0]; Layout.column: card.cell("top")[1]
                Layout.preferredWidth: card.sectionWidth
                spacing: 4
                GraphHeader { title: "TOP PROCESSES" }
                // A fixed model of 3, so the rows are reused instead of rebuilt on every update.
                Repeater {
                    model: 3
                    StatRow {
                        required property int index
                        readonly property var p: card.s && card.s.top[index] ? card.s.top[index] : null
                        name: p ? p.name : ""
                        value: p ? p.cpu.toFixed(1) + "%" : ""
                    }
                }
            }
        }
    }
}
