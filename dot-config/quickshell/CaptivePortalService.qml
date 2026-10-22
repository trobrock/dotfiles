import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string status: "disconnected"
    property string portalUrl: ""
    property bool dnsOverride: false
    property string errorMessage: ""
    property bool bridgeRunning: bridge.running
    property int restartAttempts: 0
    property bool shuttingDown: false
    readonly property bool signInRequired: status === "captive"
    readonly property int maximumLineBytes: 4096
    readonly property int maximumRestartAttempts: 6

    function failClosed(message) {
        status = "disconnected";
        portalUrl = "";
        dnsOverride = false;
        errorMessage = message;
    }

    function writeCommand(command) {
        if (!bridge.running || ["open", "check", "stop"].indexOf(command) < 0)
            return false;
        try {
            bridge.write(JSON.stringify({ "command": command }) + "\n");
            return true;
        } catch (error) {
            errorMessage = "Captive portal assistant is unavailable";
            return false;
        }
    }

    function openPortal() {
        return signInRequired && writeCommand("open");
    }

    function checkAgain() {
        return writeCommand("check");
    }

    function validUrl(value) {
        if (typeof value !== "string" || value.length > 2048 || /[\x00-\x1f\x7f]/.test(value))
            return false;
        return /^https?:\/\/[^\s/@]+(?::[0-9]+)?(?:[/?#]|$)/i.test(value);
    }

    function handleLine(line) {
        if (typeof line !== "string" || line.length === 0 || line.length > maximumLineBytes) {
            failClosed("Captive portal assistant returned invalid data");
            return;
        }
        var raw = null;
        try {
            raw = JSON.parse(line);
        } catch (error) {
            failClosed("Captive portal assistant returned invalid data");
            return;
        }
        if (!raw || typeof raw !== "object" || Array.isArray(raw)
                || Object.keys(raw).sort().join(",") !== "dnsOverride,error,event,status,url"
                || raw.event !== "status"
                || ["disconnected", "checking", "online", "captive", "offline"].indexOf(raw.status) < 0
                || typeof raw.url !== "string" || typeof raw.dnsOverride !== "boolean" || typeof raw.error !== "string"
                || raw.error.length > 160 || (raw.url !== "" && !validUrl(raw.url))
                || (raw.status === "captive") !== (raw.url !== "")) {
            failClosed("Captive portal assistant returned invalid data");
            return;
        }
        status = raw.status;
        portalUrl = raw.url;
        dnsOverride = raw.dnsOverride;
        errorMessage = raw.error;
        restartAttempts = 0;
    }

    Component.onCompleted: bridge.running = true
    Component.onDestruction: {
        shuttingDown = true;
        writeCommand("stop");
    }

    Process {
        id: bridge

        command: [Quickshell.env("HOME") + "/.local/bin/quickshell-captive-portal"]
        stdinEnabled: true
        onStarted: {
            root.errorMessage = "";
        }
        onExited: function(exitCode, exitStatus) {
            root.status = "disconnected";
            root.portalUrl = "";
            root.dnsOverride = false;
            root.errorMessage = "Captive portal assistant is unavailable";
            if (!root.shuttingDown && root.restartAttempts < root.maximumRestartAttempts) {
                restartTimer.interval = Math.min(30000, 500 * Math.pow(2, root.restartAttempts));
                root.restartAttempts++;
                restartTimer.restart();
            }
        }

        stdout: SplitParser {
            onRead: function(line) {
                root.handleLine(line);
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 500
        onTriggered: {
            if (!bridge.running)
                bridge.running = true;
        }
    }
}
