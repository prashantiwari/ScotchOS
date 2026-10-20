// Base for every desktop widget. Re-exposes the shared colors and empty-workspace check from shell.qml,
// so a card can use `shell.bg`, `shell.font`, … with the widget as its `shell`, and reads the widget's
// [section] of scotchos.conf.
import QtQuick
import Quickshell

Scope {
    required property var core          // the ShellRoot in shell.qml
    required property string section    // this widget's [section] in scotchos.conf

    readonly property color bg: core.bg
    readonly property color fg: core.fg
    readonly property color accent: core.accent
    readonly property color accentDim: core.accentDim
    readonly property color dim: core.dim
    readonly property string font: core.font

    readonly property bool anyEmpty: core.anyEmpty
    function workspaceEmpty(screen) { return core.workspaceEmpty(screen) }

    // ---- Settings ----
    readonly property var conf: core.conf[section] ?? ({})

    // A string setting; with `allowed`, anything else falls back (with a warning).
    function str(key, fallback, allowed) {
        const v = conf[key] ?? fallback;
        if (allowed && !allowed.includes(v)) {
            console.warn("scotchos.conf: [" + section + "]", key, "=", v, "isn't known - using", fallback);
            return fallback;
        }
        return v;
    }
    function num(key, fallback) {
        const n = parseInt(conf[key] ?? fallback);
        return isNaN(n) ? fallback : n;
    }
    function flag(key, fallback) { return core.isYes(conf[key] ?? (fallback ? "yes" : "no")) }

    // Position and margins, which every card has.
    function placeSetting(fallback) { return str("position", fallback, core.positions) }
    readonly property int marginX: num("margin_x", 20)
    readonly property int marginY: num("margin_y", 20)
}
