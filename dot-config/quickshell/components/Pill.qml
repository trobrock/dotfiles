import QtQuick

Rectangle {
    id: root
    property var theme
    property color accent: theme ? theme.text : "white"
    property bool embedded: false
    // data accepts both visual children and non-Item objects such as PopupWindow.
    default property alias content: holder.data

    implicitWidth: holder.implicitWidth + (embedded ? 4 : 20)
    implicitHeight: 27
    radius: theme ? theme.radius : 10
    color: embedded ? "transparent" : theme ? theme.surface : "#99313244"
    border.width: embedded ? 0 : 1
    border.color: theme ? theme.surface1 : "#45475a"

    Row {
        id: holder
        anchors.centerIn: parent
        spacing: root.embedded ? 1 : 7
    }
}
