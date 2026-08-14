import QtQuick
import "../components"

Pill {
    id: root

    required property var bar
    property string icon: ""
    property string text: ""
    property string tooltip: ""
    property color foreground: bar.theme.text
    property bool hideWhenEmpty: false
    property bool actionable: false
    property real maxTextWidth: Number.POSITIVE_INFINITY
    signal activated()

    theme: bar.theme
    visible: !hideWhenEmpty || text !== ""

    ModuleButton {
        bar: root.bar
        theme: root.theme
        text: root.icon + (root.text ? "  " + root.text : "")
        tooltip: root.tooltip
        foreground: root.foreground
        horizontalPadding: 2
        actionable: root.actionable
        acceptedButtons: Qt.LeftButton
        maxTextWidth: root.maxTextWidth
        onClicked: function(button) { if (button === Qt.LeftButton) root.activated() }
    }
}
