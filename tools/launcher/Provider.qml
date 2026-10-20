// One source of launcher results. Add a feature by writing a Provider and listing it in Launcher.qml.
//   keywords : words (or symbols) that select this provider, e.g. "yt" or ">"; Tab turns one into a chip
//   inDefault: also searched when nothing is selected, so its rows mix into the plain list
//   search   : query -> rows, used with the keyword/chip, and in the plain list when inDefault
//   fallback : query -> rows that close the plain list (e.g. "Search YouTube for ...")
// A row is { title, subtitle, glyph | iconName, run(), alt() }; alt runs on Shift+Enter, altHint says what it does.
import QtQuick

QtObject {
    property var core
    property string name
    property string glyph
    property string placeholder
    property var keywords: []
    property bool inDefault: false
    property var search: q => []
    property var fallback: q => []
}
