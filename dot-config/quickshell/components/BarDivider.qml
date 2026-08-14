import QtQuick

Item {
    id: root

    property var theme

    implicitWidth: 7
    implicitHeight: 27

    Rectangle {
        anchors.centerIn: parent
        width: 1
        height: 14
        color: root.theme ? root.theme.surface1 : "#45475a"
    }
}
