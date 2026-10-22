import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var service
    required property var theme
    property bool dismissed: false

    function focusedScreen() {
        var monitor = Hyprland.focusedMonitor;
        var screens = Quickshell.screens;
        if (monitor) {
            for (var i = 0; i < screens.length; ++i) {
                if (screens[i].name === monitor.name)
                    return screens[i];
            }
        }
        return screens.length > 0 ? screens[0] : null;
    }

    screen: focusedScreen()
    visible: service.signInRequired && !dismissed
    color: "transparent"
    implicitWidth: 410
    implicitHeight: 118
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    WlrLayershell.namespace: "quickshell-captive-portal"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        right: true
    }
    margins.top: 44
    margins.right: 14

    Connections {
        target: root.service
        function onStatusChanged() {
            if (!root.service.signInRequired)
                root.dismissed = false;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.theme.base
        border.width: 2
        border.color: root.theme.yellow

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.top: parent.top
            anchors.topMargin: 12
            text: "Wi-Fi sign-in required"
            textFormat: Text.PlainText
            color: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: 14
            font.bold: true
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: closeButton.left
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 37
            text: root.service.errorMessage || "This network needs you to accept terms or sign in."
            textFormat: Text.PlainText
            color: root.service.errorMessage ? root.theme.red : root.theme.subtext
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: 11
        }

        Rectangle {
            id: openButton
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            width: 112
            height: 30
            radius: 6
            color: openHover.hovered ? root.theme.blue : root.theme.lavender

            Text {
                anchors.centerIn: parent
                text: "Open sign-in"
                textFormat: Text.PlainText
                color: root.theme.base
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }
            HoverHandler { id: openHover }
            TapHandler { onTapped: root.service.openPortal() }
        }

        Rectangle {
            anchors.left: openButton.right
            anchors.leftMargin: 8
            anchors.bottom: openButton.bottom
            width: 92
            height: 30
            radius: 6
            color: checkHover.hovered ? root.theme.surface1 : root.theme.surfaceSolid

            Text {
                anchors.centerIn: parent
                text: "Check again"
                textFormat: Text.PlainText
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 11
            }
            HoverHandler { id: checkHover }
            TapHandler { onTapped: root.service.checkAgain() }
        }

        Rectangle {
            id: closeButton
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 8
            width: 28
            height: 28
            radius: 6
            color: closeHover.hovered ? root.theme.surface1 : "transparent"

            Text {
                anchors.centerIn: parent
                text: "×"
                color: root.theme.subtext
                font.family: root.theme.fontFamily
                font.pixelSize: 17
            }
            HoverHandler { id: closeHover }
            TapHandler { onTapped: root.dismissed = true }
        }
    }
}
