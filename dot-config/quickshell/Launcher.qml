import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Item {
    id: root

    required property var theme
    property bool launcherVisible: false
    property string mode: "apps"
    property string query: ""
    property var targetScreen: null
    property var appResults: []
    property var calcResults: []
    property var clipboardResults: []
    property string errorText: ""
    property int selectedIndex: 0
    property bool changingText: false
    property int calcGeneration: 0
    property int calcProcessGeneration: 0
    property int calcExitCode: 0
    property bool calcStreamFinished: false
    property bool calcProcessExited: false
    property int clipboardGeneration: 0
    property int clipboardProcessGeneration: 0
    property var clipboardPendingRows: []
    readonly property var currentResults: mode === "apps" ? appResults : (mode === "calc" ? calcResults : clipboardResults)
    readonly property int resultCount: currentResults.length

    function bounded(value, maximum) {
        return String(value === undefined || value === null ? "" : value).slice(0, maximum);
    }

    function oneLine(value, maximum) {
        return bounded(value, maximum * 2).replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim().slice(0, maximum);
    }

    function applicationIcon(name) {
        var icon = bounded(name, 160);
        if (!/^[A-Za-z0-9._+-]+$/.test(icon) || icon === "network-wired")
            return "";
        return Quickshell.iconPath(icon, true);
    }

    function normalizeMode(requested) {
        var value = String(requested || "apps").toLowerCase();
        if (value === "calc" || value === "calculator")
            return "calc";
        if (value === "clipboard" || value === "clip")
            return "clipboard";
        return "apps";
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

    function show(requestedMode) {
        targetScreen = focusedScreen();
        setMode(normalizeMode(requestedMode), true);
        launcherVisible = true;
        Qt.callLater(function() {
            searchInput.forceActiveFocus();
        });
    }

    function toggle(requestedMode) {
        var wanted = normalizeMode(requestedMode);
        if (launcherVisible && mode === wanted)
            hide();
        else
            show(wanted);
    }

    function hide() {
        if (!launcherVisible)
            return;
        launcherVisible = false;
        calcDebounce.stop();
        clipboardDebounce.stop();
        calcGeneration++;
        clipboardGeneration++;
        changingText = true;
        query = "";
        searchInput.text = "";
        changingText = false;
        appResults = [];
        calcResults = [];
        clipboardResults = [];
        clipboardPendingRows = [];
        errorText = "";
    }

    function showApps() {
        show("apps");
    }

    function showCalc() {
        show("calc");
    }

    function showClipboard() {
        show("clipboard");
    }

    function toggleApps() {
        toggle("apps");
    }

    function toggleCalc() {
        toggle("calc");
    }

    function toggleClipboard() {
        toggle("clipboard");
    }

    function setMode(newMode, clearInput) {
        var wanted = normalizeMode(newMode);
        if (mode === "clipboard" && wanted !== "clipboard") {
            clipboardResults = [];
            clipboardPendingRows = [];
        }
        mode = wanted;
        selectedIndex = 0;
        errorText = "";
        if (clearInput) {
            changingText = true;
            query = "";
            searchInput.text = "";
            changingText = false;
        }
        updateMode();
        if (launcherVisible)
            Qt.callLater(function() {
                searchInput.forceActiveFocus();
            });
    }

    function cycleMode(delta) {
        var modes = ["apps", "calc", "clipboard"];
        var index = modes.indexOf(mode);
        setMode(modes[(index + delta + modes.length) % modes.length], true);
    }

    function updateMode() {
        if (mode === "apps") {
            calcDebounce.stop();
            clipboardDebounce.stop();
            updateApps();
        } else if (mode === "calc") {
            clipboardDebounce.stop();
            calcGeneration++;
            calcResults = [];
            if (query.length > 0) {
                errorText = "Calculating…";
                calcDebounce.restart();
            } else {
                errorText = "Type an expression";
            }
        } else {
            calcDebounce.stop();
            clipboardGeneration++;
            clipboardResults = [];
            errorText = "Searching clipboard…";
            clipboardDebounce.restart();
        }
    }

    function handleInput(value) {
        if (changingText)
            return;
        var next = bounded(value, mode === "calc" ? 256 : 120);
        var prefixMode = "";
        if (next.charAt(0) === "=")
            prefixMode = "calc";
        else if (next.charAt(0) === "$")
            prefixMode = "clipboard";
        if (prefixMode !== "") {
            changingText = true;
            next = next.slice(1);
            if (mode === "clipboard" && prefixMode !== "clipboard") {
                clipboardResults = [];
                clipboardPendingRows = [];
            }
            mode = prefixMode;
            searchInput.text = next;
            searchInput.cursorPosition = next.length;
            changingText = false;
        } else if (next !== value) {
            changingText = true;
            searchInput.text = next;
            searchInput.cursorPosition = next.length;
            changingText = false;
        }
        query = next;
        selectedIndex = 0;
        errorText = "";
        updateMode();
    }

    function fuzzyScore(candidate, needle) {
        var text = bounded(candidate, 320).toLowerCase();
        var wanted = bounded(needle, 80).toLowerCase();
        if (wanted.length === 0)
            return 0;
        var direct = text.indexOf(wanted);
        var score = direct >= 0 ? 500 - Math.min(direct, 100) * 2 : 0;
        var position = 0;
        var previous = -2;
        for (var i = 0; i < wanted.length; ++i) {
            var found = text.indexOf(wanted.charAt(i), position);
            if (found < 0)
                return -1;
            score += found === previous + 1 ? 18 : 5;
            if (found === 0 || /[\s._-]/.test(text.charAt(found - 1)))
                score += 12;
            score -= Math.min(found - position, 20);
            previous = found;
            position = found + 1;
        }
        return score - Math.min(text.length, 200) / 20;
    }

    function updateApps() {
        var needle = bounded(query, 80).trim().toLowerCase();
        var values = DesktopEntries.applications.values;
        var scored = [];
        for (var i = 0; i < values.length; ++i) {
            var entry = values[i];
            if (!entry || entry.noDisplay || !entry.command || entry.command.length === 0)
                continue;
            var name = oneLine(entry.name, 100);
            if (name.length === 0)
                continue;
            var genericName = oneLine(entry.genericName, 100);
            var keywords = "";
            if (entry.keywords)
                keywords = bounded(Array.prototype.join.call(entry.keywords, " "), 120);
            var score = fuzzyScore(name + " " + genericName + " " + keywords, needle);
            if (score < 0)
                continue;
            scored.push({
                "entry": entry,
                "title": name,
                "subtitle": genericName.length > 0 ? genericName : oneLine(entry.comment, 140),
                "icon": bounded(entry.icon, 160),
                "score": score
            });
        }
        scored.sort(function(a, b) {
            if (b.score !== a.score)
                return b.score - a.score;
            return a.title.localeCompare(b.title);
        });
        appResults = scored.slice(0, 9);
        if (appResults.length === 0)
            errorText = "No matching applications";
        else
            errorText = "";
        clampSelection();
    }

    function launchApplication(entry) {
        if (!entry || !entry.command || entry.command.length === 0)
            return;
        var argv = ["uwsm", "app", "--"];
        if (entry.runInTerminal) {
            argv.push("ghostty");
            argv.push("-e");
        }
        for (var i = 0; i < entry.command.length && i < 128; ++i)
            argv.push(String(entry.command[i]).slice(0, 4096));
        try {
            Quickshell.execDetached(argv);
            hide();
        } catch (error) {
            errorText = "Could not launch this application";
        }
    }

    function startCalc() {
        if (!launcherVisible || mode !== "calc" || query.length === 0)
            return;
        if (calcProcess.running)
            return;
        calcProcessGeneration = calcGeneration;
        calcExitCode = 0;
        calcStreamFinished = false;
        calcProcessExited = false;
        calcTimeout.restart();
        calcProcess.exec(["qalc", "-t", bounded(query, 256)]);
    }

    function finishCalcOutput(raw) {
        calcStreamFinished = true;
        if (calcProcessGeneration === calcGeneration && launcherVisible && mode === "calc") {
            var result = bounded(raw, 512).replace(/[\r\n]+$/g, "").trim();
            if (result.length > 0) {
                calcResults = [{
                    "title": result,
                    "subtitle": "Enter to copy"
                }];
                errorText = "";
                selectedIndex = 0;
            }
        }
        finishCalcCycle();
    }

    function finishCalcCycle() {
        if (!calcProcessExited || !calcStreamFinished)
            return;
        if (calcProcessGeneration === calcGeneration && launcherVisible && mode === "calc" && calcResults.length === 0)
            errorText = calcExitCode === 0 ? "No calculator result" : "Calculator unavailable (is qalc installed?)";
        if (calcProcessGeneration !== calcGeneration && launcherVisible && mode === "calc")
            Qt.callLater(startCalc);
    }

    function calcExited(code) {
        calcTimeout.stop();
        calcExitCode = code;
        calcProcessExited = true;
        finishCalcCycle();
    }

    function copyCalculation() {
        if (calcResults.length === 0)
            return;
        var result = bounded(calcResults[0].title, 512);
        try {
            Quickshell.execDetached(["wl-copy", result]);
        } catch (error) {
        }
        hide();
    }

    function sanitizedClipboardQuery() {
        return bounded(query, 120).replace(/[;\r\n]/g, " ");
    }

    function startClipboardQuery() {
        if (!launcherVisible || mode !== "clipboard")
            return;
        if (clipboardProcess.running)
            return;
        clipboardProcessGeneration = clipboardGeneration;
        clipboardPendingRows = [];
        clipboardTimeout.restart();
        clipboardProcess.exec(["elephant", "query", "--json", "clipboard;" + sanitizedClipboardQuery() + ";9"]);
    }

    function parseClipboardLine(line) {
        if (clipboardProcessGeneration !== clipboardGeneration || clipboardPendingRows.length >= 9)
            return;
        var data = bounded(line, 16384).trim();
        if (data.length === 0)
            return;
        var value;
        try {
            value = JSON.parse(data);
        } catch (error) {
            return;
        }
        if (!value || typeof value !== "object" || !value.item || typeof value.item !== "object")
            return;
        var item = value.item;
        var identifier = bounded(item.identifier !== undefined ? item.identifier : item.id, 128);
        if (!/^[0-9a-f]{32}$/.test(identifier))
            return;
        var previewType = oneLine(item.preview_type, 24).toLowerCase();
        var image = previewType === "file";
        var title = image ? "Clipboard image" : oneLine(item.text !== undefined ? item.text : item.preview, 180);
        var subtitle = oneLine(item.subtext !== undefined ? item.subtext : item.description, 220);
        if (title.length === 0)
            title = image ? "Clipboard image" : "Clipboard entry";
        if (subtitle.length === 0)
            subtitle = image ? "Image (preview not loaded)" : "Enter to copy";
        var rows = clipboardPendingRows.slice();
        rows.push({
            "identifier": identifier,
            "title": title,
            "subtitle": subtitle,
            "image": image
        });
        clipboardPendingRows = rows;
    }

    function clipboardExited(code) {
        clipboardTimeout.stop();
        if (clipboardProcessGeneration === clipboardGeneration && launcherVisible && mode === "clipboard") {
            clipboardResults = clipboardPendingRows.slice(0, 9);
            selectedIndex = 0;
            if (code !== 0)
                errorText = "Clipboard search unavailable (is Elephant running?)";
            else if (clipboardResults.length === 0)
                errorText = query.length > 0 ? "No matching clipboard entries" : "Clipboard is empty";
            else
                errorText = "";
        }
        clipboardPendingRows = [];
        if (clipboardProcessGeneration !== clipboardGeneration && launcherVisible && mode === "clipboard")
            Qt.callLater(startClipboardQuery);
    }

    function activateClipboard(identifier) {
        var safeIdentifier = bounded(identifier, 128);
        if (!/^[0-9a-f]{32}$/.test(safeIdentifier))
            return;
        try {
            Quickshell.execDetached(["elephant", "activate", "clipboard;" + safeIdentifier + ";copy;;"]);
        } catch (error) {
        }
        hide();
    }

    function clampSelection() {
        if (resultCount === 0)
            selectedIndex = 0;
        else
            selectedIndex = Math.max(0, Math.min(selectedIndex, resultCount - 1));
    }

    function moveSelection(delta) {
        if (resultCount === 0)
            return;
        selectedIndex = (selectedIndex + delta + resultCount) % resultCount;
    }

    function activateSelected() {
        if (resultCount === 0)
            return;
        var row = currentResults[selectedIndex];
        if (mode === "apps")
            launchApplication(row.entry);
        else if (mode === "calc")
            copyCalculation();
        else
            activateClipboard(row.identifier);
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "launcher"
        description: "Show application launcher"
        onPressed: root.toggleApps()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "clipboard"
        description: "Show clipboard launcher"
        onPressed: root.toggleClipboard()
    }

    IpcHandler {
        target: "launcher"

        function show(mode: string) {
            root.show(mode);
        }

        function toggle(mode: string) {
            root.toggle(mode);
        }

        function showApps(): void {
            root.showApps();
        }

        function showCalc(): void {
            root.showCalc();
        }

        function showClipboard(): void {
            root.showClipboard();
        }

        function resultCount(): int {
            return root.resultCount;
        }

        function currentMode(): string {
            return root.mode;
        }

        function hide(): void {
            root.hide();
        }
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            if (root.launcherVisible && root.mode === "apps")
                root.updateApps();
        }
    }

    Timer {
        id: calcDebounce

        interval: 110
        onTriggered: root.startCalc()
    }

    Timer {
        id: clipboardDebounce

        interval: 120
        onTriggered: root.startClipboardQuery()
    }

    Timer {
        id: calcTimeout

        interval: 3000
        onTriggered: {
            if (calcProcess.running)
                calcProcess.running = false;
            if (root.calcProcessGeneration === root.calcGeneration && root.mode === "calc")
                root.errorText = "Calculator timed out";
        }
    }

    Timer {
        id: clipboardTimeout

        interval: 3000
        onTriggered: {
            if (clipboardProcess.running)
                clipboardProcess.running = false;
            if (root.clipboardProcessGeneration === root.clipboardGeneration && root.mode === "clipboard")
                root.errorText = "Clipboard search timed out";
        }
    }

    Process {
        id: calcProcess

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.finishCalcOutput(text)
        }
        onExited: function(exitCode) {
            root.calcExited(exitCode);
        }
    }

    Process {
        id: clipboardProcess

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                root.parseClipboardLine(data);
            }
        }
        onExited: function(exitCode) {
            root.clipboardExited(exitCode);
        }
    }

    PanelWindow {
        id: launcherWindow

        screen: root.targetScreen
        visible: root.launcherVisible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell-launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.launcherVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        HyprlandFocusGrab {
            active: root.launcherVisible
            windows: [launcherWindow]
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
                width: Math.min(780, launcherWindow.width - 40)
                height: Math.min(570, launcherWindow.height - 80)
                radius: root.theme.radius + 4
                color: root.theme.base
                border.width: 1
                border.color: root.theme.surface1
                clip: true

                MouseArea {
                    anchors.fill: parent
                }

                Rectangle {
                    id: rail

                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    width: Math.min(164, card.width * 0.27)
                    color: root.theme.surfaceSolid

                    Column {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 12
                        spacing: 7

                        Text {
                            width: parent.width
                            leftPadding: 10
                            topPadding: 8
                            bottomPadding: 12
                            text: "LAUNCHER"
                            textFormat: Text.PlainText
                            color: root.theme.overlay
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.5
                        }

                        Repeater {
                            model: [{
                                    "mode": "apps",
                                    "icon": "󰀻",
                                    "label": "Apps"
                                }, {
                                    "mode": "calc",
                                    "icon": "󰃬",
                                    "label": "Calc"
                                }, {
                                    "mode": "clipboard",
                                    "icon": "󰅇",
                                    "label": "Clipboard"
                                }]

                            delegate: Rectangle {
                                required property var modelData

                                width: rail.width - 24
                                height: 42
                                radius: root.theme.radius - 2
                                color: root.mode === modelData.mode ? root.theme.surface1 : "transparent"
                                border.width: tabHover.hovered && root.mode !== modelData.mode ? 1 : 0
                                border.color: root.theme.overlay

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 11
                                    spacing: 10

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.icon
                                        textFormat: Text.PlainText
                                        color: root.mode === modelData.mode ? root.theme.mauve : root.theme.subtext
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: 17
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        textFormat: Text.PlainText
                                        color: root.mode === modelData.mode ? root.theme.text : root.theme.subtext
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: root.mode === modelData.mode
                                    }
                                }

                                HoverHandler {
                                    id: tabHover
                                }

                                TapHandler {
                                    onTapped: root.setMode(modelData.mode, true)
                                }
                            }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 16
                        text: "Tab  mode\nEsc  close"
                        textFormat: Text.PlainText
                        color: root.theme.overlay
                        font.family: root.theme.fontFamily
                        font.pixelSize: 10
                        lineHeight: 1.45
                    }
                }

                Item {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: rail.right
                    anchors.right: parent.right
                    anchors.margins: 20

                    Rectangle {
                        id: searchBox

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 48
                        radius: root.theme.radius
                        color: root.theme.surfaceSolid
                        border.width: searchInput.activeFocus ? 2 : 1
                        border.color: searchInput.activeFocus ? root.theme.blue : root.theme.surface1

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 15
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.mode === "apps" ? "󰍉" : (root.mode === "calc" ? "=" : "󰅇")
                            textFormat: Text.PlainText
                            color: root.theme.mauve
                            font.family: root.theme.fontFamily
                            font.pixelSize: 18
                        }

                        TextInput {
                            id: searchInput

                            anchors.left: parent.left
                            anchors.leftMargin: 46
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.theme.text
                            selectionColor: root.theme.blue
                            selectedTextColor: root.theme.base
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSize + 1
                            clip: true
                            activeFocusOnTab: true
                            Accessible.name: "Launcher search"
                            onTextChanged: root.handleInput(text)
                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Down) {
                                    root.moveSelection(1);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up) {
                                    root.moveSelection(-1);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    root.activateSelected();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    root.hide();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                    var backwards = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
                                    root.cycleMode(backwards ? -1 : 1);
                                    event.accepted = true;
                                }
                            }
                        }

                        Text {
                            anchors.left: searchInput.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length === 0
                            text: root.mode === "apps" ? "Search applications…" : (root.mode === "calc" ? "Enter an expression…" : "Search clipboard…")
                            textFormat: Text.PlainText
                            color: root.theme.overlay
                            font: searchInput.font
                        }
                    }

                    Column {
                        anchors.top: searchBox.bottom
                        anchors.topMargin: 14
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 5

                        Repeater {
                            model: root.currentResults

                            delegate: Rectangle {
                                id: resultRow

                                required property var modelData
                                required property int index

                                width: parent.width
                                height: 46
                                radius: root.theme.radius - 2
                                color: index === root.selectedIndex ? root.theme.surfaceSolid : (rowHover.hovered ? Qt.rgba(root.theme.surface1.r, root.theme.surface1.g, root.theme.surface1.b, 0.55) : "transparent")
                                border.width: index === root.selectedIndex ? 1 : 0
                                border.color: searchInput.activeFocus ? root.theme.lavender : root.theme.overlay
                                Accessible.name: modelData.title

                                IconImage {
                                    id: appIcon

                                    visible: root.mode === "apps"
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 30
                                    height: 30
                                    source: root.mode === "apps" ? root.applicationIcon(modelData.icon) : ""
                                }

                                Text {
                                    visible: root.mode === "apps" && (appIcon.source.toString() === "" || appIcon.status === Image.Error)
                                    anchors.left: parent.left
                                    anchors.leftMargin: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 28
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "󰣆"
                                    textFormat: Text.PlainText
                                    color: root.theme.subtext
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: 17
                                }

                                Text {
                                    visible: root.mode !== "apps"
                                    anchors.left: parent.left
                                    anchors.leftMargin: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 28
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.mode === "calc" ? "󰃬" : (modelData.image ? "󰋩" : "󰅇")
                                    textFormat: Text.PlainText
                                    color: root.mode === "calc" ? root.theme.green : root.theme.peach
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: 17
                                }

                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 50
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        text: root.bounded(modelData.title, root.mode === "calc" ? 512 : 180)
                                        textFormat: Text.PlainText
                                        color: root.theme.text
                                        elide: Text.ElideRight
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: index === root.selectedIndex
                                    }

                                    Text {
                                        width: parent.width
                                        visible: text.length > 0
                                        text: root.oneLine(modelData.subtitle, 220)
                                        textFormat: Text.PlainText
                                        color: root.theme.subtext
                                        elide: Text.ElideRight
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: 10
                                    }
                                }

                                HoverHandler {
                                    id: rowHover
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
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: searchBox.bottom
                        anchors.topMargin: 38
                        visible: root.resultCount === 0 && root.errorText.length > 0
                        text: root.bounded(root.errorText, 160)
                        textFormat: Text.PlainText
                        color: root.errorText.indexOf("unavailable") >= 0 || root.errorText.indexOf("timed out") >= 0 ? root.theme.red : root.theme.subtext
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        font.family: root.theme.fontFamily
                        font.pixelSize: 13
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: root.resultCount > 0 ? String(root.selectedIndex + 1) + " / " + String(root.resultCount) : ""
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
