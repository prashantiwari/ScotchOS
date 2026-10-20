// A card's window on one screen: on the desktop layer (above the wallpaper, below windows), never focused,
// clicks pass through, placed by `place` and the margins. Use one per screen inside `Variants`.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    required property var modelData
    required property string layerName     // layer-shell namespace, e.g. "scotchos-quote"
    property string place: "center"
    property int marginX: 20
    property int marginY: 20

    screen: modelData

    WlrLayershell.layer: WlrLayer.Bottom          // above wallpaper, below windows
    WlrLayershell.namespace: layerName
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal          // stay clear of waybar, reserve nothing
    exclusiveZone: 0
    mask: Region {}                              // clicks pass through to the desktop

    // Anchor to the edges named in `place`; on an axis with no anchor the compositor centers the card.
    anchors.left: place.includes("left")
    anchors.right: place.includes("right")
    anchors.top: place.startsWith("top")
    anchors.bottom: place.startsWith("bottom")
    margins.left: marginX
    margins.right: marginX
    margins.top: marginY
    margins.bottom: marginY
    color: "transparent"
}
