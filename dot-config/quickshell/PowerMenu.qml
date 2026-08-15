import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: root

    required property var theme
    property bool powerMenuVisible: false
    property var targetScreen: null
    property int selectedIndex: 0
    property bool confirmationPending: false
    property int confirmationSelection: 0
    readonly property string selectedAction: actions[selectedIndex].action
    readonly property var actions: [{
            "action": "lock",
            "icon": "󰌾",
            "label": "Lock"
        }, {
            "action": "suspend",
            "icon": "󰤄",
            "label": "Suspend"
        }, {
            "action": "hibernate",
            "icon": "󰒲",
            "label": "Hibernate"
        }, {
            "action": "logout",
            "icon": "󰍃",
            "label": "Log out"
        }, {
            "action": "restart",
            "icon": "󰜉",
            "label": "Restart"
        }, {
            "action": "shutdown",
            "icon": "󰐥",
            "label": "Shut down"
        }]

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

    function show() {
        targetScreen = focusedScreen();
        selectedIndex = 0;
        confirmationPending = false;
        confirmationSelection = 0;
        confirmationGuard.stop();
        powerMenuVisible = true;
        Qt.callLater(function() {
            keyboardScope.forceActiveFocus();
        });
    }

    function hide() {
        if (!powerMenuVisible)
            return;
        powerMenuVisible = false;
        confirmationPending = false;
        confirmationSelection = 0;
        confirmationGuard.stop();
    }

    function toggle() {
        if (powerMenuVisible)
            hide();
        else
            show();
    }

    function moveSelection(delta) {
        selectedIndex = (selectedIndex + delta + actions.length) % actions.length;
    }

    function requestConfirmation() {
        confirmationPending = true;
        confirmationSelection = 0;
        confirmationGuard.restart();
    }

    function returnToActions() {
        confirmationPending = false;
        confirmationSelection = 0;
        confirmationGuard.stop();
    }

    function runImmediateAction(action) {
        hide();
        try {
            if (action === "lock")
                Quickshell.execDetached(["/usr/bin/hyprlock"]);
            else if (action === "suspend")
                Quickshell.execDetached(["/usr/bin/systemctl", "suspend"]);
            else if (action === "hibernate")
                Quickshell.execDetached(["/usr/bin/systemctl", "hibernate"]);
        } catch (error) {
        }
    }

    function runConfirmedAction(action) {
        hide();
        try {
            if (action === "logout")
                Quickshell.execDetached(["/usr/bin/uwsm", "stop"]);
            else if (action === "restart")
                Quickshell.execDetached(["/usr/bin/systemctl", "reboot"]);
            else if (action === "shutdown")
                Quickshell.execDetached(["/usr/bin/systemctl", "poweroff"]);
        } catch (error) {
        }
    }

    function activateSelected() {
        var action = selectedAction;
        if (action === "lock" || action === "suspend" || action === "hibernate")
            runImmediateAction(action);
        else
            requestConfirmation();
    }

    function activateConfirmation() {
        if (confirmationSelection === 1 && confirmationGuard.running)
            return;
        if (confirmationSelection === 0)
            returnToActions();
        else
            runConfirmedAction(selectedAction);
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "power-menu"
        description: "Show power and session menu"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "powerMenu"

        function show(): void {
            root.show();
        }

        function hide(): void {
            root.hide();
        }

        function toggle(): void {
            root.toggle();
        }

        function visible(): bool {
            return root.powerMenuVisible;
        }

        function selectedAction(): string {
            return root.selectedAction;
        }

        function confirmationPending(): bool {
            return root.confirmationPending;
        }
    }

    Timer {
        id: confirmationGuard

        interval: Qt.styleHints.mouseDoubleClickInterval + 100
    }

    PanelWindow {
        id: powerWindow

        screen: root.targetScreen
        visible: root.powerMenuVisible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell-power-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.powerMenuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        HyprlandFocusGrab {
            active: root.powerMenuVisible
            windows: [powerWindow]
            onCleared: root.hide()
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.theme.base.r, root.theme.base.g, root.theme.base.b, 0.58)

            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }

            Rectangle {
                id: card

                anchors.centerIn: parent
                width: Math.min(600, powerWindow.width - 40)
                height: Math.min(360, powerWindow.height - 80)
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
                    focus: root.powerMenuVisible
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            if (root.confirmationPending)
                                root.returnToActions();
                            else
                                root.hide();
                            event.accepted = true;
                            return;
                        }

                        if (root.confirmationPending) {
                            if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                                root.confirmationSelection = (root.confirmationSelection + 1) % 2;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                root.confirmationSelection = (root.confirmationSelection + 1) % 2;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                                if (!event.isAutoRepeat)
                                    root.activateConfirmation();
                                event.accepted = true;
                            }
                            return;
                        }

                        if (event.key === Qt.Key_Left) {
                            root.moveSelection(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Right) {
                            root.moveSelection(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            root.moveSelection(-3);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down) {
                            root.moveSelection(3);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                            var backwards = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
                            root.moveSelection(backwards ? -1 : 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            root.activateSelected();
                            event.accepted = true;
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: !root.confirmationPending

                        Text {
                            anchors.top: parent.top
                            anchors.topMargin: 24
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "POWER & SESSION"
                            textFormat: Text.PlainText
                            color: root.theme.overlay
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.5
                        }

                        Grid {
                            id: actionGrid

                            anchors.top: parent.top
                            anchors.topMargin: 60
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 24
                            anchors.rightMargin: 24
                            columns: 3
                            columnSpacing: 10
                            rowSpacing: 10

                            Repeater {
                                model: root.actions

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    width: (actionGrid.width - actionGrid.columnSpacing * 2) / 3
                                    height: 108
                                    radius: root.theme.radius
                                    color: index === root.selectedIndex ? root.theme.surfaceSolid : (actionHover.hovered ? Qt.rgba(root.theme.surface1.r, root.theme.surface1.g, root.theme.surface1.b, 0.55) : "transparent")
                                    border.width: index === root.selectedIndex ? 1 : 0
                                    border.color: root.theme.lavender
                                    Accessible.name: modelData.label

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.icon
                                            textFormat: Text.PlainText
                                            color: index < 3 ? root.theme.lavender : root.theme.peach
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: 27
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.label
                                            textFormat: Text.PlainText
                                            color: root.theme.text
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: 13
                                            font.bold: index === root.selectedIndex
                                        }
                                    }

                                    HoverHandler {
                                        id: actionHover
                                        onHoveredChanged: {
                                            if (hovered)
                                                root.selectedIndex = index;
                                        }
                                    }

                                    TapHandler {
                                        onTapped: {
                                            root.selectedIndex = index;
                                            root.activateSelected();
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 17
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Arrows / Tab  select    Enter  activate    Esc  close"
                            textFormat: Text.PlainText
                            color: root.theme.overlay
                            font.family: root.theme.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: root.confirmationPending

                        Column {
                            anchors.top: parent.top
                            anchors.topMargin: 45
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 12

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.actions[root.selectedIndex].icon
                                textFormat: Text.PlainText
                                color: root.theme.red
                                font.family: root.theme.fontFamily
                                font.pixelSize: 36
                            }

                            Text {
                                width: parent.width
                                text: "Confirm " + root.actions[root.selectedIndex].label.toLowerCase() + "?"
                                textFormat: Text.PlainText
                                color: root.theme.text
                                horizontalAlignment: Text.AlignHCenter
                                font.family: root.theme.fontFamily
                                font.pixelSize: 19
                                font.bold: true
                            }

                            Text {
                                width: parent.width
                                text: "This will end or interrupt your current session."
                                textFormat: Text.PlainText
                                color: root.theme.subtext
                                horizontalAlignment: Text.AlignHCenter
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                            }
                        }

                        Row {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 62
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12

                            Repeater {
                                model: [{
                                        "label": "Cancel",
                                        "confirm": false
                                    }, {
                                        "label": "Confirm",
                                        "confirm": true
                                    }]

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    width: 150
                                    height: 48
                                    radius: root.theme.radius
                                    color: index === root.confirmationSelection ? (modelData.confirm ? root.theme.red : root.theme.surface1) : root.theme.surfaceSolid
                                    border.width: index === root.confirmationSelection ? 1 : 0
                                    border.color: modelData.confirm ? root.theme.red : root.theme.lavender
                                    Accessible.name: modelData.label

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        textFormat: Text.PlainText
                                        color: index === root.confirmationSelection && modelData.confirm ? root.theme.base : root.theme.text
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: index === root.confirmationSelection
                                    }

                                    TapHandler {
                                        onTapped: {
                                            if (modelData.confirm && confirmationGuard.running)
                                                return;
                                            root.confirmationSelection = index;
                                            root.activateConfirmation();
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 18
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Cancel is selected by default    Esc  back"
                            textFormat: Text.PlainText
                            color: root.theme.overlay
                            font.family: root.theme.fontFamily
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }
}
