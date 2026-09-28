import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: root

    required property var theme
    property bool chooserVisible: false
    property var targetScreen: null
    property var devices: []
    property int selectedIndex: 0

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

    function show(optionsEncoded) {
        var parsed;
        try {
            parsed = JSON.parse(Qt.atob(optionsEncoded));
        } catch (error) {
            parsed = [];
        }

        devices = [{
            "name": "__none__",
            "description": "Desktop audio only",
            "detail": "Do not record a microphone",
            "isDefault": false,
            "icon": "󰍭"
        }];

        for (var i = 0; i < parsed.length; ++i) {
            devices.push({
                "name": String(parsed[i].name || ""),
                "description": String(parsed[i].description || parsed[i].name || "Microphone"),
                "detail": parsed[i].isDefault ? "Default microphone" : "Microphone",
                "isDefault": Boolean(parsed[i].isDefault),
                "icon": "󰍬"
            });
        }

        selectedIndex = 0;
        for (var j = 1; j < devices.length; ++j) {
            if (devices[j].isDefault) {
                selectedIndex = j;
                break;
            }
        }

        targetScreen = focusedScreen();
        chooserVisible = true;
        Qt.callLater(function() {
            keyboardScope.forceActiveFocus();
            deviceList.positionViewAtIndex(selectedIndex, ListView.Contain);
        });
    }

    function finish(device) {
        if (!chooserVisible)
            return;
        chooserVisible = false;
        microphoneIpc.selected(device);
    }

    function cancel() {
        finish("__cancel__");
    }

    function moveSelection(delta) {
        if (devices.length === 0)
            return;
        selectedIndex = (selectedIndex + delta + devices.length) % devices.length;
        deviceList.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function activateSelected() {
        if (selectedIndex >= 0 && selectedIndex < devices.length)
            finish(devices[selectedIndex].name);
    }

    IpcHandler {
        id: microphoneIpc
        target: "microphoneChooser"

        signal selected(string device)

        function show(optionsEncoded: string): void {
            root.show(optionsEncoded);
        }

        function hide(): void {
            root.cancel();
        }

        function visible(): bool {
            return root.chooserVisible;
        }

        function deviceCount(): int {
            return root.devices.length;
        }

        function selectedDevice(): string {
            if (root.selectedIndex < 0 || root.selectedIndex >= root.devices.length)
                return "";
            return root.devices[root.selectedIndex].name;
        }
    }

    PanelWindow {
        id: chooserWindow

        screen: root.targetScreen
        visible: root.chooserVisible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell-microphone-chooser"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.chooserVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        HyprlandFocusGrab {
            active: root.chooserVisible
            windows: [chooserWindow]
            onCleared: root.cancel()
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.theme.base.r, root.theme.base.g, root.theme.base.b, 0.58)

            MouseArea {
                anchors.fill: parent
                onClicked: root.cancel()
            }

            Rectangle {
                id: card

                anchors.centerIn: parent
                width: Math.min(520, chooserWindow.width - 40)
                height: Math.min(130 + root.devices.length * 62, chooserWindow.height - 80)
                radius: root.theme.radius + 4
                color: root.theme.base
                border.width: 1
                border.color: root.theme.surface1
                clip: true

                MouseArea {
                    anchors.fill: parent
                }

                FocusScope {
                    id: keyboardScope

                    anchors.fill: parent
                    focus: root.chooserVisible
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            root.cancel();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                            root.moveSelection(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                            root.moveSelection(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            if (!event.isAutoRepeat)
                                root.activateSelected();
                            event.accepted = true;
                        }
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 14

                        Row {
                            width: parent.width
                            spacing: 12

                            Text {
                                width: 34
                                text: "󰕾"
                                color: root.theme.mauve
                                font.family: root.theme.fontFamily
                                font.pixelSize: 24
                                horizontalAlignment: Text.AlignHCenter
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: parent.width - 46
                                spacing: 2

                                Text {
                                    text: "Recording audio"
                                    color: root.theme.text
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.fontSize + 3
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: "Choose a microphone for this recording"
                                    color: root.theme.subtext
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.fontSize - 1
                                }
                            }
                        }

                        ListView {
                            id: deviceList

                            width: parent.width
                            height: parent.height - 66
                            spacing: 6
                            clip: true
                            model: root.devices
                            currentIndex: root.selectedIndex

                            delegate: Rectangle {
                                id: deviceRow

                                required property var modelData
                                required property int index

                                width: deviceList.width
                                height: 56
                                radius: root.theme.radius
                                color: index === root.selectedIndex ? root.theme.surfaceSolid : (rowMouse.containsMouse ? root.theme.surface : "transparent")
                                border.width: index === root.selectedIndex ? 1 : 0
                                border.color: root.theme.mauve

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 12

                                    Text {
                                        width: 28
                                        text: deviceRow.modelData.icon
                                        color: deviceRow.index === root.selectedIndex ? root.theme.mauve : root.theme.subtext
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: 20
                                        horizontalAlignment: Text.AlignHCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Column {
                                        width: parent.width - 100
                                        spacing: 2
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            width: parent.width
                                            text: deviceRow.modelData.description
                                            color: root.theme.text
                                            elide: Text.ElideRight
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: root.theme.fontSize
                                            font.weight: deviceRow.index === root.selectedIndex ? Font.DemiBold : Font.Normal
                                        }

                                        Text {
                                            text: deviceRow.modelData.detail
                                            color: root.theme.subtext
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: root.theme.fontSize - 2
                                        }
                                    }

                                    Text {
                                        width: 36
                                        text: deviceRow.index === root.selectedIndex ? "󰄬" : ""
                                        color: root.theme.green
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: 18
                                        horizontalAlignment: Text.AlignRight
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: rowMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: root.selectedIndex = deviceRow.index
                                    onClicked: root.finish(deviceRow.modelData.name)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
