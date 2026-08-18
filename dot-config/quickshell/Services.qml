import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// One shared service instance feeds every monitor's bar.
Item {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configDir: Quickshell.shellDir
    readonly property string agentUsageExecutable: String(Quickshell.env("AI_USAGE_COMMAND") || "").trim() || home + "/.local/bin/ai-usage"
    property var calendar: ({
        "text": "",
        "tooltip": "Calendar unavailable"
    })
    property var tailscale: ({
        "available": false,
        "connected": false,
        "icon": "󰖪",
        "text": "",
        "tooltip": "Tailscale unavailable"
    })
    property var recording: ({
        "text": "",
        "tooltip": ""
    })
    property var network: ({
        "connected": false,
        "kind": "unknown",
        "icon": "󰖪",
        "tooltip": "Network status unavailable"
    })
    property var agentUsage: null
    property bool agentUsageRefreshing: false
    property string agentUsageError: "Waiting for usage data"
    property bool agentUsageRunActive: false
    property bool agentUsageProcessStarted: false
    property bool agentUsageProcessExited: false
    property bool agentUsageStreamFinished: false
    property bool agentUsageResponseValid: false
    property bool agentUsageResponseInvalid: false
    property int agentUsageExitCode: 0
    property int agentUsagePendingMode: 0
    property bool agentLimitsRetryUsed: false
    readonly property int agentUsageLimitsMode: 1
    readonly property int agentUsageNormalMode: 2
    readonly property int agentUsageForceMode: 3
    property bool powerProfilesAvailable: false
    property string powerProfilesState: "unknown"
    property bool powerProfileProbeActive: false
    property bool powerProfileProbeResponseValid: false
    property bool powerProfileProbeExited: false
    property string powerProfileProbeResult: ""
    property string voxText: "󰍭"
    property string voxTooltip: "VoxType starting…"
    property bool voxAvailable: false
    property int voxRestartAttempts: 0
    readonly property int voxMaxRestartAttempts: 6
    property bool voxAttemptActive: false
    property bool voxLaunchPending: false
    property bool voxProcessStarted: false
    property bool idleInhibited: false
    readonly property var audioSink: Pipewire.defaultAudioSink

    function objectOrFallback(raw, fallback) {
        try {
            var parsed = JSON.parse(String(raw || "").trim());
            return parsed && typeof parsed === "object" ? parsed : fallback;
        } catch (error) {
            return fallback;
        }
    }

    function applyScript(name, raw, fallback) {
        root[name] = objectOrFallback(raw, fallback);
    }

    function applyCalendar(raw) {
        var parsed = objectOrFallback(raw, null);
        if (!parsed || Array.isArray(parsed) || typeof parsed.title !== "string") {
            calendar = {
                "text": "",
                "tooltip": "Calendar unavailable"
            };
            return ;
        }
        var title = parsed.title.trim();
        calendar = {
            "text": title,
            "tooltip": typeof parsed.tooltip === "string" && parsed.tooltip.trim() !== "" ? parsed.tooltip : title || "Calendar"
        };
    }

    function applyRecording(raw) {
        var active = String(raw || "").trim() === "recording";
        recording = active ? {
            "text": "󰻂",
            "tooltip": "Stop screen recording"
        } : {
            "text": "",
            "tooltip": ""
        };
    }

    function agentUsagePayload(raw) {
        var parsed = objectOrFallback(raw, null);
        if (!parsed || Array.isArray(parsed) || parsed.schemaVersion !== 1 || !Array.isArray(parsed.providers) || !Array.isArray(parsed.errors) || !parsed.sync || typeof parsed.sync !== "object" || Array.isArray(parsed.sync))
            return null;

        return parsed;
    }

    function agentUsageMessage(entry) {
        if (typeof entry === "string")
            return entry.trim();

        if (!entry || typeof entry !== "object" || Array.isArray(entry))
            return "";

        return String(entry.message || entry.error || entry.detail || entry.state || "").trim();
    }

    function agentUsagePayloadError(payload) {
        var messages = [];
        for (var i = 0; i < payload.errors.length; i++) {
            var message = agentUsageMessage(payload.errors[i]);
            if (message !== "" && messages.indexOf(message) < 0)
                messages.push(message);

        }
        var rawStatus = payload.sync.statusText || payload.sync.error || payload.sync.status || "";
        var syncStatus = agentUsageMessage(rawStatus);
        var normalizedStatus = syncStatus.toLowerCase();
        if (syncStatus !== "" && normalizedStatus !== "ok" && normalizedStatus !== "ready" && messages.indexOf(syncStatus) < 0)
            messages.push(syncStatus);

        return messages.join(" · ");
    }

    function agentUsageNeedsLimitsRetry(payload) {
        for (var i = 0; i < payload.providers.length; i++) {
            var provider = payload.providers[i];
            if (!provider || typeof provider !== "object" || Array.isArray(provider))
                continue;

            var providerId = String(provider.providerId || provider.id || "").trim();
            if (providerId !== "" && provider.retryAdvised === true)
                return true;

        }
        return false;
    }

    function updateAgentLimitsRetry(payload) {
        if (!agentUsageNeedsLimitsRetry(payload)) {
            agentLimitsRetry.stop();
            agentLimitsRetryUsed = false;
            return ;
        }
        if (!agentLimitsRetry.running && !agentLimitsRetryUsed)
            agentLimitsRetry.restart();

    }

    function applyAgentUsage(raw) {
        if (!agentUsageRunActive)
            return false;

        var parsed = agentUsagePayload(raw);
        if (!parsed) {
            agentUsageResponseValid = false;
            agentUsageResponseInvalid = true;
            agentUsageError = "AI usage helper returned invalid data";
            return false;
        }
        agentUsage = parsed;
        agentUsageResponseValid = true;
        agentUsageResponseInvalid = false;
        agentUsageError = agentUsagePayloadError(parsed);
        updateAgentLimitsRetry(parsed);
        return true;
    }

    function receiveAgentUsage(raw) {
        if (!agentUsageRunActive)
            return ;

        agentUsageStreamFinished = true;
        applyAgentUsage(raw);
        if (agentUsageProcessExited) {
            agentUsageDrainFallback.stop();
            finishAgentUsage();
        }
    }

    function setTailscaleUnavailable(message) {
        tailscale = {
            "available": false,
            "connected": false,
            "icon": "󰖪",
            "text": "",
            "tooltip": message || "Tailscale unavailable"
        };
    }

    function applyTailscale(raw) {
        var parsed = objectOrFallback(raw, null);
        var name = parsed && parsed.CurrentTailnet && typeof parsed.CurrentTailnet.Name === "string" ? parsed.CurrentTailnet.Name.trim() : "";
        var connected = parsed && parsed.BackendState === "Running" && name !== "";
        if (!connected) {
            setTailscaleUnavailable("Tailscale disconnected or unavailable");
            return ;
        }
        tailscale = {
            "available": true,
            "connected": true,
            "icon": "",
            "text": name,
            "tooltip": "Tailscale VPN\nConnected as: " + name
        };
    }

    function setVoxUnavailable(message) {
        voxAvailable = false;
        voxText = "󰍭";
        voxTooltip = message || "VoxType unavailable";
    }

    function applyVox(raw) {
        var parsed = objectOrFallback(raw, null);
        var text = parsed && typeof parsed.text === "string" ? parsed.text.trim() : parsed && typeof parsed.icon === "string" ? parsed.icon.trim() : "";
        if (!text || text.toLowerCase() === "null") {
            setVoxUnavailable("VoxType unavailable (invalid status data)");
            return ;
        }
        voxLaunchPending = false;
        voxWatchdog.stop();
        voxAvailable = true;
        voxRestartAttempts = 0;
        voxText = text;
        voxTooltip = String(parsed.tooltip || parsed.status || "VoxType ready");
    }

    function handleVoxFailure(reason) {
        voxAvailable = false;
        if (voxRestartAttempts >= voxMaxRestartAttempts) {
            setVoxUnavailable("VoxType unavailable (" + reason + "; restart limit reached)");
            return ;
        }
        voxRestartAttempts++;
        setVoxUnavailable("VoxType unavailable (" + reason + ") · restarting in 10s (" + voxRestartAttempts + "/" + voxMaxRestartAttempts + ")");
        voxRestart.restart();
    }

    function startVoxMonitor() {
        if (voxProcess.running || voxAttemptActive)
            return ;

        voxAttemptActive = true;
        voxLaunchPending = true;
        voxProcessStarted = false;
        setVoxUnavailable("VoxType starting…");
        voxWatchdog.restart();
        voxProcess.running = true;
    }

    function applyPowerProfileProbe(raw) {
        if (!powerProfileProbeActive)
            return ;

        var profile = String(raw || "").trim().toLowerCase();
        if (profile !== "power-saver" && profile !== "balanced" && profile !== "performance")
            return ;

        powerProfileProbeResponseValid = true;
        powerProfileProbeResult = profile;
        if (powerProfileProbeExited)
            finishPowerProfileProbe();

    }

    function finishPowerProfileProbe() {
        if (!powerProfileProbeActive || !powerProfileProbeResponseValid)
            return ;

        powerProfileProbeActive = false;
        powerProfileWatchdog.stop();
        powerProfilesAvailable = true;
        powerProfilesState = powerProfileProbeResult;
    }

    function setPowerProfilesUnavailable() {
        powerProfilesAvailable = false;
        powerProfilesState = "unavailable";
    }

    function probePowerProfiles() {
        if (powerProfileProcess.running || powerProfileProbeActive)
            return ;

        powerProfileProbeResponseValid = false;
        powerProfileProbeExited = false;
        powerProfileProbeResult = "";
        powerProfileProbeActive = true;
        powerProfileWatchdog.restart();
        powerProfileProcess.running = true;
    }

    function runDetached(argv) {
        try {
            Quickshell.execDetached(argv);
        } catch (error) {
            console.warn("quickshell-bar command failed:", argv[0], error);
        }
    }

    function openCalendarEvent() {
        runDetached([home + "/.config/scripts/open_calendar_event.sh"]);
    }

    function openTailscale() {
        runDetached(["ghostty", "-e", home + "/.config/scripts/tailscale-switch"]);
    }

    function toggleRecording() {
        runDetached([home + "/.config/scripts/record-screen", "--stop"]);
    }

    function restartVox() {
        runDetached(["systemctl", "--user", "restart", "voxtype"]);
        voxRestartAttempts = 0;
        if (!voxProcess.running && !voxAttemptActive) {
            voxRestart.stop();
            startVoxMonitor();
        }
    }

    function openPavucontrol() {
        runDetached(["pavucontrol"]);
    }

    function launchAiAgent() {
        var raw = String(Quickshell.env("AI_USAGE_AGENT_COMMAND") || "").trim();
        var command = [];
        if (raw !== "") {
            try {
                var configured = JSON.parse(raw);
                if (Array.isArray(configured) && configured.length > 0) {
                    var valid = true;
                    for (var i = 0; i < configured.length; i++) {
                        if (typeof configured[i] !== "string" || configured[i] === "" || configured[i].indexOf("\u0000") >= 0) {
                            valid = false;
                            break;
                        }
                        command.push(configured[i]);
                    }
                    if (!valid)
                        command = [];

                }
            } catch (error) {
                if (!/\s/.test(raw) && raw.indexOf("\u0000") < 0)
                    command = [raw];

            }
        }
        if (command.length === 0)
            command = ["ghostty", "-e", home + "/.local/bin/pi"];

        runDetached(command);
    }

    function requestAgentUsage(mode) {
        if (agentUsageCommand.running || agentUsageRunActive) {
            agentUsagePendingMode = Math.max(agentUsagePendingMode, mode);
            if (!agentUsageRunActive)
                agentUsageRestart.restart();

            return ;
        }
        if (mode === agentUsageForceMode)
            agentUsageCommand.command = [agentUsageExecutable, "update", "--force"];
        else if (mode === agentUsageLimitsMode)
            agentUsageCommand.command = [agentUsageExecutable, "refresh-limits"];
        else
            agentUsageCommand.command = [agentUsageExecutable, "update"];
        agentUsageResponseValid = false;
        agentUsageResponseInvalid = false;
        agentUsageExitCode = 0;
        agentUsageRefreshing = true;
        agentUsageRunActive = true;
        agentUsageProcessStarted = false;
        agentUsageProcessExited = false;
        agentUsageStreamFinished = false;
        agentUsageDrainFallback.stop();
        agentUsageWatchdog.restart();
        try {
            agentUsageCommand.running = true;
        } catch (error) {
            agentUsageRunActive = false;
            agentUsageRefreshing = false;
            agentUsageWatchdog.stop();
            agentUsageError = "AI usage helper failed to start";
        }
    }

    function refreshAgentUsage(force) {
        requestAgentUsage(force === true ? agentUsageForceMode : agentUsageNormalMode);
    }

    function refreshAgentLimits() {
        requestAgentUsage(agentUsageLimitsMode);
    }

    function finishAgentUsage() {
        if (!agentUsageRunActive)
            return ;

        agentUsageRunActive = false;
        agentUsageRefreshing = false;
        agentUsageWatchdog.stop();
        agentUsageDrainFallback.stop();
        if (!agentUsageProcessStarted && !agentUsageResponseValid)
            agentUsageError = "AI usage helper failed to start";
        else if (!agentUsageResponseValid && !agentUsageResponseInvalid)
            agentUsageError = agentUsageExitCode !== 0 ? "AI usage helper failed (exit " + agentUsageExitCode + ")" : "AI usage helper returned no valid data";
        else if (agentUsageExitCode !== 0 && agentUsageError === "")
            agentUsageError = "AI usage helper failed (exit " + agentUsageExitCode + ")";
        if (agentUsagePendingMode > 0)
            agentUsageRestart.restart();

    }

    Component.onCompleted: root.startVoxMonitor()

    PwObjectTracker {
        objects: root.audioSink ? [root.audioSink] : []
    }

    Process {
        id: calendarProcess

        command: [root.home + "/.config/scripts/calendar.sh"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyCalendar(text)
        }

    }

    Process {
        id: tailscaleProcess

        command: ["tailscale", "status", "--json"]
        onExited: function(code) {
            if (code !== 0)
                root.setTailscaleUnavailable("Tailscale status failed (exit " + code + ")");

        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyTailscale(text)
        }

    }

    Process {
        id: recordingProcess

        command: [root.home + "/.config/scripts/record-screen", "--status"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyRecording(text)
        }

    }

    Process {
        id: networkProcess

        command: [root.configDir + "/scripts/network-status"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.network = root.objectOrFallback(text, ({
                "connected": false,
                "kind": "unknown",
                "icon": "󰖪",
                "tooltip": "Network unavailable"
            }))
        }

    }

    Process {
        id: agentUsageCommand

        onStarted: {
            if (root.agentUsageRunActive) {
                root.agentUsageProcessStarted = true;
                agentUsageWatchdog.restart();
            }
        }
        onExited: function(code) {
            if (!root.agentUsageRunActive)
                return ;

            root.agentUsageExitCode = code;
            root.agentUsageProcessExited = true;
            agentUsageWatchdog.stop();
            if (root.agentUsageStreamFinished)
                root.finishAgentUsage();
            else
                agentUsageDrainFallback.restart();
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.receiveAgentUsage(text)
        }

    }

    Timer {
        id: agentUsageDrainFallback

        interval: 1000
        onTriggered: {
            if (root.agentUsageRunActive && root.agentUsageProcessExited)
                root.finishAgentUsage();

        }
    }

    Timer {
        id: agentUsageRestart

        interval: 100
        onTriggered: {
            if (agentUsageCommand.running) {
                restart();
                return ;
            }
            var mode = root.agentUsagePendingMode;
            root.agentUsagePendingMode = 0;
            if (mode > 0)
                root.requestAgentUsage(mode);

        }
    }

    Timer {
        id: agentUsageWatchdog

        interval: root.agentUsageProcessStarted ? 310000 : 5000
        onTriggered: {
            if (!root.agentUsageRunActive)
                return ;

            root.agentUsageRunActive = false;
            root.agentUsageRefreshing = false;
            agentUsageDrainFallback.stop();
            root.agentUsageError = root.agentUsageProcessStarted ? "AI usage helper timed out" : "AI usage helper failed to start";
            if (agentUsageCommand.running)
                agentUsageCommand.running = false;

            if (root.agentUsagePendingMode > 0)
                agentUsageRestart.restart();

        }
    }

    Timer {
        id: agentLimitsRetry

        interval: 30000
        onTriggered: {
            root.agentLimitsRetryUsed = true;
            root.refreshAgentLimits();
        }
    }

    Process {
        id: powerProfileProcess

        command: ["powerprofilesctl", "get"]
        onExited: function(code) {
            if (!root.powerProfileProbeActive)
                return ;

            powerProfileWatchdog.stop();
            if (code !== 0) {
                root.powerProfileProbeActive = false;
                root.setPowerProfilesUnavailable();
            } else {
                root.powerProfileProbeExited = true;
                root.finishPowerProfileProbe();
                if (root.powerProfileProbeActive)
                    powerProfileFinalize.restart();

            }
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyPowerProfileProbe(text)
        }

    }

    Timer {
        id: powerProfileFinalize

        interval: 100
        onTriggered: {
            if (!root.powerProfileProbeActive)
                return ;

            root.powerProfileProbeActive = false;
            if (!root.powerProfileProbeResponseValid)
                root.setPowerProfilesUnavailable();

        }
    }

    Timer {
        id: powerProfileWatchdog

        interval: 5000
        onTriggered: {
            if (!root.powerProfileProbeActive)
                return ;

            root.powerProfileProbeActive = false;
            root.setPowerProfilesUnavailable();
            if (powerProfileProcess.running)
                powerProfileProcess.running = false;

        }
    }

    Process {
        id: voxProcess

        command: ["/usr/local/bin/voxtype", "status", "--follow", "--format", "json"]
        onStarted: {
            if (root.voxAttemptActive) {
                root.voxProcessStarted = true;
                voxWatchdog.restart();
            }
        }
        onExited: function(code) {
            if (!root.voxAttemptActive)
                return ;

            root.voxAttemptActive = false;
            root.voxLaunchPending = false;
            voxWatchdog.stop();
            root.handleVoxFailure("status exited " + code);
        }

        stdout: SplitParser {
            onRead: function(line) {
                root.applyVox(line);
            }
        }

    }

    Timer {
        id: voxWatchdog

        interval: root.voxProcessStarted ? 10000 : 5000
        onTriggered: {
            if (!root.voxAttemptActive || !root.voxLaunchPending)
                return ;

            root.voxAttemptActive = false;
            root.voxLaunchPending = false;
            if (voxProcess.running)
                voxProcess.running = false;

            root.handleVoxFailure(root.voxProcessStarted ? "status helper returned no data" : "status helper did not start");
        }
    }

    Timer {
        id: voxRestart

        interval: 10000
        onTriggered: root.startVoxMonitor()
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.probePowerProfiles()
    }

    Timer {
        interval: 300000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!calendarProcess.running)
                calendarProcess.running = true;

        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!tailscaleProcess.running)
                tailscaleProcess.running = true;

        }
    }

    Timer {
        interval: 900000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshAgentUsage(false)
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!recordingProcess.running)
                recordingProcess.running = true;

        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!networkProcess.running)
                networkProcess.running = true;

        }
    }

}
