pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland

Item {
    id: root

    required property var theme
    required property var services
    property var notificationService: null

    property var targetScreen: null
    property bool osdVisible: false
    property string displayedKind: ""
    property real displayedValue: -1
    property string displayedIcon: ""
    property string displayedLabel: ""
    property string displayedDetail: ""
    property bool displayedProgress: false
    property int displaySerial: 0
    property int hideSerial: 0

    readonly property var audioSink: services ? services.audioSink : null
    readonly property var audioSource: Pipewire.defaultAudioSource

    property var audioQueue: []
    property bool audioActive: false
    property int audioProcessSerial: 0
    property string audioProcessKind: ""
    property int audioRefreshSerial: 0
    property string audioRefreshKind: ""

    property int brightnessPercent: -1
    property bool brightnessActive: false
    property bool brightnessExited: false
    property bool brightnessStreamFinished: false
    property int brightnessExitCode: -1
    property string brightnessOutput: ""
    property string brightnessOperation: ""
    property int brightnessProcessSerial: 0
    property int pendingBrightnessSteps: 0
    property int pendingBrightnessSerial: 0
    property bool pendingBrightnessQuery: false
    property int pendingBrightnessQuerySerial: 0

    property bool dndConnectionArmed: false

    function boundedText(value, maximum) {
        return String(value === undefined || value === null ? "" : value).replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim().slice(0, maximum);
    }

    function clampUnit(value) {
        var number = Number(value);
        return isFinite(number) ? Math.max(0, Math.min(1, number)) : 0;
    }

    function focusedScreen() {
        var monitor = Hyprland.focusedMonitor;
        var screens = Quickshell.screens;
        if (monitor) {
            for (var i = 0; i < screens.length; ++i) {
                if (screens[i] && screens[i].name === monitor.name)
                    return screens[i];
            }
        }
        return screens.length > 0 ? screens[0] : null;
    }

    function beginDisplay(kind) {
        displaySerial++;
        displayedKind = boundedText(kind, 32);
        targetScreen = focusedScreen();
        osdVisible = targetScreen !== null;
        hideSerial = displaySerial;
        hideTimer.restart();
        return displaySerial;
    }

    function setDisplay(icon, label, detail, value, progress) {
        displayedIcon = boundedText(icon, 8);
        displayedLabel = boundedText(label, 80);
        displayedDetail = boundedText(detail, 120);
        displayedValue = progress ? clampUnit(value) : -1;
        displayedProgress = !!progress;
    }

    function volumeIcon(volume, muted) {
        if (muted || volume <= 0)
            return "󰝟";
        if (volume >= 0.67)
            return "";
        if (volume >= 0.34)
            return "";
        return "";
    }

    function updateVolume(serial) {
        if (serial !== displaySerial || displayedKind !== "volume")
            return;
        var sink = audioSink;
        if (!sink || !sink.audio) {
            setDisplay("󰝟", "Volume", "No audio output", 0, true);
            return;
        }
        var volume = clampUnit(sink.audio.volume);
        var muted = !!sink.audio.muted;
        setDisplay(volumeIcon(volume, muted), "Volume", muted ? "Muted" : Math.round(volume * 100) + "%", volume, true);
    }

    function updateMicrophone(serial) {
        if (serial !== displaySerial || displayedKind !== "microphone")
            return;
        var source = audioSource;
        if (!source || !source.audio) {
            setDisplay("", "Microphone", "No audio input", -1, false);
            return;
        }
        var muted = !!source.audio.muted;
        setDisplay(muted ? "" : "", "Microphone", muted ? "Muted" : "Live", -1, false);
    }

    function showVolume(): void {
        var serial = beginDisplay("volume");
        updateVolume(serial);
    }

    function showMicrophone(): void {
        var serial = beginDisplay("microphone");
        updateMicrophone(serial);
    }

    function showBrightness(): void {
        var serial = beginDisplay("brightness");
        if (brightnessPercent >= 0)
            setDisplay("󰃠", "Brightness", brightnessPercent + "%", brightnessPercent / 100, true);
        else
            setDisplay("󰃠", "Brightness", "Reading…", 0, true);
        if (!brightnessActive && !brightnessProcess.running)
            startBrightness(0, serial);
        else {
            pendingBrightnessQuery = true;
            pendingBrightnessQuerySerial = serial;
        }
    }

    function showPowerProfile(): void {
        beginDisplay("power-profile");
        if (PowerProfiles.profile === PowerProfile.Performance)
            setDisplay("", "Power profile", "Performance", -1, false);
        else if (PowerProfiles.profile === PowerProfile.PowerSaver)
            setDisplay("", "Power profile", "Power saver", -1, false);
        else if (PowerProfiles.profile === PowerProfile.Balanced)
            setDisplay("", "Power profile", "Balanced", -1, false);
        else
            setDisplay("?", "Power profile", "Unavailable", -1, false);
    }

    function showMessage(icon: string, label: string, detail: string): void {
        beginDisplay("message");
        setDisplay(icon, label, detail, -1, false);
    }

    function adjustVolume(direction) {
        showVolume();
        var suffix = direction > 0 ? "5%+" : "5%-";
        enqueueAudio(["wpctl", "set-volume", "-l", "1", "@DEFAULT_AUDIO_SINK@", suffix], "volume", displaySerial);
    }

    function toggleOutputMute() {
        showVolume();
        enqueueAudio(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"], "volume", displaySerial);
    }

    function toggleMicrophoneMute() {
        showMicrophone();
        enqueueAudio(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"], "microphone", displaySerial);
    }

    function enqueueAudio(command, kind, serial) {
        var queue = audioQueue.slice();
        if (queue.length >= 48)
            queue.shift();
        queue.push({
            "command": command,
            "kind": kind,
            "serial": serial
        });
        audioQueue = queue;
        audioRefreshKind = kind;
        audioRefreshSerial = serial;
        audioSettle.restart();
        startNextAudio();
    }

    function startNextAudio() {
        if (audioActive || audioProcess.running || audioQueue.length === 0)
            return;
        var queue = audioQueue.slice();
        var request = queue.shift();
        audioQueue = queue;
        audioActive = true;
        audioProcessKind = String(request.kind);
        audioProcessSerial = Number(request.serial);
        audioProcess.command = request.command;
        audioProcess.running = true;
        audioWatchdog.restart();
    }

    function finishAudio(exitCode) {
        if (!audioActive)
            return;
        audioWatchdog.stop();
        var failedKind = audioProcessKind;
        var failedSerial = audioProcessSerial;
        audioActive = false;
        if (exitCode !== 0 && failedSerial === displaySerial && displayedKind === failedKind) {
            if (failedKind === "volume")
                setDisplay("󰝟", "Volume", "Audio control unavailable", 0, true);
            else
                setDisplay("", "Microphone", "Audio control unavailable", -1, false);
        }
        Qt.callLater(startNextAudio);
        audioSettle.restart();
    }

    function refreshAudio() {
        if (audioProcess.running || audioActive || audioQueue.length > 0) {
            audioSettle.restart();
            return;
        }
        if (audioRefreshSerial !== displaySerial || audioRefreshKind !== displayedKind)
            return;
        if (audioRefreshKind === "volume")
            updateVolume(audioRefreshSerial);
        else if (audioRefreshKind === "microphone")
            updateMicrophone(audioRefreshSerial);
    }

    function adjustBrightness(direction) {
        var wanted = direction > 0 ? 1 : -1;
        pendingBrightnessQuery = false;
        pendingBrightnessQuerySerial = 0;
        var serial = beginDisplay("brightness");
        if (brightnessPercent >= 0)
            setDisplay("󰃠", "Brightness", "Adjusting… " + brightnessPercent + "%", brightnessPercent / 100, true);
        else
            setDisplay("󰃠", "Brightness", "Adjusting…", 0, true);
        requestBrightness(wanted, serial);
    }

    function requestBrightness(direction, serial) {
        var wanted = direction > 0 ? 1 : -1;
        if (brightnessActive || brightnessProcess.running) {
            pendingBrightnessSteps = Math.max(-20, Math.min(20, pendingBrightnessSteps + wanted));
            pendingBrightnessSerial = serial;
            if (pendingBrightnessSteps === 0) {
                pendingBrightnessQuery = true;
                pendingBrightnessQuerySerial = serial;
            }
            return;
        }
        startBrightness(wanted, serial);
    }

    function startBrightness(direction, serial) {
        if (brightnessActive || brightnessProcess.running)
            return;
        brightnessActive = true;
        brightnessExited = false;
        brightnessStreamFinished = false;
        brightnessExitCode = -1;
        brightnessOutput = "";
        brightnessProcessSerial = serial;
        brightnessOperation = direction === 0 ? "info" : "set";
        if (direction === 0)
            brightnessProcess.command = ["brightnessctl", "-m", "-e4", "info"];
        else {
            var change = Math.min(100, Math.abs(direction) * 5);
            brightnessProcess.command = ["brightnessctl", "-m", "-e4", "-n2", "set", String(change) + (direction > 0 ? "%+" : "%-")];
        }
        brightnessProcess.running = true;
        brightnessWatchdog.restart();
    }

    function parseBrightness(output) {
        var text = String(output === undefined || output === null ? "" : output);
        var match = /^([^,\r\n]+),([^,\r\n]+),(\d+),(\d{1,3})%,(\d+)\r?\n?$/.exec(text);
        if (!match)
            return -1;
        var percent = Number(match[4]);
        return isFinite(percent) && percent >= 0 && percent <= 100 ? Math.round(percent) : -1;
    }

    function tryFinishBrightness() {
        if (!brightnessActive || !brightnessExited || !brightnessStreamFinished)
            return;
        brightnessWatchdog.stop();
        var serial = brightnessProcessSerial;
        var percent = brightnessExitCode === 0 ? parseBrightness(brightnessOutput) : -1;
        brightnessActive = false;
        if (percent >= 0) {
            brightnessPercent = percent;
            if (serial === displaySerial && displayedKind === "brightness")
                setDisplay("󰃠", "Brightness", percent + "%", percent / 100, true);
        } else if (serial === displaySerial && displayedKind === "brightness") {
            setDisplay("󰃠", "Brightness", "Brightness control unavailable", 0, true);
        }
        continueBrightnessQueue();
    }

    function continueBrightnessQueue() {
        var direction = 0;
        var serial = 0;
        var query = false;
        if (pendingBrightnessSteps !== 0) {
            direction = pendingBrightnessSteps;
            serial = pendingBrightnessSerial;
            pendingBrightnessSteps = 0;
            pendingBrightnessSerial = 0;
        } else if (pendingBrightnessQuery) {
            query = true;
            serial = pendingBrightnessQuerySerial;
            pendingBrightnessQuery = false;
            pendingBrightnessQuerySerial = 0;
        } else {
            return;
        }
        Qt.callLater(function () {
            if (!brightnessActive && !brightnessProcess.running)
                startBrightness(direction, serial);
            else {
                if (query) {
                    pendingBrightnessQuery = true;
                    pendingBrightnessQuerySerial = serial;
                } else {
                    pendingBrightnessSteps = Math.max(-20, Math.min(20, pendingBrightnessSteps + direction));
                    pendingBrightnessSerial = serial;
                }
                brightnessRecovery.restart();
            }
        });
    }

    function brightnessTimedOut() {
        if (!brightnessActive)
            return;
        var serial = brightnessProcessSerial;
        brightnessActive = false;
        if (brightnessProcess.running)
            brightnessProcess.running = false;
        if (serial === displaySerial && displayedKind === "brightness")
            setDisplay("󰃠", "Brightness", "Brightness command timed out", 0, true);
        brightnessRecovery.restart();
    }

    Component.onCompleted: Qt.callLater(function () {
        root.dndConnectionArmed = true;
    })

    PwObjectTracker {
        objects: root.audioSink ? [root.audioSink] : []
    }

    PwObjectTracker {
        objects: root.audioSource ? [root.audioSource] : []
    }

    Connections {
        target: root.notificationService
        enabled: root.notificationService !== null
        ignoreUnknownSignals: true

        function onDndChanged() {
            if (!root.dndConnectionArmed || !root.notificationService)
                return;
            var enabled = !!root.notificationService.dnd;
            root.showMessage(enabled ? "" : "", "Do not disturb", enabled ? "On" : "Off");
        }
    }

    Timer {
        id: hideTimer

        interval: 1500
        onTriggered: {
            if (root.hideSerial === root.displaySerial)
                root.osdVisible = false;
        }
    }

    Timer {
        id: audioSettle

        interval: 120
        onTriggered: root.refreshAudio()
    }

    Timer {
        id: audioWatchdog

        interval: 1200
        onTriggered: {
            if (!root.audioActive)
                return;
            var serial = root.audioProcessSerial;
            var kind = root.audioProcessKind;
            root.audioActive = false;
            if (audioProcess.running)
                audioProcess.running = false;
            if (serial === root.displaySerial && kind === root.displayedKind) {
                if (kind === "volume")
                    root.setDisplay("󰝟", "Volume", "Audio command timed out", 0, true);
                else
                    root.setDisplay("", "Microphone", "Audio command timed out", -1, false);
            }
            audioRecovery.restart();
        }
    }

    Timer {
        id: audioRecovery

        interval: 80
        onTriggered: {
            if (audioProcess.running) {
                restart();
                return;
            }
            root.startNextAudio();
            audioSettle.restart();
        }
    }

    Timer {
        id: brightnessWatchdog

        interval: 1800
        onTriggered: root.brightnessTimedOut()
    }

    Timer {
        id: brightnessRecovery

        interval: 100
        onTriggered: {
            if (brightnessProcess.running) {
                restart();
                return;
            }
            root.continueBrightnessQueue();
        }
    }

    Process {
        id: audioProcess

        onExited: function (exitCode) {
            if (root.audioActive)
                root.finishAudio(exitCode);
            else
                audioRecovery.restart();
        }
    }

    Process {
        id: brightnessProcess

        onExited: function (exitCode) {
            if (!root.brightnessActive)
                return;
            root.brightnessExitCode = exitCode;
            root.brightnessExited = true;
            root.tryFinishBrightness();
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (!root.brightnessActive)
                    return;
                root.brightnessOutput = text;
                root.brightnessStreamFinished = true;
                root.tryFinishBrightness();
            }
        }
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "volume-up"
        description: "Increase output volume"
        onPressed: root.adjustVolume(1)
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "volume-down"
        description: "Decrease output volume"
        onPressed: root.adjustVolume(-1)
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "output-mute"
        description: "Toggle output mute"
        onPressed: root.toggleOutputMute()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "microphone-mute"
        description: "Toggle microphone mute"
        onPressed: root.toggleMicrophoneMute()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "brightness-up"
        description: "Increase display brightness"
        onPressed: root.adjustBrightness(1)
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "brightness-down"
        description: "Decrease display brightness"
        onPressed: root.adjustBrightness(-1)
    }

    IpcHandler {
        target: "osd"

        function showVolume(): void {
            root.showVolume();
        }

        function showMicrophone(): void {
            root.showMicrophone();
        }

        function showBrightness(): void {
            root.showBrightness();
        }

        function showPowerProfile(): void {
            root.showPowerProfile();
        }

        function currentKind(): string {
            return root.displayedKind;
        }

        function currentValue(): real {
            return root.displayedValue;
        }

        function isVisible(): bool {
            return root.osdVisible;
        }
    }

    PanelWindow {
        id: osdWindow

        screen: root.targetScreen
        visible: root.osdVisible && root.targetScreen !== null
        color: "transparent"
        implicitWidth: 320
        implicitHeight: 86
        exclusionMode: ExclusionMode.Ignore
        focusable: false
        mask: Region {}
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "quickshell-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.bottom: true
        margins.bottom: 52

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: root.theme.surfaceSolid
            border.width: 1
            border.color: root.theme.surface1

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 13
                color: Qt.rgba(root.theme.base.r, root.theme.base.g, root.theme.base.b, 0.18)
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                width: 42
                horizontalAlignment: Text.AlignHCenter
                text: root.displayedIcon
                textFormat: Text.PlainText
                color: root.displayedKind === "brightness" ? root.theme.yellow : root.displayedKind === "volume" ? root.theme.pink : root.displayedKind === "microphone" ? root.theme.mauve : root.displayedKind === "power-profile" ? root.theme.green : root.theme.blue
                font.family: root.theme.fontFamily
                font.pixelSize: 27
            }

            Item {
                anchors.left: parent.left
                anchors.leftMargin: 76
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Text {
                    id: labelText

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: root.displayedProgress ? 10 : 17
                    text: root.displayedLabel
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                }

                Text {
                    id: detailText

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: labelText.bottom
                    anchors.topMargin: 2
                    text: root.displayedDetail
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.theme.subtext
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    height: 6
                    radius: 3
                    visible: root.displayedProgress
                    color: root.theme.base

                    Rectangle {
                        width: parent.width * root.clampUnit(root.displayedValue)
                        height: parent.height
                        radius: parent.radius
                        color: root.displayedKind === "brightness" ? root.theme.yellow : root.theme.pink
                    }
                }
            }
        }
    }
}
