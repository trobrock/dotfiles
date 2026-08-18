import QtQuick

Item {
    id: root

    property real iconSize: 15
    property color foreground: "white"
    property color badgeColor: "#f38ba8"
    property bool crossed: false
    property bool warning: false

    implicitWidth: iconSize
    implicitHeight: iconSize

    readonly property real dotSize: Math.max(2, iconSize * 0.24)
    readonly property real middle: (iconSize - dotSize) / 2
    readonly property real end: iconSize - dotSize

    Dot { x: 0; y: 0; opacity: 0.24 }
    Dot { x: root.middle; y: 0; opacity: 0.24 }
    Dot { x: root.end; y: 0; opacity: 0.24 }
    Dot { x: 0; y: root.middle }
    Dot { x: root.middle; y: root.middle }
    Dot { x: root.end; y: root.middle }
    Dot { x: 0; y: root.end; opacity: 0.24 }
    Dot { x: root.middle; y: root.end }
    Dot { x: root.end; y: root.end; opacity: 0.24 }

    Rectangle {
        visible: root.crossed
        anchors.centerIn: parent
        width: parent.width * 1.22
        height: Math.max(2, parent.height * 0.14)
        radius: height / 2
        color: root.foreground
        rotation: -45
    }

    Rectangle {
        visible: root.warning
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.max(7, parent.width * 0.44)
        height: width
        radius: width / 2
        color: root.badgeColor

        Text {
            anchors.centerIn: parent
            text: "!"
            textFormat: Text.PlainText
            color: root.foreground
            font.pixelSize: Math.max(6, parent.height * 0.72)
            font.bold: true
        }
    }

    component Dot: Rectangle {
        width: root.dotSize
        height: root.dotSize
        radius: width / 2
        color: root.foreground
    }
}
