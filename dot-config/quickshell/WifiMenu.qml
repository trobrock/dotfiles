import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: root

    required property var theme
    required property var service
    property bool menuVisible: false
    property var targetScreen: null
    property int selectedIndex: 0
    property var promptNetwork: null
    property bool confirmationPending: false
    property int confirmationSelection: 0
    property string confirmationId: ""
    property string confirmationName: ""
    readonly property var networkRows: buildRows()
    readonly property int networkCount: networkRows.length
    readonly property int visibleNetworkRows: Math.min(networkCount, 7)
    readonly property int navigationCount: networkCount + 2
    readonly property string selectedState: selectionState()

    function buildRows() {
        var source = service && Array.isArray(service.networks) ? service.networks : [];
        return source.slice(0, 50);
    }

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

    function showOnScreen(screen) {
        targetScreen = screen || focusedScreen();
        selectedIndex = 0;
        clearPrompt();
        clearConfirmation();
        menuVisible = true;
        Qt.callLater(function() {
            keyboardScope.forceActiveFocus();
        });
    }

    function show() {
        showOnScreen(null);
    }

    function hide() {
        if (!menuVisible)
            return;
        clearPrompt();
        clearConfirmation();
        menuVisible = false;
    }

    function toggle() {
        if (menuVisible)
            hide();
        else
            show();
    }

    function networkById(id) {
        for (var i = 0; i < networkRows.length; ++i) {
            if (networkRows[i].id === id)
                return networkRows[i];
        }
        return null;
    }

    function selectedNetwork() {
        var row = selectedIndex - 2;
        return row >= 0 && row < networkRows.length ? networkRows[row] : null;
    }

    function supported(network) {
        return !!network && (network.type === "open" || network.type === "psk");
    }

    function networkStatus(network) {
        if (!network)
            return "Unsupported";
        if (network.connected)
            return "Connected";
        if (!supported(network))
            return network.type === "8021x" ? "Enterprise" : "Unsupported";
        if (network.known)
            return "Saved";
        return network.type === "open" ? "Open" : "Secured";
    }

    function typeIcon(network) {
        if (!network)
            return "?";
        if (network.type === "open")
            return "󰖩";
        if (network.type === "8021x")
            return "󰌾";
        if (network.type === "psk")
            return "󰌾";
        return "󰅛";
    }

    function signalIcon(level) {
        return level >= 4 ? "󰤨" : level === 3 ? "󰤥" : level === 2 ? "󰤢" : level === 1 ? "󰤟" : "󰤯";
    }

    function mutationsAllowed() {
        return service.available && service.powered && !service.busy && !actionGuard.running;
    }

    function activateNetwork(network) {
        if (!network || !service.available || !service.powered || service.busy || actionGuard.running)
            return;
        if (network.connected) {
            actionGuard.restart();
            service.disconnect();
        } else if (!supported(network)) {
            return;
        } else if (network.type === "open" || network.known) {
            actionGuard.restart();
            service.connectNetwork(network.id);
        } else {
            promptNetwork = network;
            passwordInput.text = "";
            inputGuard.restart();
            Qt.callLater(function() {
                passwordInput.forceActiveFocus();
            });
        }
    }

    function activateSelected() {
        if (selectedIndex === 0) {
            if (!service.available || service.busy || actionGuard.running)
                return;
            actionGuard.restart();
            service.setPowered(!service.powered);
        } else if (selectedIndex === 1) {
            if (!service.available || !service.powered || service.scanning || service.busy || actionGuard.running)
                return;
            actionGuard.restart();
            service.scan();
        } else {
            activateNetwork(selectedNetwork());
        }
    }

    function submitPassword() {
        if (!promptNetwork || inputGuard.running || service.busy || !service.available || !service.powered)
            return;
        var current = networkById(promptNetwork.id);
        if (!current || current.name !== promptNetwork.name || current.known || current.type !== "psk") {
            clearPrompt();
            return;
        }
        var secret = passwordInput.text;
        if (!/^[\x20-\x7e]{8,63}$/.test(secret)) {
            secret = "";
            return;
        }
        passwordInput.text = "";
        inputGuard.restart();
        service.connectNetwork(current.id, secret);
        secret = "";
        promptNetwork = null;
        keyboardScope.forceActiveFocus();
    }

    function clearPrompt() {
        if (passwordInput)
            passwordInput.text = "";
        promptNetwork = null;
        inputGuard.stop();
        if (menuVisible)
            keyboardScope.forceActiveFocus();
    }

    function requestForget(network) {
        if (!network || !network.known || service.busy || actionGuard.running)
            return;
        confirmationId = network.id;
        confirmationName = network.name;
        confirmationSelection = 0;
        confirmationPending = true;
        confirmationGuard.restart();
    }

    function clearConfirmation() {
        confirmationPending = false;
        confirmationSelection = 0;
        confirmationId = "";
        confirmationName = "";
        confirmationGuard.stop();
    }

    function activateConfirmation() {
        if (confirmationSelection === 0) {
            clearConfirmation();
            return;
        }
        if (confirmationGuard.running || service.busy)
            return;
        var current = networkById(confirmationId);
        if (current && current.name === confirmationName && current.known) {
            actionGuard.restart();
            service.forgetNetwork(current.id);
        }
        clearConfirmation();
    }

    function toggleAutoconnect(network) {
        if (!network || !network.known || !mutationsAllowed())
            return;
        var current = networkById(network.id);
        if (!current || current.name !== network.name || !current.known)
            return;
        actionGuard.restart();
        service.setAutoconnect(current.id, !current.autoconnect);
    }

    function moveSelection(delta) {
        if (navigationCount <= 0)
            return;
        selectedIndex = (selectedIndex + delta + navigationCount) % navigationCount;
        keepSelectedVisible();
    }

    function setSelection(index) {
        selectedIndex = Math.max(0, Math.min(index, navigationCount - 1));
        keepSelectedVisible();
    }

    function keepSelectedVisible() {
        if (selectedIndex < 2 || !networkFlick.visible)
            return;
        var row = selectedIndex - 2;
        var top = row * 56;
        var bottom = top + 52;
        if (top < networkFlick.contentY)
            networkFlick.contentY = top;
        else if (bottom > networkFlick.contentY + networkFlick.height)
            networkFlick.contentY = Math.min(networkFlick.contentHeight - networkFlick.height, bottom - networkFlick.height);
    }

    function selectionState() {
        if (promptNetwork)
            return "Password entry";
        if (confirmationPending)
            return confirmationSelection === 0 ? "Forget cancel" : "Forget confirm";
        if (selectedIndex === 0)
            return service.available ? (service.powered ? "Wi-Fi enabled" : "Wi-Fi disabled") : "Wi-Fi unavailable";
        if (selectedIndex === 1)
            return service.scanning ? "Scanning" : "Scan idle";
        return networkStatus(selectedNetwork());
    }

    onNetworkCountChanged: setSelection(selectedIndex)
    onMenuVisibleChanged: {
        if (!menuVisible)
            clearPrompt();
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "wifi"
        description: "Show Wi-Fi panel"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "wifiMenu"

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
            return root.menuVisible;
        }

        function networkCount(): int {
            return root.networkCount;
        }

        function selectedState(): string {
            return root.selectedState;
        }
    }

    Timer {
        id: actionGuard

        interval: Qt.styleHints.mouseDoubleClickInterval + 100
    }

    Timer {
        id: inputGuard

        interval: Qt.styleHints.mouseDoubleClickInterval + 100
    }

    Timer {
        id: confirmationGuard

        interval: Qt.styleHints.mouseDoubleClickInterval + 100
    }

    PanelWindow {
        id: wifiWindow

        screen: root.targetScreen
        visible: root.menuVisible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell-wifi-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.menuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        HyprlandFocusGrab {
            active: root.menuVisible
            windows: [wifiWindow]
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
                width: Math.min(560, wifiWindow.width - 40)
                height: Math.min(wifiWindow.height - 80, Math.max(310, (operationRow.visible ? 176 : 148) + root.visibleNetworkRows * 56))
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
                    focus: root.menuVisible
                    Keys.onPressed: function(event) {
                        if (root.promptNetwork)
                            return;
                        if (event.key === Qt.Key_Escape) {
                            if (root.confirmationPending)
                                root.clearConfirmation();
                            else
                                root.hide();
                            event.accepted = true;
                            return;
                        }
                        if (root.confirmationPending) {
                            if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                root.confirmationSelection = (root.confirmationSelection + 1) % 2;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Home) {
                                root.confirmationSelection = 0;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_End) {
                                root.confirmationSelection = 1;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                                if (!event.isAutoRepeat)
                                    root.activateConfirmation();
                                event.accepted = true;
                            }
                            return;
                        }
                        if (event.key === Qt.Key_Up) {
                            root.moveSelection(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down) {
                            root.moveSelection(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                            var backwards = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
                            root.moveSelection(backwards ? -1 : 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Home) {
                            root.setSelection(0);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_End) {
                            root.setSelection(root.navigationCount - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_F) {
                            if (!event.isAutoRepeat)
                                root.requestForget(root.selectedNetwork());
                            event.accepted = true;
                        } else if (event.key === Qt.Key_A) {
                            if (!event.isAutoRepeat)
                                root.toggleAutoconnect(root.selectedNetwork());
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            if (!event.isAutoRepeat)
                                root.activateSelected();
                            event.accepted = true;
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: !root.promptNetwork && !root.confirmationPending

                        Text {
                            id: heading

                            anchors.top: parent.top
                            anchors.topMargin: 20
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "WI-FI"
                            textFormat: Text.PlainText
                            color: root.theme.overlay
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.5
                        }

                        Row {
                            id: controls

                            anchors.top: heading.bottom
                            anchors.topMargin: 15
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            spacing: 9

                            ControlButton {
                                width: (controls.width - controls.spacing) / 2
                                selected: root.selectedIndex === 0
                                available: root.service.available && !root.service.busy
                                icon: root.service.powered ? "󰤨" : "󰤭"
                                label: !root.service.available ? "Unavailable" : root.service.powered ? "On" : "Off"
                                onHovered: root.setSelection(0)
                                onActivated: {
                                    root.setSelection(0);
                                    root.activateSelected();
                                }
                            }

                            ControlButton {
                                width: (controls.width - controls.spacing) / 2
                                selected: root.selectedIndex === 1
                                available: root.service.available && root.service.powered && !root.service.scanning && !root.service.busy
                                icon: root.service.scanning ? "󰑓" : "󰍉"
                                label: root.service.scanning ? "Scanning…" : "Scan"
                                onHovered: root.setSelection(1)
                                onActivated: {
                                    root.setSelection(1);
                                    root.activateSelected();
                                }
                            }
                        }

                        Row {
                            id: operationRow

                            anchors.top: controls.bottom
                            anchors.topMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 30
                            spacing: 8
                            visible: root.service.busy || root.service.errorMessage !== ""

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.service.busy ? (root.service.pendingCommand === "connect" ? "Connecting…" : "Working…") : root.service.errorMessage
                                textFormat: Text.PlainText
                                color: root.service.errorMessage !== "" ? root.theme.red : root.theme.subtext
                                font.family: root.theme.fontFamily
                                font.pixelSize: 11
                            }

                            Rectangle {
                                width: 72
                                height: 28
                                visible: root.service.busy && root.service.pendingCommand === "connect"
                                radius: root.theme.radius - 3
                                color: cancelHover.hovered ? root.theme.surface1 : root.theme.surfaceSolid

                                Text {
                                    anchors.centerIn: parent
                                    text: root.service.cancelSeq >= 0 ? "Canceling…" : "Cancel"
                                    textFormat: Text.PlainText
                                    color: root.theme.text
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: 10
                                }

                                HoverHandler {
                                    id: cancelHover
                                }

                                TapHandler {
                                    enabled: root.service.cancelSeq < 0
                                    onTapped: root.service.cancel()
                                }
                            }
                        }

                        Text {
                            id: emptyText

                            anchors.top: controls.bottom
                            anchors.topMargin: operationRow.visible ? 44 : 36
                            anchors.left: parent.left
                            anchors.right: parent.right
                            visible: !root.service.available || !root.service.powered || root.networkCount === 0
                            text: !root.service.available ? "Wi-Fi is unavailable" : !root.service.powered ? "Wi-Fi is off" : "No networks found. Select Scan to search."
                            textFormat: Text.PlainText
                            color: root.theme.subtext
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            font.family: root.theme.fontFamily
                            font.pixelSize: 13
                        }

                        Flickable {
                            id: networkFlick

                            anchors.top: controls.bottom
                            anchors.topMargin: operationRow.visible ? 40 : 12
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            height: Math.min(388, Math.max(0, Math.min(root.networkCount, Math.floor(Math.max(0, footer.y - y - 6) / 56)) * 56 - 4))
                            visible: root.service.available && root.service.powered && root.networkCount > 0
                            clip: true
                            contentWidth: width
                            contentHeight: networkColumn.height
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: networkColumn

                                width: networkFlick.width
                                spacing: 4

                                Repeater {
                                    model: root.networkRows

                                    delegate: Rectangle {
                                        id: networkRow

                                        required property var modelData
                                        required property int index
                                        readonly property bool actionable: modelData.connected || root.supported(modelData)
                                        readonly property bool mutableNow: root.service.available && root.service.powered && !root.service.busy

                                        width: networkColumn.width
                                        height: 52
                                        radius: root.theme.radius - 2
                                        color: root.selectedIndex === index + 2 ? root.theme.surfaceSolid : (networkHover.hovered ? Qt.rgba(root.theme.surface1.r, root.theme.surface1.g, root.theme.surface1.b, 0.55) : "transparent")
                                        border.width: root.selectedIndex === index + 2 ? 1 : 0
                                        border.color: root.theme.lavender
                                        opacity: actionable && mutableNow ? 1 : 0.62

                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 24
                                            horizontalAlignment: Text.AlignHCenter
                                            text: root.typeIcon(modelData)
                                            textFormat: Text.PlainText
                                            color: modelData.connected ? root.theme.green : root.theme.blue
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: 17
                                        }

                                        Column {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 42
                                            anchors.right: autoButton.visible ? autoButton.left : forgetButton.visible ? forgetButton.left : signalLabel.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 1

                                            Text {
                                                width: parent.width
                                                text: modelData.name === "" ? "Hidden network" : modelData.name
                                                textFormat: Text.PlainText
                                                color: root.theme.text
                                                elide: Text.ElideRight
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: 13
                                                font.bold: root.selectedIndex === index + 2
                                            }

                                            Text {
                                                width: parent.width
                                                text: root.networkStatus(modelData)
                                                textFormat: Text.PlainText
                                                color: root.supported(modelData) ? root.theme.subtext : root.theme.red
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: 10
                                            }
                                        }

                                        Rectangle {
                                            id: autoButton

                                            anchors.right: forgetButton.visible ? forgetButton.left : signalLabel.left
                                            anchors.rightMargin: 3
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 32
                                            height: 32
                                            visible: modelData.known
                                            radius: root.theme.radius - 3
                                            color: autoHover.hovered ? root.theme.surface1 : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "A"
                                                textFormat: Text.PlainText
                                                color: modelData.autoconnect ? root.theme.green : root.theme.overlay
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: 11
                                                font.bold: true
                                            }

                                            HoverHandler {
                                                id: autoHover
                                                onHoveredChanged: {
                                                    if (hovered)
                                                        root.setSelection(index + 2);
                                                }
                                            }

                                            TapHandler {
                                                enabled: networkRow.mutableNow
                                                onTapped: {
                                                    root.setSelection(index + 2);
                                                    root.toggleAutoconnect(modelData);
                                                }
                                            }
                                        }

                                        Rectangle {
                                            id: forgetButton

                                            anchors.right: signalLabel.left
                                            anchors.rightMargin: 3
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 32
                                            height: 32
                                            visible: modelData.known
                                            radius: root.theme.radius - 3
                                            color: forgetHover.hovered ? root.theme.surface1 : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰆴"
                                                textFormat: Text.PlainText
                                                color: root.theme.red
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: 13
                                            }

                                            HoverHandler {
                                                id: forgetHover
                                                onHoveredChanged: {
                                                    if (hovered)
                                                        root.setSelection(index + 2);
                                                }
                                            }

                                            TapHandler {
                                                enabled: networkRow.mutableNow
                                                onTapped: {
                                                    root.setSelection(index + 2);
                                                    root.requestForget(modelData);
                                                }
                                            }
                                        }

                                        Text {
                                            id: signalLabel

                                            anchors.right: parent.right
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 24
                                            horizontalAlignment: Text.AlignHCenter
                                            text: root.signalIcon(modelData.signal)
                                            textFormat: Text.PlainText
                                            color: root.theme.subtext
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: 16
                                        }

                                        HoverHandler {
                                            id: networkHover
                                            onHoveredChanged: {
                                                if (hovered)
                                                    root.setSelection(index + 2);
                                            }
                                        }

                                        Item {
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.left: parent.left
                                            anchors.right: autoButton.visible ? autoButton.left : forgetButton.visible ? forgetButton.left : signalLabel.left

                                            TapHandler {
                                                enabled: networkRow.actionable && networkRow.mutableNow
                                                onTapped: {
                                                    root.setSelection(index + 2);
                                                    root.activateNetwork(modelData);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            id: footer

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 14
                            text: "Up / Down / Tab  select    Enter  activate    A  auto    F  forget    Esc  close"
                            textFormat: Text.PlainText
                            color: root.theme.overlay
                            horizontalAlignment: Text.AlignHCenter
                            font.family: root.theme.fontFamily
                            font.pixelSize: 9
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: !!root.promptNetwork

                        Column {
                            anchors.centerIn: parent
                            width: Math.min(390, parent.width - 48)
                            spacing: 14

                            Text {
                                width: parent.width
                                text: "WI-FI PASSWORD"
                                textFormat: Text.PlainText
                                color: root.theme.overlay
                                horizontalAlignment: Text.AlignHCenter
                                font.family: root.theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 1.5
                            }

                            Text {
                                width: parent.width
                                text: root.promptNetwork ? "Password for " + root.promptNetwork.name : "Enter the network password"
                                textFormat: Text.PlainText
                                color: root.theme.text
                                horizontalAlignment: Text.AlignHCenter
                                font.family: root.theme.fontFamily
                                font.pixelSize: 16
                                font.bold: true
                            }

                            Rectangle {
                                width: parent.width
                                height: 46
                                radius: root.theme.radius
                                color: root.theme.surfaceSolid
                                border.width: 1
                                border.color: passwordInput.activeFocus ? root.theme.lavender : root.theme.surface1

                                TextInput {
                                    id: passwordInput

                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: root.theme.text
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: 14
                                    echoMode: TextInput.Password
                                    maximumLength: 63
                                    selectByMouse: false
                                    persistentSelection: false
                                    validator: RegularExpressionValidator {
                                        regularExpression: /^[\x20-\x7e]{0,63}$/
                                    }
                                    Keys.onPressed: function(event) {
                                        if ((event.modifiers & Qt.ControlModifier) || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))) {
                                            event.accepted = true;
                                            return;
                                        }
                                        if (event.key === Qt.Key_Escape) {
                                            root.clearPrompt();
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            if (!event.isAutoRepeat)
                                                root.submitPassword();
                                            event.accepted = true;
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.AllButtons
                                    onClicked: passwordInput.forceActiveFocus()
                                }
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 12

                                PromptButton {
                                    label: "Cancel"
                                    primary: false
                                    onActivated: root.clearPrompt()
                                }

                                PromptButton {
                                    label: "Connect"
                                    primary: true
                                    available: /^[\x20-\x7e]{8,63}$/.test(passwordInput.text) && !inputGuard.running && !root.service.busy
                                    onActivated: root.submitPassword()
                                }
                            }

                            Text {
                                width: parent.width
                                text: "8–63 printable ASCII characters    Esc  cancel"
                                textFormat: Text.PlainText
                                color: root.theme.overlay
                                horizontalAlignment: Text.AlignHCenter
                                font.family: root.theme.fontFamily
                                font.pixelSize: 10
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: root.confirmationPending

                        Column {
                            anchors.top: parent.top
                            anchors.topMargin: 80
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 12

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰆴"
                                textFormat: Text.PlainText
                                color: root.theme.red
                                font.family: root.theme.fontFamily
                                font.pixelSize: 34
                            }

                            Text {
                                width: parent.width
                                text: "Forget this Wi-Fi network?"
                                textFormat: Text.PlainText
                                color: root.theme.text
                                horizontalAlignment: Text.AlignHCenter
                                font.family: root.theme.fontFamily
                                font.pixelSize: 18
                                font.bold: true
                            }

                            Text {
                                width: parent.width
                                text: "Saved credentials will be removed."
                                textFormat: Text.PlainText
                                color: root.theme.subtext
                                horizontalAlignment: Text.AlignHCenter
                                font.family: root.theme.fontFamily
                                font.pixelSize: 12
                            }
                        }

                        Row {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 82
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12

                            Repeater {
                                model: [{
                                        "label": "Cancel",
                                        "confirm": false
                                    }, {
                                        "label": "Forget",
                                        "confirm": true
                                    }]

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    width: 150
                                    height: 46
                                    radius: root.theme.radius
                                    color: index === root.confirmationSelection ? (modelData.confirm ? root.theme.red : root.theme.surface1) : root.theme.surfaceSolid
                                    border.width: index === root.confirmationSelection ? 1 : 0
                                    border.color: modelData.confirm ? root.theme.red : root.theme.lavender

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
                            anchors.bottomMargin: 22
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

    component ControlButton: Rectangle {
        id: control

        required property bool selected
        required property bool available
        required property string icon
        required property string label
        signal hovered()
        signal activated()

        height: 52
        radius: root.theme.radius
        color: selected ? root.theme.surfaceSolid : (controlHover.hovered ? Qt.rgba(root.theme.surface1.r, root.theme.surface1.g, root.theme.surface1.b, 0.55) : "transparent")
        border.width: selected ? 1 : 0
        border.color: root.theme.lavender
        opacity: available ? 1 : 0.55

        Row {
            anchors.centerIn: parent
            spacing: 9

            Text {
                text: control.icon
                textFormat: Text.PlainText
                color: root.theme.blue
                font.family: root.theme.fontFamily
                font.pixelSize: 17
            }

            Text {
                text: control.label
                textFormat: Text.PlainText
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 12
                font.bold: control.selected
            }
        }

        HoverHandler {
            id: controlHover
            onHoveredChanged: {
                if (hovered)
                    control.hovered();
            }
        }

        TapHandler {
            enabled: control.available
            onTapped: control.activated()
        }
    }

    component PromptButton: Rectangle {
        id: promptButton

        required property string label
        required property bool primary
        property bool available: true
        signal activated()

        width: 150
        height: 44
        radius: root.theme.radius
        color: primary ? root.theme.blue : root.theme.surfaceSolid
        opacity: available ? 1 : 0.5

        Text {
            anchors.centerIn: parent
            text: promptButton.label
            textFormat: Text.PlainText
            color: promptButton.primary ? root.theme.base : root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: 13
            font.bold: true
        }

        TapHandler {
            enabled: promptButton.available
            onTapped: promptButton.activated()
        }
    }
}
