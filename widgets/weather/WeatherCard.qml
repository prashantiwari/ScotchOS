// The weather card: header, current conditions, the next 24 hours as a curve, and the coming days.
import QtQuick

Rectangle {
    id: card
    required property var shell
    readonly property var cur: shell.data?.current ?? null
    readonly property var today: shell.data ? shell.day(0) : null
    readonly property real contentWidth: 340

    width: content.width + 40
    height: content.implicitHeight + 40
    radius: 18
    color: Qt.alpha(shell.bg, 0.78)
    border { width: 1; color: Qt.alpha(shell.accent, 0.35) }

    function t(v) { return Math.round(v) + card.shell.deg }

    Column {
        id: content
        x: 20; y: 20
        width: card.contentWidth
        spacing: 14

        // ---- Header: title, place and fetch time ----
        Item {
            width: parent.width
            height: 22
            Text {
                id: title
                text: "\u{F0590}  WEATHER"
                color: card.shell.accent
                font { family: card.shell.font; pixelSize: 14; bold: true; letterSpacing: 2 }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; left: title.right; leftMargin: 12 }
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: (card.shell.city ? "\u{F034E} " + card.shell.city + "   " : "")
                      + (card.shell.fetchedAt ? Qt.formatDateTime(new Date(card.shell.fetchedAt), "HH:mm") : "")
                color: card.shell.dim
                font { family: card.shell.font; pixelSize: 11 }
            }
        }

        // ---- Placeholder until the first reply ----
        Text {
            visible: !card.cur
            width: parent.width
            wrapMode: Text.Wrap
            text: card.shell.error ? card.shell.error + ". Retrying in a few minutes." : "Fetching the weather…"
            color: card.shell.dim
            font { family: card.shell.font; pixelSize: 13 }
        }

        // ---- Now: icon and temperature, condition and details, today's range and the sun ----
        Item {
            visible: card.cur !== null
            width: parent.width
            height: 64

            Text {
                id: bigIcon
                anchors.verticalCenter: parent.verticalCenter
                text: card.cur ? card.shell.icon(card.cur.weather_code, card.cur.is_day) : ""
                color: card.shell.accent
                font { family: card.shell.font; pixelSize: 50 }
            }
            Text {
                id: bigTemp
                anchors { left: bigIcon.right; leftMargin: 12; top: parent.top; topMargin: -2 }
                text: card.cur ? card.t(card.cur.temperature_2m) : ""
                color: card.shell.fg
                font { family: card.shell.font; pixelSize: 34; bold: true }
            }
            Text {
                anchors { left: bigTemp.left; top: bigTemp.bottom; topMargin: -2 }
                text: card.cur ? card.shell.describe(card.cur.weather_code)[0] + " · feels " + card.t(card.cur.apparent_temperature) : ""
                color: card.shell.dim
                font { family: card.shell.font; pixelSize: 11 }
            }

            Column {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 3
                Repeater {
                    // [icon, text]: fixed rows, only their text changes
                    model: card.today && card.cur ? [
                        ["\u{F005D}", card.t(card.today.max) + "  \u{F0045} " + card.t(card.today.min)],
                        ["\u{F058C}", card.cur.relative_humidity_2m + "%   \u{F059D} " + Math.round(card.cur.wind_speed_10m) + " " + card.shell.windUnit],
                        ["\u{F059C}", card.shell.hhmm(card.today.sunrise) + "  \u{F059B} " + card.shell.hhmm(card.today.sunset)],
                    ] : []
                    Text {
                        required property var modelData
                        anchors.right: parent.right
                        text: modelData[0] + " " + modelData[1]
                        color: card.shell.fg
                        font { family: card.shell.font; pixelSize: 11 }
                    }
                }
            }
        }

        // ---- Next 24 hours ----
        TempCurve {
            visible: card.shell.showHourly && card.shell.hours.length > 1
            width: parent.width
            shell: card.shell
        }

        // ---- Coming days ----
        Row {
            visible: card.cur !== null
            width: parent.width
            Repeater {
                model: card.shell.days
                Column {
                    id: dayCol
                    required property int index
                    readonly property var d: card.shell.data ? card.shell.day(index) : null
                    width: card.contentWidth / card.shell.days
                    spacing: 3
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !dayCol.d ? "" : dayCol.index === 0 ? "Today"
                              : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][card.shell.local(dayCol.d.t).getUTCDay()]
                        color: dayCol.index === 0 ? card.shell.accent : card.shell.dim
                        font { family: card.shell.font; pixelSize: 11; bold: dayCol.index === 0 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dayCol.d ? card.shell.icon(dayCol.d.code, true) : ""
                        color: card.shell.fg
                        font { family: card.shell.font; pixelSize: 22 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dayCol.d ? Math.round(dayCol.d.max) + "°" : ""
                        color: card.shell.fg
                        font { family: card.shell.font; pixelSize: 12; bold: true }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dayCol.d ? Math.round(dayCol.d.min) + "°" : ""
                        color: card.shell.dim
                        font { family: card.shell.font; pixelSize: 11 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Rain chance only when it's worth a look
                        opacity: dayCol.d && dayCol.d.rain >= 20 ? 1 : 0
                        text: dayCol.d ? "\u{F058C}" + dayCol.d.rain + "%" : ""
                        color: card.shell.accent
                        font { family: card.shell.font; pixelSize: 10 }
                    }
                }
            }
        }
    }
}
