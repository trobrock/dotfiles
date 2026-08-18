import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property int maximumNetworks: 50
    readonly property int maximumLineBytes: 64 * 1024
    property bool available: false
    property bool powered: false
    property bool scanning: false
    property string stationState: "disconnected"
    property string connectedId: ""
    property var networks: []
    property bool bridgeRunning: bridge.running
    property string bridgeError: "Wi-Fi bridge unavailable"
    property string errorMessage: ""
    property bool busy: pendingSeq >= 0
    property string pendingCommand: ""
    property int pendingSeq: -1
    property int cancelSeq: -1
    property int nextSeq: 1
    property int restartAttempts: 0
    property bool intentionalStop: false
    property bool protocolStopping: false
    readonly property int maximumRestartAttempts: 6

    function validId(value) {
        return typeof value === "string" && /^[A-Za-z0-9._~-]{8,64}$/.test(value);
    }

    function validSeq(value) {
        return typeof value === "number" && isFinite(value) && Math.floor(value) === value && value >= 0 && value <= 2147483647;
    }

    function utf8BytesAtMost(value, maximum) {
        var bytes = 0;
        for (var i = 0; i < value.length; ++i) {
            var code = value.charCodeAt(i);
            if (code <= 0x7f)
                bytes += 1;
            else if (code <= 0x7ff)
                bytes += 2;
            else if (code >= 0xd800 && code <= 0xdbff) {
                if (i + 1 >= value.length)
                    return false;
                var low = value.charCodeAt(++i);
                if (low < 0xdc00 || low > 0xdfff)
                    return false;
                bytes += 4;
            } else if (code >= 0xdc00 && code <= 0xdfff) {
                return false;
            } else {
                bytes += 3;
            }
            if (bytes > maximum)
                return false;
        }
        return true;
    }

    function sanitizedName(value) {
        if (typeof value !== "string")
            return null;
        var clean = value.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu, "");
        clean = clean.replace(/\s+/g, " ").trim();
        return clean.slice(0, 80);
    }

    function hasOnlyKeys(value, required, optional) {
        var keys = Object.keys(value);
        for (var i = 0; i < required.length; ++i) {
            if (!Object.prototype.hasOwnProperty.call(value, required[i]))
                return false;
        }
        for (var j = 0; j < keys.length; ++j) {
            if (required.indexOf(keys[j]) < 0 && optional.indexOf(keys[j]) < 0)
                return false;
        }
        return true;
    }

    function failClosed(message) {
        available = false;
        powered = false;
        scanning = false;
        stationState = "disconnected";
        connectedId = "";
        networks = [];
        clearPending();
        bridgeError = message || "Wi-Fi bridge returned invalid data";
        if (message === "Wi-Fi bridge returned invalid data")
            stopUntrustedBridge();
    }

    function stopUntrustedBridge() {
        if (protocolStopping)
            return;
        protocolStopping = true;
        intentionalStop = false;
        Qt.callLater(function() {
            if (bridge.running)
                bridge.running = false;
        });
    }

    function clearPending() {
        pendingSeq = -1;
        pendingCommand = "";
        cancelSeq = -1;
    }

    function allocateSeq() {
        var value = nextSeq;
        nextSeq = value >= 2147483647 ? 1 : value + 1;
        return value;
    }

    function writeMessage(message) {
        if (!bridge.running)
            return false;
        var line = "";
        try {
            line = JSON.stringify(message);
            if (typeof line !== "string" || !utf8BytesAtMost(line, 16 * 1024))
                return false;
            bridge.write(line + "\n");
            line = "";
            return true;
        } catch (error) {
            line = "";
            return false;
        }
    }

    function sendMutation(command, fields) {
        if (busy || !available || !bridge.running)
            return false;
        var seq = allocateSeq();
        var message = {
            "command": command,
            "seq": seq
        };
        if (fields) {
            for (var key in fields)
                message[key] = fields[key];
        }
        if (!writeMessage(message)) {
            errorMessage = "Wi-Fi bridge is unavailable";
            return false;
        }
        pendingSeq = seq;
        pendingCommand = command;
        errorMessage = "";
        return true;
    }

    function scan() {
        if (!powered || scanning)
            return false;
        return sendMutation("scan", null);
    }

    function setPowered(enabled) {
        if (typeof enabled !== "boolean")
            return false;
        return sendMutation("power", {
            "enabled": enabled
        });
    }

    function disconnect() {
        return sendMutation("disconnect", null);
    }

    function connectNetwork(id, passphrase) {
        if (!validId(id))
            return false;
        var message = {
            "id": id
        };
        var secret = passphrase;
        if (secret !== undefined && secret !== null) {
            if (typeof secret !== "string" || !/^[\x20-\x7e]{8,63}$/.test(secret)) {
                secret = "";
                return false;
            }
            message.passphrase = secret;
        }
        var sent = sendMutation("connect", message);
        if (message.passphrase !== undefined) {
            message.passphrase = "";
            delete message.passphrase;
        }
        secret = "";
        return sent;
    }

    function forgetNetwork(id) {
        if (!validId(id))
            return false;
        return sendMutation("forget", {
            "id": id
        });
    }

    function setAutoconnect(id, enabled) {
        if (!validId(id) || typeof enabled !== "boolean")
            return false;
        return sendMutation("autoconnect", {
            "id": id,
            "enabled": enabled
        });
    }

    function cancel() {
        if (!busy || cancelSeq >= 0 || !bridge.running)
            return false;
        var seq = allocateSeq();
        if (!writeMessage({
                "command": "cancel",
                "seq": seq
            }))
            return false;
        cancelSeq = seq;
        return true;
    }

    function restartBridge() {
        if (available || restartTimer.running)
            return;
        restartAttempts = 0;
        intentionalStop = bridge.running;
        if (bridge.running)
            bridge.running = false;
        else {
            intentionalStop = false;
            restartTimer.interval = 100;
            restartTimer.restart();
        }
    }

    function validNetwork(raw) {
        if (!raw || typeof raw !== "object" || Array.isArray(raw) || !hasOnlyKeys(raw, ["id", "name", "type", "connected", "known", "autoconnect", "signal"], []))
            return null;
        if (!validId(raw.id) || typeof raw.name !== "string")
            return null;
        var name = sanitizedName(raw.name);
        if (name === null || name.length > 80)
            return null;
        if (["open", "psk", "8021x", "wep", "unknown"].indexOf(raw.type) < 0)
            return null;
        if (typeof raw.connected !== "boolean" || typeof raw.known !== "boolean" || typeof raw.autoconnect !== "boolean")
            return null;
        if (typeof raw.signal !== "number" || !isFinite(raw.signal) || Math.floor(raw.signal) !== raw.signal || raw.signal < 0 || raw.signal > 4)
            return null;
        if (!raw.known && raw.autoconnect)
            return null;
        return {
            "id": raw.id,
            "name": name,
            "type": raw.type,
            "connected": raw.connected,
            "known": raw.known,
            "autoconnect": raw.autoconnect,
            "signal": raw.signal
        };
    }

    function applySnapshot(raw) {
        var states = ["connected", "disconnected", "connecting", "disconnecting", "roaming"];
        if (!hasOnlyKeys(raw, ["event", "status", "code", "available", "powered", "scanning", "stationState", "connectedId", "networks"], ["seq"]) || raw.event !== "snapshot" || (raw.status !== "ok" && raw.status !== "error") || (raw.status === "ok") !== (raw.code === "ok") || (raw.code !== "ok" && raw.code !== "failed") || typeof raw.available !== "boolean" || typeof raw.powered !== "boolean" || typeof raw.scanning !== "boolean" || states.indexOf(raw.stationState) < 0 || !Array.isArray(raw.networks) || raw.networks.length > maximumNetworks) {
            failClosed("Wi-Fi bridge returned invalid data");
            return false;
        }
        if (raw.connectedId !== null && !validId(raw.connectedId)) {
            failClosed("Wi-Fi bridge returned invalid data");
            return false;
        }
        if (!raw.available && (raw.powered || raw.scanning || raw.connectedId !== null || raw.networks.length !== 0)) {
            failClosed("Wi-Fi bridge returned invalid data");
            return false;
        }
        var bounded = [];
        var ids = Object.create(null);
        var connectedRows = 0;
        var connectedRowId = "";
        for (var i = 0; i < raw.networks.length; ++i) {
            var network = validNetwork(raw.networks[i]);
            if (!network || ids[network.id] === true) {
                failClosed("Wi-Fi bridge returned invalid data");
                return false;
            }
            ids[network.id] = true;
            if (network.connected) {
                connectedRows++;
                connectedRowId = network.id;
            }
            bounded.push(network);
        }
        if (connectedRows > 1 || (raw.connectedId !== null && (ids[raw.connectedId] !== true || connectedRowId !== raw.connectedId)) || (raw.connectedId === null && connectedRows === 1 && raw.stationState !== "connecting") || (raw.connectedId === null && raw.stationState === "connected")) {
            failClosed("Wi-Fi bridge returned invalid data");
            return false;
        }
        available = raw.available;
        powered = raw.available && raw.powered;
        scanning = raw.available && raw.scanning;
        stationState = raw.stationState;
        connectedId = raw.connectedId === null ? "" : raw.connectedId;
        networks = bounded;
        bridgeError = raw.available ? "" : "Wi-Fi unavailable";
        return true;
    }

    function resultMessage(code) {
        var messages = {
            "aborted": "Wi-Fi operation was aborted",
            "busy": "Wi-Fi is busy",
            "canceled": "Wi-Fi operation was canceled",
            "failed": "Wi-Fi operation failed",
            "invalid_request": "Wi-Fi request was rejected",
            "no_agent": "Wi-Fi credentials are unavailable",
            "not_configured": "Wi-Fi network is not configured",
            "not_connected": "Wi-Fi is not connected",
            "not_found": "Wi-Fi network is no longer available",
            "secret_required": "A Wi-Fi password is required",
            "stale_id": "Wi-Fi network list changed; try again",
            "timeout": "Wi-Fi operation timed out",
            "unavailable": "Wi-Fi is unavailable",
            "unsupported": "This Wi-Fi security type is unsupported"
        };
        return messages[code] || "Wi-Fi operation failed";
    }

    function handleResult(raw) {
        var commands = ["snapshot", "scan", "power", "disconnect", "connect", "forget", "autoconnect", "cancel", "invalid"];
        var codes = ["ok", "aborted", "busy", "canceled", "failed", "invalid_request", "no_agent", "not_configured", "not_connected", "not_found", "secret_required", "stale_id", "timeout", "unavailable", "unsupported"];
        if (!hasOnlyKeys(raw, ["event", "command", "status", "code"], ["seq"]) || commands.indexOf(raw.command) < 0 || codes.indexOf(raw.code) < 0 || (raw.status !== "ok" && raw.status !== "error") || (raw.status === "ok") !== (raw.code === "ok") || (raw.seq !== undefined && !validSeq(raw.seq))) {
            failClosed("Wi-Fi bridge returned invalid data");
            return;
        }
        if (raw.seq === undefined)
            return;
        if (raw.command === "cancel") {
            if (raw.seq === cancelSeq)
                cancelSeq = -1;
            return;
        }
        if (raw.seq !== pendingSeq || raw.command !== pendingCommand)
            return;
        errorMessage = raw.code === "ok" ? "" : resultMessage(raw.code);
        clearPending();
    }

    function handleLine(line) {
        if (typeof line !== "string" || line.length > maximumLineBytes || !utf8BytesAtMost(line, maximumLineBytes)) {
            failClosed("Wi-Fi bridge returned invalid data");
            return;
        }
        var raw = null;
        try {
            raw = JSON.parse(line);
        } catch (error) {
            failClosed("Wi-Fi bridge returned invalid data");
            return;
        }
        if (!raw || typeof raw !== "object" || Array.isArray(raw) || (raw.event !== "snapshot" && raw.event !== "result") || (raw.status !== "ok" && raw.status !== "error") || typeof raw.code !== "string") {
            failClosed("Wi-Fi bridge returned invalid data");
            return;
        }
        if (raw.event === "snapshot") {
            if (["ok", "failed"].indexOf(raw.code) < 0 || (raw.status === "ok") !== (raw.code === "ok") || (raw.status === "error" && raw.available !== false) || (raw.seq !== undefined && !validSeq(raw.seq))) {
                failClosed("Wi-Fi bridge returned invalid data");
                return;
            }
            applySnapshot(raw);
        } else {
            handleResult(raw);
        }
    }

    Component.onCompleted: bridge.running = true

    Process {
        id: bridge

        command: Quickshell.env("QUICKSHELL_WIFI_FIXTURE") === "1" ? [Quickshell.env("HOME") + "/.local/bin/quickshell-iwd", "--fixture"] : [Quickshell.env("HOME") + "/.local/bin/quickshell-iwd"]
        stdinEnabled: true
        onStarted: {
            root.intentionalStop = false;
            root.protocolStopping = false;
            root.bridgeError = "";
            restartStable.restart();
            root.writeMessage({
                "command": "snapshot",
                "seq": root.allocateSeq()
            });
        }
        onExited: function(exitCode, exitStatus) {
            restartStable.stop();
            root.protocolStopping = false;
            root.failClosed("Wi-Fi bridge unavailable");
            root.clearPending();
            if (root.intentionalStop) {
                root.intentionalStop = false;
                restartTimer.interval = 100;
                restartTimer.restart();
            } else if (root.restartAttempts < root.maximumRestartAttempts) {
                restartTimer.interval = Math.min(30000, 500 * Math.pow(2, root.restartAttempts));
                root.restartAttempts++;
                restartTimer.restart();
            } else {
                root.bridgeError = "Wi-Fi bridge restart limit reached";
            }
        }

        stdout: SplitParser {
            onRead: function(line) {
                root.handleLine(line);
            }
        }

        stderr: SplitParser {
            onRead: function(line) {
                root.bridgeError = "Wi-Fi bridge reported an error";
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

    Timer {
        id: restartStable

        interval: 60000
        onTriggered: root.restartAttempts = 0
    }
}
