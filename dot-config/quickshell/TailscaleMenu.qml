import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "components"

Item {
    id: root

    required property var theme
    required property var service
    property bool menuVisible: false
    property var targetScreen: null
    property string currentMode: "main"
    property int selectedIndex: 0
    property int mainSelectedIndex: 0
    property int peerSelectedIndex: 0
    property int exitSelectedIndex: 0
    property string selectedPeerId: ""
    property string pendingSendPeerId: ""

    readonly property var accountRows: boundedArray(service ? service.accounts : [], 32)
    readonly property var peerRows: boundedArray(service ? service.peers : [], 200)
    readonly property var exitTailnetRows: boundedArray(service ? service.tailnetExitNodes : [], 200)
    readonly property var exitMullvadRows: boundedArray(service ? service.mullvadRegions : [], 128)
    readonly property var activeExitNode: findActiveExitNode()
    readonly property var mainRows: buildMainRows()
    readonly property int mainRowCount: mainRows.length
    readonly property var selectedPeer: findPeerById(selectedPeerId)
    readonly property var peerActionRows: buildPeerActionRows()
    readonly property int peerActionCount: peerActionRows.length
    readonly property var exitRows: buildExitRows()
    readonly property int exitRowCount: exitRows.length
    readonly property int rowCount: currentMode === "main" ? mainRowCount + 2 : currentMode === "peer" ? peerActionCount : exitRowCount
    readonly property int visibleListRows: Math.min(currentMode === "main" ? mainRowCount : currentMode === "peer" ? peerActionCount : exitRowCount, 8)
    readonly property string selectedState: selectionState()
    readonly property bool startGuardRunning: startGuard.running

    function boundedArray(source, maximum) {
        return Array.isArray(source) ? source.slice(0, maximum) : [];
    }

    function safeText(value, fallback) {
        var text = value === undefined || value === null ? "" : String(value);
        return text !== "" ? text : (fallback || "");
    }

    function peerPrimaryIp(peer) {
        if (!peer)
            return "";
        if (peer.TailscaleIPs && peer.TailscaleIPs.length > 0)
            return safeText(peer.TailscaleIPs[0], "");
        if (peer.TailscaleIPv6 && peer.TailscaleIPv6.length > 0)
            return safeText(peer.TailscaleIPv6[0], "");
        return "";
    }

    function peerTitle(peer) {
        return safeText(peer && (peer.DisplayName || peer.HostName), "Device");
    }

    function peerSubtitle(peer) {
        if (!peer)
            return "Online";
        var dns = safeText(peer.DNSName, "");
        var ip = peerPrimaryIp(peer);
        var parts = [];
        if (dns !== "")
            parts.push(dns);
        if (ip !== "" && ip !== dns)
            parts.push(ip);
        if (parts.length === 0)
            parts.push("Online");
        return parts.join("  ");
    }

    function accountTitle(account) {
        return safeText(account && account.label, "Account");
    }

    function exitNodeSubtitle(node) {
        if (!node)
            return "Exit node";
        if (node.Mullvad === true)
            return "Mullvad region";
        var dns = safeText(node.DNSName, "");
        var display = safeText(node.DisplayName, "");
        if (dns !== "" && dns !== display)
            return dns;
        var ip = peerPrimaryIp(node);
        if (ip !== "")
            return ip;
        return "Tailnet exit node";
    }

    function headerSecondaryText() {
        var parts = [];
        if (safeText(service && service.statusText, "") !== "")
            parts.push(String(service.statusText));
        if (safeText(service && service.selfIp, "") !== "")
            parts.push(String(service.selfIp));
        if (parts.length === 0)
            parts.push(service && service.installed ? "Idle" : "Unavailable");
        return parts.join("  ");
    }

    function toggleLabel() {
        if (!service)
            return "Toggle";
        if (!service.installed && !service.active && !service.needsLogin && !service.running)
            return "Connect";
        if (service.needsLogin)
            return service.loginReady ? "Open login" : "Login";
        if (service.running)
            return "Disconnect";
        if (service.active)
            return "Disconnect";
        return "Connect";
    }

    function toggleIcon() {
        if (service && service.running)
            return "󰅖";
        if (service && service.needsLogin)
            return "󰌍";
        return "󰐊";
    }

    function findActiveExitNode() {
        var i;
        for (i = 0; i < exitTailnetRows.length; ++i) {
            if (exitTailnetRows[i] && exitTailnetRows[i].ExitNode === true)
                return exitTailnetRows[i];
        }
        for (i = 0; i < exitMullvadRows.length; ++i) {
            if (exitMullvadRows[i] && exitMullvadRows[i].ExitNode === true)
                return exitMullvadRows[i];
        }
        return null;
    }

    function buildMainRows() {
        var rows = [];
        var i;
        if (service && service.accountsAccessDenied)
            rows.push({ "kind": "authorize" });
        for (i = 0; i < accountRows.length; ++i)
            rows.push({ "kind": "account", "account": accountRows[i] });
        for (i = 0; i < peerRows.length; ++i)
            rows.push({ "kind": "peer", "peer": peerRows[i] });
        rows.push({ "kind": "exitChooser", "node": activeExitNode });
        return rows;
    }

    function buildPeerActionRows() {
        return [{
                "kind": "back"
            }, {
                "kind": "copyIp"
            }, {
                "kind": "copyName"
            }, {
                "kind": "copyDns"
            }, {
                "kind": "sendFiles"
            }];
    }

    function buildExitRows() {
        var rows = [{
                "kind": "back"
            }, {
                "kind": "clearExit",
                "active": activeExitNode !== null
            }];
        var i;
        for (i = 0; i < exitTailnetRows.length; ++i)
            rows.push({ "kind": "exitNode", "node": exitTailnetRows[i], "category": "tailnet" });
        for (i = 0; i < exitMullvadRows.length; ++i)
            rows.push({ "kind": "exitNode", "node": exitMullvadRows[i], "category": "mullvad" });
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
        currentMode = "main";
        selectedPeerId = "";
        pendingSendPeerId = "";
        mainSelectedIndex = 0;
        peerSelectedIndex = 0;
        exitSelectedIndex = 0;
        selectedIndex = 0;
        menuVisible = true;
        startGuard.restart();
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
        menuVisible = false;
        pendingSendPeerId = "";
        if (fileDialog.visible)
            fileDialog.close();
    }

    function toggle() {
        if (menuVisible)
            hide();
        else
            show();
    }

    function syncSelectionStore() {
        if (currentMode === "main")
            mainSelectedIndex = selectedIndex;
        else if (currentMode === "peer")
            peerSelectedIndex = selectedIndex;
        else
            exitSelectedIndex = selectedIndex;
    }

    function setSelection(index) {
        if (rowCount <= 0) {
            selectedIndex = 0;
            syncSelectionStore();
            return;
        }
        selectedIndex = Math.max(0, Math.min(index, rowCount - 1));
        syncSelectionStore();
        keepSelectedVisible();
    }

    function moveSelection(delta) {
        if (rowCount <= 0)
            return;
        selectedIndex = (selectedIndex + delta + rowCount) % rowCount;
        syncSelectionStore();
        keepSelectedVisible();
    }

    function keepSelectedVisible() {
        var flick = currentMode === "main" ? mainFlick : currentMode === "peer" ? peerFlick : exitFlick;
        if (!flick || !flick.visible)
            return;
        var row = currentMode === "main" ? selectedIndex - 2 : selectedIndex;
        if (row < 0)
            return;
        var top = row * 56;
        var bottom = top + 52;
        if (top < flick.contentY)
            flick.contentY = top;
        else if (bottom > flick.contentY + flick.height)
            flick.contentY = Math.min(flick.contentHeight - flick.height, bottom - flick.height);
    }

    function enterMain() {
        currentMode = "main";
        selectedPeerId = "";
        setSelection(mainSelectedIndex);
        Qt.callLater(function() {
            keyboardScope.forceActiveFocus();
        });
    }

    function openPeerDetail(peer) {
        if (!peer)
            return;
        selectedPeerId = safeText(peer.id, "");
        if (selectedPeerId === "")
            return;
        currentMode = "peer";
        setSelection(peerSelectedIndex);
        Qt.callLater(function() {
            keyboardScope.forceActiveFocus();
        });
    }

    function openExitList() {
        currentMode = "exit";
        setSelection(exitSelectedIndex);
        Qt.callLater(function() {
            keyboardScope.forceActiveFocus();
        });
    }

    function findPeerById(peerId) {
        var wanted = safeText(peerId, "");
        if (wanted === "")
            return null;
        for (var i = 0; i < peerRows.length; ++i) {
            if (peerRows[i] && safeText(peerRows[i].id, "") === wanted)
                return peerRows[i];
        }
        return null;
    }

    function selectedMainRow() {
        var row = selectedIndex - 2;
        return row >= 0 && row < mainRows.length ? mainRows[row] : null;
    }

    function selectedPeerAction() {
        return selectedIndex >= 0 && selectedIndex < peerActionRows.length ? peerActionRows[selectedIndex] : null;
    }

    function selectedExitRow() {
        return selectedIndex >= 0 && selectedIndex < exitRows.length ? exitRows[selectedIndex] : null;
    }

    function canActivate() {
        return !startGuard.running && !actionGuard.running && !(service && service.busy);
    }

    function activateToggle() {
        if (!canActivate())
            return;
        actionGuard.restart();
        service.toggle();
    }

    function activateRefresh() {
        if (!canActivate())
            return;
        actionGuard.restart();
        service.refresh(true);
    }

    function activateMainRow(row) {
        if (!row)
            return;
        if (row.kind === "peer") {
            openPeerDetail(row.peer);
            return;
        }
        if (row.kind === "exitChooser") {
            openExitList();
            return;
        }
        if (!canActivate())
            return;
        if (row.kind === "authorize") {
            actionGuard.restart();
            service.authorizeOperator();
        } else if (row.kind === "account" && row.account) {
            actionGuard.restart();
            service.switchAccount(row.account.id);
        }
    }

    function activatePeerAction(row) {
        if (row && row.kind === "back") {
            enterMain();
            return;
        }
        if (!row || !selectedPeer || !canActivate())
            return;
        if (row.kind === "copyIp") {
            actionGuard.restart();
            service.copyPeerIp(selectedPeer.id);
        } else if (row.kind === "copyName") {
            actionGuard.restart();
            service.copyPeerName(selectedPeer.id);
        } else if (row.kind === "copyDns") {
            actionGuard.restart();
            service.copyPeerDnsName(selectedPeer.id);
        } else if (row.kind === "sendFiles") {
            if (!service.canSendFiles(selectedPeer.id))
                return;
            pendingSendPeerId = selectedPeer.id;
            actionGuard.restart();
            fileDialog.open();
        }
    }

    function activateExitRow(row) {
        if (row && row.kind === "back") {
            enterMain();
            return;
        }
        if (!row || !canActivate())
            return;
        actionGuard.restart();
        if (row.kind === "clearExit")
            service.setExitNode("");
        else if (row.kind === "exitNode" && row.node)
            service.setExitNode(row.node.id);
    }

    function activateSelected() {
        if (currentMode === "main") {
            if (selectedIndex === 0)
                activateToggle();
            else if (selectedIndex === 1)
                activateRefresh();
            else
                activateMainRow(selectedMainRow());
        } else if (currentMode === "peer") {
            activatePeerAction(selectedPeerAction());
        } else {
            activateExitRow(selectedExitRow());
        }
    }

    function selectionState() {
        if (currentMode === "main") {
            if (selectedIndex === 0)
                return "Toggle control";
            if (selectedIndex === 1)
                return "Refresh control";
            var row = selectedMainRow();
            if (!row)
                return "Main list";
            if (row.kind === "authorize")
                return "Authorize operator";
            if (row.kind === "account")
                return row.account && row.account.selected ? "Current account" : "Switch account";
            if (row.kind === "peer")
                return "Peer detail";
            if (row.kind === "exitChooser")
                return activeExitNode ? "Current exit node" : "Exit chooser";
            return "Main list";
        }
        if (currentMode === "peer") {
            var actionRow = selectedPeerAction();
            if (!actionRow)
                return "Peer actions";
            if (actionRow.kind === "back")
                return "Back to main panel";
            if (actionRow.kind === "copyIp")
                return "Copy address";
            if (actionRow.kind === "copyName")
                return "Copy name";
            if (actionRow.kind === "copyDns")
                return "Copy DNS name";
            if (actionRow.kind === "sendFiles")
                return "Send files";
            return "Peer actions";
        }
        var exitRow = selectedExitRow();
        if (!exitRow)
            return "Exit nodes";
        if (exitRow.kind === "back")
            return "Back to main panel";
        if (exitRow.kind === "clearExit")
            return exitRow.active ? "Clear exit node" : "No active exit node";
        return exitRow.category === "mullvad" ? "Mullvad exit node" : "Tailnet exit node";
    }

    function peerActionTitle(kind) {
        if (kind === "back")
            return "Back";
        if (kind === "copyIp")
            return "Copy address";
        if (kind === "copyName")
            return "Copy name";
        if (kind === "copyDns")
            return "Copy DNS name";
        if (kind === "sendFiles")
            return "Send with Taildrop";
        return "Action";
    }

    function peerActionSubtitle(kind) {
        if (kind === "back")
            return "Return to devices and connections";
        if (kind === "copyIp")
            return "Copy the current tailnet address";
        if (kind === "copyName")
            return "Copy the device name";
        if (kind === "copyDns")
            return "Copy the tailnet DNS name";
        if (kind === "sendFiles")
            return service.fileSharing ? "Choose local files to send" : "File sharing unavailable";
        return "";
    }

    function peerActionIcon(kind) {
        if (kind === "back")
            return "󰁍";
        if (kind === "copyIp")
            return "󰆏";
        if (kind === "copyName")
            return "󰈙";
        if (kind === "copyDns")
            return "󰇖";
        if (kind === "sendFiles")
            return "󰜡";
        return "󰈔";
    }

    function peerActionAvailable(kind) {
        if (kind === "back")
            return true;
        if (!selectedPeer)
            return false;
        if (kind === "sendFiles")
            return !service.busy && service.canSendFiles(selectedPeer.id);
        return !service.busy;
    }

    function localFilePath(urlValue) {
        var text = safeText(urlValue, "");
        if (text.indexOf("file:///") === 0)
            text = text.slice(7);
        else if (text.indexOf("file://localhost/") === 0)
            text = text.slice(16);
        else
            return "";
        var splitAt = text.search(/[?#]/);
        if (splitAt >= 0)
            text = text.slice(0, splitAt);
        try {
            text = decodeURIComponent(text);
        } catch (_error) {
            return "";
        }
        return text !== "" && text.charAt(0) === "/" ? text : "";
    }

    function localFilePaths(urls) {
        var result = [];
        if (!Array.isArray(urls))
            return result;
        for (var i = 0; i < urls.length; ++i) {
            var path = localFilePath(urls[i]);
            if (path !== "")
                result.push(path);
        }
        return result;
    }

    function footerText() {
        if (currentMode === "peer")
            return "J / K / ↑ / ↓  select    Enter  activate    C  address    N  name    D  DNS    S  send    Esc  back";
        if (currentMode === "exit")
            return "J / K / ↑ / ↓  select    Enter  choose    T  toggle    R  refresh    Esc  back";
        return "J / K / ↑ / ↓  select    Enter  open    T  toggle    R  refresh    X  exit nodes    Esc  close";
    }

    onRowCountChanged: setSelection(selectedIndex)
    onSelectedPeerChanged: {
        if (menuVisible && currentMode === "peer" && !selectedPeer)
            Qt.callLater(enterMain);
    }
    onMenuVisibleChanged: {
        service.panelActive = menuVisible;
        if (!menuVisible) {
            currentMode = "main";
            selectedPeerId = "";
            pendingSendPeerId = "";
            selectedIndex = 0;
            mainSelectedIndex = 0;
            peerSelectedIndex = 0;
            exitSelectedIndex = 0;
        }
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "tailscale"
        description: "Show Tailscale panel"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "tailscaleMenu"

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

        function rowCount(): int {
            return root.rowCount;
        }

        function selectedState(): string {
            return root.selectedState;
        }
    }

    Timer {
        id: startGuard

        interval: Qt.styleHints.mouseDoubleClickInterval + 100
    }

    Timer {
        id: actionGuard

        interval: Qt.styleHints.mouseDoubleClickInterval + 100
    }

    FileDialog {
        id: fileDialog

        fileMode: FileDialog.OpenFiles
        title: "Select files to send"
        onAccepted: {
            var paths = root.localFilePaths(selectedFiles);
            var peerId = root.pendingSendPeerId;
            root.pendingSendPeerId = "";
            root.service.sendFiles(peerId, paths);
            Qt.callLater(function() {
                keyboardScope.forceActiveFocus();
            });
        }
        onRejected: {
            root.pendingSendPeerId = "";
            Qt.callLater(function() {
                keyboardScope.forceActiveFocus();
            });
        }
    }

    PanelWindow {
        id: tailscaleWindow

        screen: root.targetScreen
        visible: root.menuVisible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell-tailscale-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.menuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        onVisibleChanged: root.service.panelActive = visible

        HyprlandFocusGrab {
            active: root.menuVisible
            windows: [tailscaleWindow]
            onCleared: root.hide()
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.theme.base.r, root.theme.base.g, root.theme.base.b, 0.58)

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: {
                    if (!startGuard.running)
                        root.hide();
                }
            }

            Rectangle {
                id: card

                anchors.centerIn: parent
                width: Math.min(560, tailscaleWindow.width - 40)
                height: Math.min(tailscaleWindow.height - 80, Math.max(320, 182 + (root.currentMode === "main" ? 56 : 0) + root.visibleListRows * 56 + (stateRow.visible ? 30 : 0)))
                radius: root.theme.radius + 4
                color: root.theme.base
                border.width: 1
                border.color: root.theme.surface1
                clip: true

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                FocusScope {
                    id: keyboardScope

                    anchors.fill: parent
                    focus: root.menuVisible
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            if (root.currentMode === "main")
                                root.hide();
                            else
                                root.enterMain();
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                            root.moveSelection(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
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
                            root.setSelection(root.rowCount - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_T) {
                            if (!event.isAutoRepeat)
                                root.activateToggle();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_R) {
                            if (!event.isAutoRepeat)
                                root.activateRefresh();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_X) {
                            if (!event.isAutoRepeat)
                                root.openExitList();
                            event.accepted = true;
                        } else if (root.currentMode === "peer" && event.key === Qt.Key_C) {
                            if (!event.isAutoRepeat)
                                root.activatePeerAction({ "kind": "copyIp" });
                            event.accepted = true;
                        } else if (root.currentMode === "peer" && event.key === Qt.Key_N) {
                            if (!event.isAutoRepeat)
                                root.activatePeerAction({ "kind": "copyName" });
                            event.accepted = true;
                        } else if (root.currentMode === "peer" && event.key === Qt.Key_D) {
                            if (!event.isAutoRepeat)
                                root.activatePeerAction({ "kind": "copyDns" });
                            event.accepted = true;
                        } else if (root.currentMode === "peer" && event.key === Qt.Key_S) {
                            if (!event.isAutoRepeat)
                                root.activatePeerAction({ "kind": "sendFiles" });
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            if (!event.isAutoRepeat)
                                root.activateSelected();
                            event.accepted = true;
                        }
                    }

                    Column {
                        id: topColumn

                        anchors.top: parent.top
                        anchors.topMargin: 18
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 12

                        Text {
                            width: parent.width
                            text: "TAILSCALE"
                            textFormat: Text.PlainText
                            color: root.theme.overlay
                            horizontalAlignment: Text.AlignHCenter
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.5
                        }

                        Row {
                            x: Math.max(0, (topColumn.width - width) / 2)
                            spacing: 12

                            TailscaleIcon {
                                iconSize: 24
                                foreground: root.theme.text
                                badgeColor: root.theme.red
                                crossed: !root.service.installed || (!root.service.running && !root.service.needsLogin && !root.service.active)
                                warning: root.service.needsLogin || root.service.accountsAccessDenied
                            }

                            Column {
                                spacing: 2

                                Text {
                                    text: root.safeText(root.service.selfName, "This device")
                                    textFormat: Text.PlainText
                                    color: root.theme.text
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: 15
                                    font.bold: true
                                }

                                Text {
                                    text: root.headerSecondaryText()
                                    textFormat: Text.PlainText
                                    color: root.theme.subtext
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }
                        }

                        Row {
                            id: controls

                            width: parent.width
                            visible: root.currentMode === "main"
                            spacing: 9

                            ControlButton {
                                width: (controls.width - controls.spacing) / 2
                                selected: root.selectedIndex === 0 && root.currentMode === "main"
                                available: !root.service.busy
                                icon: root.toggleIcon()
                                label: root.toggleLabel()
                                onHovered: root.setSelection(0)
                                onActivated: {
                                    root.setSelection(0);
                                    root.activateToggle();
                                }
                            }

                            ControlButton {
                                width: (controls.width - controls.spacing) / 2
                                selected: root.selectedIndex === 1 && root.currentMode === "main"
                                available: !root.service.busy
                                icon: "󰑐"
                                label: "Refresh"
                                onHovered: root.setSelection(1)
                                onActivated: {
                                    root.setSelection(1);
                                    root.activateRefresh();
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            visible: root.currentMode === "peer"
                            text: root.selectedPeer ? root.peerTitle(root.selectedPeer) : "Device"
                            textFormat: Text.PlainText
                            color: root.theme.text
                            horizontalAlignment: Text.AlignHCenter
                            font.family: root.theme.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Text {
                            width: parent.width
                            visible: root.currentMode === "peer"
                            text: root.selectedPeer ? root.peerSubtitle(root.selectedPeer) : "Unavailable"
                            textFormat: Text.PlainText
                            color: root.theme.subtext
                            horizontalAlignment: Text.AlignHCenter
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                        }

                        Text {
                            width: parent.width
                            visible: root.currentMode === "exit"
                            text: "EXIT NODES"
                            textFormat: Text.PlainText
                            color: root.theme.text
                            horizontalAlignment: Text.AlignHCenter
                            font.family: root.theme.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Text {
                            width: parent.width
                            visible: root.currentMode === "exit"
                            text: root.activeExitNode ? "Current selection available below" : "Choose a tailnet device or Mullvad region"
                            textFormat: Text.PlainText
                            color: root.theme.subtext
                            horizontalAlignment: Text.AlignHCenter
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                        }

                        Text {
                            id: stateRow

                            width: parent.width
                            visible: root.service.busy || root.service.actionStatus !== "" || root.service.errorMessage !== ""
                            text: root.service.errorMessage !== "" ? root.service.errorMessage : root.service.actionStatus !== "" ? root.service.actionStatus : "Working…"
                            textFormat: Text.PlainText
                            color: root.service.errorMessage !== "" ? root.theme.red : root.theme.subtext
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    Flickable {
                        id: mainFlick

                        x: 18
                        y: topColumn.y + topColumn.height + 12
                        width: card.width - 36
                        height: Math.min(448, Math.max(0, root.visibleListRows * 56 - 4), Math.max(0, footer.y - y - 10))
                        visible: root.currentMode === "main" && root.mainRowCount > 0
                        clip: true
                        contentWidth: width
                        contentHeight: mainColumn.height
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: mainColumn

                            width: mainFlick.width
                            spacing: 4

                            Repeater {
                                model: root.mainRows

                                delegate: MenuRow {
                                    required property var modelData
                                    required property int index

                                    width: mainColumn.width
                                    selected: root.currentMode === "main" && root.selectedIndex === index + 2
                                    available: modelData.kind === "peer" || modelData.kind === "exitChooser" ? true : (modelData.kind === "authorize" ? !root.service.busy : modelData.account ? !root.service.busy && modelData.account.selected !== true : true)
                                    icon: modelData.kind === "authorize" ? "󰐽" : modelData.kind === "account" ? "󰀄" : modelData.kind === "peer" ? root.safeText(modelData.peer && modelData.peer.OSIcon, "󰟀") : "󰌾"
                                    title: modelData.kind === "authorize" ? "Authorize operator" : modelData.kind === "account" ? root.accountTitle(modelData.account) : modelData.kind === "peer" ? root.peerTitle(modelData.peer) : root.activeExitNode ? root.safeText(root.activeExitNode.DisplayName, "Current exit node") : "Choose exit node"
                                    subtitle: modelData.kind === "authorize" ? "Account list access is restricted" : modelData.kind === "account" ? (modelData.account && modelData.account.selected ? "Current account" : "Switch account") : modelData.kind === "peer" ? root.peerSubtitle(modelData.peer) : root.activeExitNode ? root.exitNodeSubtitle(root.activeExitNode) : "Choose tailnet or Mullvad"
                                    trailingText: modelData.kind === "account" && modelData.account && modelData.account.selected ? "On" : modelData.kind === "exitChooser" && root.activeExitNode ? "On" : ""
                                    accentColor: modelData.kind === "authorize" ? root.theme.yellow : modelData.kind === "account" ? (modelData.account && modelData.account.selected ? root.theme.green : root.theme.blue) : modelData.kind === "peer" ? root.theme.sapphire : root.activeExitNode && root.activeExitNode.Mullvad ? root.theme.peach : root.theme.lavender
                                    showChevron: modelData.kind === "peer" || modelData.kind === "exitChooser"
                                    onHovered: root.setSelection(index + 2)
                                    onActivated: {
                                        root.setSelection(index + 2);
                                        root.activateMainRow(modelData);
                                    }
                                }
                            }
                        }
                    }

                    Flickable {
                        id: peerFlick

                        x: 18
                        y: topColumn.y + topColumn.height + 12
                        width: card.width - 36
                        height: Math.min(448, Math.max(0, root.visibleListRows * 56 - 4), Math.max(0, footer.y - y - 10))
                        visible: root.currentMode === "peer" && root.peerActionCount > 0
                        clip: true
                        contentWidth: width
                        contentHeight: peerColumn.height
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: peerColumn

                            width: peerFlick.width
                            spacing: 4

                            Repeater {
                                model: root.peerActionRows

                                delegate: MenuRow {
                                    required property var modelData
                                    required property int index

                                    width: peerColumn.width
                                    selected: root.currentMode === "peer" && root.selectedIndex === index
                                    available: root.peerActionAvailable(modelData.kind)
                                    icon: root.peerActionIcon(modelData.kind)
                                    title: root.peerActionTitle(modelData.kind)
                                    subtitle: root.peerActionSubtitle(modelData.kind)
                                    trailingText: ""
                                    accentColor: modelData.kind === "sendFiles" ? root.theme.blue : root.theme.lavender
                                    showChevron: false
                                    onHovered: root.setSelection(index)
                                    onActivated: {
                                        root.setSelection(index);
                                        root.activatePeerAction(modelData);
                                    }
                                }
                            }
                        }
                    }

                    Flickable {
                        id: exitFlick

                        x: 18
                        y: topColumn.y + topColumn.height + 12
                        width: card.width - 36
                        height: Math.min(448, Math.max(0, root.visibleListRows * 56 - 4), Math.max(0, footer.y - y - 10))
                        visible: root.currentMode === "exit" && root.exitRowCount > 0
                        clip: true
                        contentWidth: width
                        contentHeight: exitColumn.height
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: exitColumn

                            width: exitFlick.width
                            spacing: 4

                            Repeater {
                                model: root.exitRows

                                delegate: MenuRow {
                                    required property var modelData
                                    required property int index

                                    width: exitColumn.width
                                    selected: root.currentMode === "exit" && root.selectedIndex === index
                                    available: modelData.kind === "back" ? true : modelData.kind === "clearExit" ? (!!modelData.active && !root.service.busy) : !root.service.busy
                                    icon: modelData.kind === "back" ? "󰁍" : modelData.kind === "clearExit" ? "󰅖" : root.safeText(modelData.node && modelData.node.OSIcon, modelData.category === "mullvad" ? "󰖂" : "󰌾")
                                    title: modelData.kind === "back" ? "Back" : modelData.kind === "clearExit" ? "Clear exit node" : root.safeText(modelData.node && modelData.node.DisplayName, "Exit node")
                                    subtitle: modelData.kind === "back" ? "Return to devices and connections" : modelData.kind === "clearExit" ? (modelData.active ? "Disable the current exit node" : "No exit node selected") : root.exitNodeSubtitle(modelData.node)
                                    trailingText: modelData.kind !== "back" && modelData.kind !== "clearExit" && modelData.node && modelData.node.ExitNode === true ? "On" : ""
                                    accentColor: modelData.kind === "back" ? root.theme.lavender : modelData.kind === "clearExit" ? root.theme.red : modelData.category === "mullvad" ? root.theme.peach : root.theme.blue
                                    showChevron: false
                                    onHovered: root.setSelection(index)
                                    onActivated: {
                                        root.setSelection(index);
                                        root.activateExitRow(modelData);
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
                        text: root.footerText()
                        textFormat: Text.PlainText
                        color: root.theme.overlay
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        font.family: root.theme.fontFamily
                        font.pixelSize: 9
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
        color: selected ? root.theme.surfaceSolid : "transparent"
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
            onHoveredChanged: {
                if (hovered)
                    control.hovered();
            }
        }

        TapHandler {
            enabled: control.available && !root.startGuardRunning
            onTapped: control.activated()
        }
    }

    component MenuRow: Rectangle {
        id: row

        required property bool selected
        required property bool available
        required property string icon
        required property string title
        required property string subtitle
        required property string trailingText
        required property color accentColor
        property bool showChevron: false
        signal hovered()
        signal activated()

        height: 52
        radius: root.theme.radius - 2
        color: selected ? root.theme.surfaceSolid : "transparent"
        border.width: selected ? 1 : 0
        border.color: root.theme.lavender
        opacity: available ? 1 : 0.58

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            horizontalAlignment: Text.AlignHCenter
            text: row.icon
            textFormat: Text.PlainText
            color: row.accentColor
            font.family: root.theme.fontFamily
            font.pixelSize: 17
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 42
            anchors.right: trailing.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: row.title
                textFormat: Text.PlainText
                color: root.theme.text
                elide: Text.ElideRight
                font.family: root.theme.fontFamily
                font.pixelSize: 13
                font.bold: row.selected
            }

            Text {
                width: parent.width
                text: row.subtitle
                textFormat: Text.PlainText
                color: root.theme.subtext
                elide: Text.ElideRight
                font.family: root.theme.fontFamily
                font.pixelSize: 10
            }
        }

        Text {
            id: trailing

            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: row.trailingText !== "" ? row.trailingText : (row.showChevron ? "›" : "")
            textFormat: Text.PlainText
            color: row.trailingText !== "" ? row.accentColor : root.theme.overlay
            font.family: root.theme.fontFamily
            font.pixelSize: row.trailingText !== "" ? 10 : 18
            font.bold: row.trailingText !== ""
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered)
                    row.hovered();
            }
        }

        TapHandler {
            enabled: row.available && !root.startGuardRunning
            onTapped: row.activated()
        }
    }
}
