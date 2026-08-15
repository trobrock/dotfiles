import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: root

    required property var theme
    property bool menuVisible: false
    property var targetScreen: null
    property int selectedIndex: 0
    property bool confirmationPending: false
    property int confirmationSelection: 0
    property var confirmationDevice: null
    property var scanAdapter: null
    property string scanState: "idle"
    property bool scanCancelRequested: false
    property bool scanSawActive: false
    readonly property bool ownsScan: scanState !== "idle"
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var deviceRows: buildDeviceRows()
    readonly property int deviceCount: deviceRows.length
    readonly property int visibleDeviceRows: Math.min(deviceCount, 7)
    readonly property int navigationCount: deviceCount + 2
    readonly property string selectedState: selectionState()

    function boundedText(value, maximum) {
        return String(value === undefined || value === null ? "" : value).slice(0, maximum * 2).replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu, " ").replace(/\s+/g, " ").trim().slice(0, maximum);
    }

    function displayName(device) {
        var value = boundedText(device ? device.name : "", 80);
        if (value === "")
            value = boundedText(device ? device.deviceName : "", 80);
        return value === "" ? "Unnamed device" : value;
    }

    function deviceIcon(device) {
        var iconClass = boundedText(device ? device.icon : "", 64).toLowerCase();
        if (/head|audio|headset/.test(iconClass))
            return "󰋋";
        if (/phone|mobile/.test(iconClass))
            return "󰄜";
        if (/keyboard|input-keyboard/.test(iconClass))
            return "󰌌";
        if (/mouse|input-mouse/.test(iconClass))
            return "󰍽";
        if (/game|joystick/.test(iconClass))
            return "󰊴";
        if (/watch/.test(iconClass))
            return "󰖉";
        if (/computer|laptop/.test(iconClass))
            return "󰌢";
        return "";
    }

    function deviceState(device) {
        if (!device)
            return "Available";
        if (device.blocked)
            return "Blocked";
        if (device.pairing)
            return "Pairing";
        if (device.state === BluetoothDeviceState.Connecting)
            return "Connecting";
        if (device.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting";
        if (device.connected || device.state === BluetoothDeviceState.Connected)
            return "Connected";
        if (device.paired || device.bonded)
            return "Paired";
        return "Available";
    }

    function buildDeviceRows() {
        var values = adapter && adapter.devices ? adapter.devices.values : [];
        var rows = [];
        var candidateCount = Math.min(values.length, 50);
        for (var i = 0; i < candidateCount; ++i) {
            var device = values[i];
            if (!device || device.adapter !== adapter)
                continue;
            var state = deviceState(device);
            var paired = !!(device.paired || device.bonded);
            rows.push({
                "device": device,
                "name": displayName(device),
                "icon": deviceIcon(device),
                "state": state,
                "connectedRank": device.connected || state === "Connected" ? 0 : 1,
                "pairedRank": paired ? 0 : 1
            });
        }
        rows.sort(function(a, b) {
            if (a.connectedRank !== b.connectedRank)
                return a.connectedRank - b.connectedRank;
            if (a.pairedRank !== b.pairedRank)
                return a.pairedRank - b.pairedRank;
            return a.name.localeCompare(b.name);
        });
        return rows;
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
        stopOwnedScan();
        menuVisible = false;
        clearConfirmation();
    }

    function toggle() {
        if (menuVisible)
            hide();
        else
            show();
    }

    function adapterReady() {
        return !!adapter && adapter.state === BluetoothAdapterState.Enabled && adapter.enabled;
    }

    function adapterToggleSafe() {
        return !!adapter && (adapter.state === BluetoothAdapterState.Enabled || adapter.state === BluetoothAdapterState.Disabled);
    }

    function clearScanOwnership() {
        scanTimeout.stop();
        scanStartTimeout.stop();
        scanAdapter = null;
        scanState = "idle";
        scanCancelRequested = false;
        scanSawActive = false;
    }

    function startScan() {
        if (!adapterReady() || adapter.discovering || scanState !== "idle")
            return;
        scanAdapter = adapter;
        scanState = "starting";
        scanCancelRequested = false;
        scanSawActive = false;
        adapter.discovering = true;
        scanStartTimeout.restart();
    }

    function stopOwnedScan() {
        scanTimeout.stop();
        if (scanState === "idle" || !scanAdapter)
            return;
        scanCancelRequested = true;
        scanState = "stopping";
        scanAdapter.discovering = false;
    }

    function toggleAdapter() {
        if (!adapterToggleSafe())
            return;
        if (adapter.state === BluetoothAdapterState.Enabled) {
            stopOwnedScan();
            adapter.enabled = false;
        } else {
            adapter.enabled = true;
        }
    }

    function activateScan() {
        if (!adapterReady())
            return;
        if (adapter.discovering) {
            if (ownsScan && scanAdapter === adapter)
                stopOwnedScan();
            return;
        }
        if (scanState === "idle")
            startScan();
    }

    function containsDevice(device) {
        if (!device || !adapter || device.adapter !== adapter || !adapter.devices)
            return false;
        var values = adapter.devices.values;
        var candidateCount = Math.min(values.length, 50);
        for (var i = 0; i < candidateCount; ++i) {
            if (values[i] === device)
                return true;
        }
        return false;
    }

    function deviceUsable(device) {
        return adapterReady() && containsDevice(device) && !device.blocked;
    }

    function deviceTransitioning(device) {
        return device && (device.state === BluetoothDeviceState.Connecting || device.state === BluetoothDeviceState.Disconnecting);
    }

    function deviceActionable(device) {
        return deviceUsable(device) && !deviceTransitioning(device);
    }

    function deviceForgettable(device) {
        return deviceActionable(device) && !device.pairing && (device.paired || device.bonded);
    }

    function activateDevice(device) {
        if (!deviceActionable(device))
            return;
        if (device.pairing)
            device.cancelPair();
        else if (device.connected || device.state === BluetoothDeviceState.Connected)
            device.disconnect();
        else if (device.paired || device.bonded)
            device.connect();
        else
            device.pair();
    }

    function selectedDevice() {
        var index = selectedIndex - 2;
        return index >= 0 && index < deviceRows.length ? deviceRows[index].device : null;
    }

    function activateSelected() {
        if (selectedIndex === 0)
            toggleAdapter();
        else if (selectedIndex === 1)
            activateScan();
        else
            activateDevice(selectedDevice());
    }

    function requestForget(device) {
        if (!deviceForgettable(device))
            return;
        confirmationDevice = device;
        confirmationPending = true;
        confirmationSelection = 0;
        confirmationGuard.restart();
    }

    function requestSelectedForget() {
        requestForget(selectedDevice());
    }

    function clearConfirmation() {
        confirmationPending = false;
        confirmationSelection = 0;
        confirmationDevice = null;
        confirmationGuard.stop();
    }

    function activateConfirmation() {
        if (confirmationSelection === 0) {
            clearConfirmation();
            return;
        }
        if (confirmationGuard.running)
            return;
        var device = confirmationDevice;
        if (deviceForgettable(device))
            device.forget();
        clearConfirmation();
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
        if (selectedIndex < 2 || !deviceFlick.visible)
            return;
        var row = selectedIndex - 2;
        var top = row * 56;
        var bottom = top + 52;
        if (top < deviceFlick.contentY)
            deviceFlick.contentY = top;
        else if (bottom > deviceFlick.contentY + deviceFlick.height)
            deviceFlick.contentY = Math.min(deviceFlick.contentHeight - deviceFlick.height, bottom - deviceFlick.height);
    }

    function selectionState() {
        if (confirmationPending)
            return confirmationSelection === 0 ? "Forget cancel" : "Forget confirm";
        if (selectedIndex === 0) {
            if (!adapter)
                return "Adapter unavailable";
            return adapter.enabled ? "Adapter enabled" : "Adapter disabled";
        }
        if (selectedIndex === 1) {
            if (scanState === "starting")
                return "Scan starting";
            if (scanState === "stopping")
                return "Scan stopping";
            return adapter && adapter.discovering ? "Scanning" : "Scan idle";
        }
        return deviceState(selectedDevice());
    }

    onAdapterChanged: {
        if (scanAdapter && scanAdapter !== adapter)
            stopOwnedScan();
        setSelection(selectedIndex);
    }
    onDeviceCountChanged: setSelection(selectedIndex)
    Component.onDestruction: stopOwnedScan()

    GlobalShortcut {
        appid: "quickshell"
        name: "bluetooth"
        description: "Show Bluetooth panel"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "bluetoothMenu"

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

        function deviceCount(): int {
            return root.deviceCount;
        }

        function selectedState(): string {
            return root.selectedState;
        }
    }

    Connections {
        target: root.scanAdapter

        function onDiscoveringChanged() {
            if (!root.scanAdapter || root.scanState === "idle")
                return;
            if (root.scanAdapter.discovering) {
                root.scanSawActive = true;
                scanStartTimeout.stop();
                if (root.scanCancelRequested || root.scanState === "stopping") {
                    root.scanState = "stopping";
                    root.scanAdapter.discovering = false;
                } else {
                    root.scanState = "active";
                    scanTimeout.restart();
                }
            } else {
                root.clearScanOwnership();
            }
        }
    }

    Timer {
        id: scanStartTimeout

        interval: 30000
        onTriggered: {
            if (!root.scanAdapter || root.scanState === "idle")
                return;
            if (root.scanAdapter.discovering) {
                root.scanSawActive = true;
                if (root.scanCancelRequested || root.scanState === "stopping")
                    root.scanAdapter.discovering = false;
            } else {
                root.clearScanOwnership();
            }
        }
    }

    Timer {
        id: scanTimeout

        interval: 30000
        onTriggered: root.stopOwnedScan()
    }

    Timer {
        id: confirmationGuard

        interval: Qt.styleHints.mouseDoubleClickInterval + 100
    }

    PanelWindow {
        id: bluetoothWindow

        screen: root.targetScreen
        visible: root.menuVisible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell-bluetooth-menu"
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
            windows: [bluetoothWindow]
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
                width: Math.min(560, bluetoothWindow.width - 40)
                height: Math.min(bluetoothWindow.height - 80, Math.max(310, 148 + root.visibleDeviceRows * 56))
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
                                root.requestSelectedForget();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            if (!event.isAutoRepeat)
                                root.activateSelected();
                            event.accepted = true;
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: !root.confirmationPending

                        Text {
                            id: heading

                            anchors.top: parent.top
                            anchors.topMargin: 20
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "BLUETOOTH"
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
                                available: root.adapterToggleSafe()
                                icon: root.adapter && root.adapter.enabled ? "" : "󰂲"
                                label: !root.adapter ? "No adapter" : root.adapter.state === BluetoothAdapterState.Blocked ? "Blocked" : root.adapter.state === BluetoothAdapterState.Enabling ? "Turning on…" : root.adapter.state === BluetoothAdapterState.Disabling ? "Turning off…" : root.adapter.enabled ? "On" : "Off"
                                onHovered: root.setSelection(0)
                                onActivated: {
                                    root.setSelection(0);
                                    root.toggleAdapter();
                                }
                            }

                            ControlButton {
                                width: (controls.width - controls.spacing) / 2
                                selected: root.selectedIndex === 1
                                available: root.adapterReady() && ((root.scanState === "idle" && !root.adapter.discovering) || (root.scanState === "active" && root.scanAdapter === root.adapter))
                                icon: root.adapter && root.adapter.discovering ? "󰑓" : "󰍉"
                                label: root.scanState === "starting" ? "Starting…" : root.scanState === "stopping" ? "Stopping…" : root.adapter && root.adapter.discovering ? (root.ownsScan ? "Stop scan" : "Scanning externally") : "Scan"
                                onHovered: root.setSelection(1)
                                onActivated: {
                                    root.setSelection(1);
                                    root.activateScan();
                                }
                            }
                        }

                        Text {
                            id: emptyText

                            anchors.top: controls.bottom
                            anchors.topMargin: 36
                            anchors.left: parent.left
                            anchors.right: parent.right
                            visible: root.deviceCount === 0
                            text: !root.adapter ? "No Bluetooth adapter" : root.adapter.state === BluetoothAdapterState.Blocked ? "Bluetooth is blocked" : root.adapterReady() ? "No devices found. Start a scan to search." : "Bluetooth is off"
                            textFormat: Text.PlainText
                            color: root.theme.subtext
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            font.family: root.theme.fontFamily
                            font.pixelSize: 13
                        }

                        Flickable {
                            id: deviceFlick

                            anchors.top: controls.bottom
                            anchors.topMargin: 12
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            height: Math.min(388, Math.max(0, root.deviceCount * 56 - 4), Math.max(0, footer.y - y - 10))
                            visible: root.deviceCount > 0
                            clip: true
                            contentWidth: width
                            contentHeight: deviceColumn.height
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: deviceColumn

                                width: deviceFlick.width
                                spacing: 4

                                Repeater {
                                    model: root.deviceRows

                                    delegate: Rectangle {
                                        id: deviceRow

                                        required property var modelData
                                        required property int index
                                        readonly property var device: modelData.device
                                        readonly property bool usable: root.deviceActionable(device)
                                        readonly property bool forgettable: root.deviceForgettable(device)

                                        width: deviceColumn.width
                                        height: 52
                                        radius: root.theme.radius - 2
                                        color: root.selectedIndex === index + 2 ? root.theme.surfaceSolid : (deviceHover.hovered ? Qt.rgba(root.theme.surface1.r, root.theme.surface1.g, root.theme.surface1.b, 0.55) : "transparent")
                                        border.width: root.selectedIndex === index + 2 ? 1 : 0
                                        border.color: root.theme.lavender
                                        opacity: usable ? 1 : 0.62

                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 26
                                            horizontalAlignment: Text.AlignHCenter
                                            text: modelData.icon
                                            textFormat: Text.PlainText
                                            color: device.connected ? root.theme.green : root.theme.blue
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: 18
                                        }

                                        Column {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 48
                                            anchors.right: batteryLabel.visible ? batteryLabel.left : forgetButton.left
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 1

                                            Text {
                                                width: parent.width
                                                text: modelData.name
                                                textFormat: Text.PlainText
                                                color: root.theme.text
                                                elide: Text.ElideRight
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: 13
                                                font.bold: root.selectedIndex === index + 2
                                            }

                                            Text {
                                                width: parent.width
                                                text: root.deviceState(device)
                                                textFormat: Text.PlainText
                                                color: device.blocked ? root.theme.red : root.theme.subtext
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: 10
                                            }
                                        }

                                        Text {
                                            id: batteryLabel

                                            anchors.right: forgetButton.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: device.batteryAvailable && isFinite(Number(device.battery))
                                            text: visible ? String(Math.round(Math.max(0, Math.min(1, Number(device.battery))) * 100)) + "%" : ""
                                            textFormat: Text.PlainText
                                            color: root.theme.subtext
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: 10
                                        }

                                        Rectangle {
                                            id: forgetButton

                                            anchors.right: parent.right
                                            anchors.rightMargin: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 34
                                            height: 34
                                            visible: deviceRow.forgettable
                                            radius: root.theme.radius - 3
                                            color: forgetHover.hovered ? root.theme.surface1 : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰆴"
                                                textFormat: Text.PlainText
                                                color: root.theme.red
                                                font.family: root.theme.fontFamily
                                                font.pixelSize: 14
                                            }

                                            HoverHandler {
                                                id: forgetHover
                                                onHoveredChanged: {
                                                    if (hovered)
                                                        root.setSelection(index + 2);
                                                }
                                            }

                                            TapHandler {
                                                onTapped: {
                                                    root.setSelection(index + 2);
                                                    root.requestForget(device);
                                                }
                                            }
                                        }

                                        HoverHandler {
                                            id: deviceHover
                                            onHoveredChanged: {
                                                if (hovered)
                                                    root.setSelection(index + 2);
                                            }
                                        }

                                        Item {
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.left: parent.left
                                            anchors.right: forgetButton.visible ? forgetButton.left : parent.right

                                            TapHandler {
                                                onTapped: {
                                                    root.setSelection(index + 2);
                                                    root.activateDevice(device);
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
                            text: "Up / Down / Tab  select    Enter  activate    F  forget    Esc  close"
                            textFormat: Text.PlainText
                            color: root.theme.overlay
                            horizontalAlignment: Text.AlignHCenter
                            font.family: root.theme.fontFamily
                            font.pixelSize: 9
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
                                text: "Forget this Bluetooth device?"
                                textFormat: Text.PlainText
                                color: root.theme.text
                                horizontalAlignment: Text.AlignHCenter
                                font.family: root.theme.fontFamily
                                font.pixelSize: 18
                                font.bold: true
                            }

                            Text {
                                width: parent.width
                                text: "It will need to be paired again before reconnecting."
                                textFormat: Text.PlainText
                                color: root.theme.subtext
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
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
}
