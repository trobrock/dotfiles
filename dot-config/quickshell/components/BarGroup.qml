import QtQuick

Rectangle {
    id: root

    property var theme
    property bool flat: false
    property int horizontalPadding: flat ? 0 : 3
    property int itemSpacing: flat ? 3 : 1
    // data accepts modules that also own detached PopupWindow objects.
    default property alias content: holder.data

    implicitWidth: holder.implicitWidth + horizontalPadding * 2
    implicitHeight: flat ? 27 : 29
    radius: theme ? theme.radius : 10
    color: flat ? "transparent" : theme ? theme.surface : "#99313244"
    border.width: flat ? 0 : 1
    border.color: theme ? theme.surface1 : "#45475a"

    Row {
        id: holder

        anchors.centerIn: parent
        spacing: root.itemSpacing
    }
}
