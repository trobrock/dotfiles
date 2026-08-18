import QtQuick
import Quickshell
import Quickshell.Io
import "TailscaleModel.js" as Model

Item {
    id: root

    property bool panelActive: false
    readonly property string helperExecutable: Quickshell.env("HOME") + "/.local/bin/quickshell-tailscale"

    property bool installed: false
    property bool running: false
    property bool needsLogin: false
    property bool active: false
    property string statusText: "Tailscale unavailable"
    property string selfName: ""
    property string selfDnsName: ""
    property string selfIp: ""
    property bool fileSharing: false
    property var peers: []
    property var accounts: []
    property var selectedAccount: ({
        "id": "",
        "nickname": "",
        "tailnet": "",
        "account": "",
        "selected": false,
        "label": ""
    })
    property string selectedAccountId: ""
    property string selectedAccountLabel: ""
    property var tailnetExitNodes: []
    property var mullvadRegions: []
    property string actionStatus: ""
    property string errorMessage: ""
    property bool accountsAccessDenied: false

    // A mutation remains private until a newly requested status snapshot validates it.
    // Treat it as busy so no other action can race the validation run.
    property var pendingMutation: null
    readonly property bool busy: activeActionId > 0 || pendingMutation !== null
    property int activeActionId: 0
    property int lastStartedActionId: 0
    property int lastFinishedActionId: 0
    property int lastSuccessfulActionId: 0
    property int lastFailedActionId: 0
    property int nextActionId: 1

    readonly property int refreshTimeoutMs: 15000
    readonly property int actionTimeoutMs: 45000
    readonly property int taildropTimeoutMs: 10 * 60 * 1000
    readonly property int loginOutputLimit: 16 * 1024
    readonly property int refreshFreshMs: 60000
    readonly property int maximumFiles: 32
    readonly property int publicTextLimit: 120
    readonly property int stderrHintLimit: 4096

    property string backendState: ""
    property string retainedAuthUrl: ""
    readonly property bool loginReady: Model.validateAuthUrl(retainedAuthUrl) !== ""
    property string selfUserId: ""
    property var exitNodeList: []
    property double statusUpdatedAt: 0
    property double accountsUpdatedAt: 0
    property double exitUpdatedAt: 0

    property bool statusRunActive: false
    property bool statusStarted: false
    property bool statusExited: false
    property bool statusStdoutDone: false
    property bool statusStderrDone: false
    property bool statusTimedOut: false
    property bool statusRestartPending: false
    property int statusRunSerial: 0
    property int statusExitCode: 0
    property string statusStdoutText: ""
    property string statusStderrText: ""

    property bool accountsRunActive: false
    property bool accountsStarted: false
    property bool accountsExited: false
    property bool accountsStdoutDone: false
    property bool accountsStderrDone: false
    property bool accountsTimedOut: false
    property bool accountsRestartPending: false
    property int accountsExitCode: 0
    property string accountsStdoutText: ""
    property string accountsStderrText: ""

    property bool exitRunActive: false
    property bool exitStarted: false
    property bool exitExited: false
    property bool exitStdoutDone: false
    property bool exitStderrDone: false
    property bool exitTimedOut: false
    property bool exitRestartPending: false
    property int exitExitCode: 0
    property string exitStdoutText: ""
    property string exitStderrText: ""

    property bool actionRunActive: false
    property bool actionStarted: false
    property bool actionExited: false
    property bool actionStdoutDone: false
    property bool actionStderrDone: false
    property bool actionTimedOut: false
    property int actionExitCode: 0
    property string actionKind: ""
    property string actionStdoutText: ""
    property string actionStderrText: ""
    property string actionStartedText: ""
    property var actionContext: null
    property int actionRunTimeoutMs: actionTimeoutMs

    function nowMs() {
        return Date.now();
    }

    function nextId() {
        var value = nextActionId;
        nextActionId = value >= 2147483647 ? 1 : value + 1;
        return value;
    }

    function boundedPublicText(message, fallback) {
        var text = Model.sanitizeDisplay(message, publicTextLimit);
        return text !== "" ? text : fallback;
    }

    function setActionText(message) {
        actionStatus = boundedPublicText(message, "");
    }

    function setPublicError(message) {
        errorMessage = boundedPublicText(message, "Tailscale error");
    }

    function clearIdentity() {
        selfName = "";
        selfDnsName = "";
        selfIp = "";
        selfUserId = "";
        fileSharing = false;
        peers = [];
        tailnetExitNodes = [];
    }

    function clearAccounts() {
        accounts = [];
        selectedAccountId = "";
        selectedAccountLabel = "";
        selectedAccount = {
            "id": "",
            "nickname": "",
            "tailnet": "",
            "account": "",
            "selected": false,
            "label": ""
        };
    }

    function clearExitNodes() {
        exitNodeList = [];
        mullvadRegions = [];
    }

    function clearStatusBuffers() {
        statusStdoutText = "";
        statusStderrText = "";
        statusStarted = false;
        statusExited = false;
        statusStdoutDone = false;
        statusStderrDone = false;
        statusTimedOut = false;
        statusExitCode = 0;
    }

    function clearAccountsBuffers() {
        accountsStdoutText = "";
        accountsStderrText = "";
        accountsStarted = false;
        accountsExited = false;
        accountsStdoutDone = false;
        accountsStderrDone = false;
        accountsTimedOut = false;
        accountsExitCode = 0;
    }

    function clearExitBuffers() {
        exitStdoutText = "";
        exitStderrText = "";
        exitStarted = false;
        exitExited = false;
        exitStdoutDone = false;
        exitStderrDone = false;
        exitTimedOut = false;
        exitExitCode = 0;
    }

    function clearActionBuffers() {
        actionStdoutText = "";
        actionStderrText = "";
        actionStarted = false;
        actionExited = false;
        actionStdoutDone = false;
        actionStderrDone = false;
        actionTimedOut = false;
        actionExitCode = 0;
        actionKind = "";
        actionStartedText = "";
        actionContext = null;
    }

    function clearRefreshErrorIfRecovered() {
        if (busy)
            return;
        if (errorMessage === "Tailscale status unavailable" || errorMessage === "Account list unavailable" || errorMessage === "Account list requires authorization" || errorMessage === "Exit node list unavailable")
            errorMessage = "";
    }

    function applyUnavailableStatus(message, keepInstalled) {
        if (keepInstalled !== true)
            installed = false;
        running = false;
        needsLogin = false;
        active = false;
        backendState = "";
        statusText = boundedPublicText(message, "Tailscale unavailable");
        retainedAuthUrl = "";
        clearIdentity();
    }

    function statusLabel(parsed) {
        if (!parsed || parsed.ok !== true)
            return "Tailscale unavailable";
        if (parsed.running === true)
            return "Connected";
        if (parsed.needsLogin === true)
            return "Login required";
        if (parsed.backendState === "Starting")
            return "Starting";
        if (parsed.backendState === "Stopped")
            return "Stopped";
        if (parsed.backendState === "NeedsMachineAuth")
            return "Machine approval required";
        if (parsed.backendState === "NoState")
            return "Disconnected";
        return boundedPublicText(parsed.backendState, "Disconnected");
    }

    function applyStatus(parsed) {
        installed = true;
        backendState = String(parsed.backendState || "");
        running = parsed.running === true;
        needsLogin = parsed.needsLogin === true;
        active = running || needsLogin || backendState === "Starting" || backendState === "NeedsMachineAuth";
        statusText = statusLabel(parsed);
        selfName = boundedPublicText(parsed.selfName, "");
        selfDnsName = Model.cleanDnsName(parsed.selfDnsName || "");
        selfIp = Model.normalizeTailnetIPv4(parsed.selfIp || "");
        selfUserId = Model.normalizeOpaqueId(parsed.selfUserId || "");
        fileSharing = parsed.fileSharing === true;
        peers = Array.isArray(parsed.peers) ? parsed.peers : [];
        tailnetExitNodes = Array.isArray(parsed.tailnetExitNodes) ? parsed.tailnetExitNodes : [];
        if (needsLogin) {
            var freshAuthUrl = Model.validateAuthUrl(parsed.authUrl || "");
            if (freshAuthUrl !== "")
                retainedAuthUrl = freshAuthUrl;
            else if (Model.validateAuthUrl(retainedAuthUrl) === "")
                retainedAuthUrl = "";
        } else {
            retainedAuthUrl = "";
        }
        statusUpdatedAt = nowMs();
        mullvadRegions = Model.mullvadRegionOptions(exitNodeList);
        clearRefreshErrorIfRecovered();
    }

    function refresh(force) {
        var triggered = refreshStatus(force);
        if (panelActive) {
            if (refreshAccounts(force))
                triggered = true;
            if (refreshExitNodes(force))
                triggered = true;
        }
        return triggered;
    }

    function refreshStatus(force) {
        if (statusProcess.running || statusRunActive) {
            if (force)
                statusRestartPending = true;
            return false;
        }
        clearStatusBuffers();
        statusRunActive = true;
        statusRunSerial += 1;
        statusWatchdog.restart();
        try {
            statusProcess.running = true;
        } catch (_error) {
            statusRunActive = false;
            statusWatchdog.stop();
            applyUnavailableStatus("Tailscale unavailable", false);
            if (!busy)
                setPublicError("Tailscale status unavailable");
            return false;
        }
        return true;
    }

    function refreshAccounts(force) {
        if (!panelActive)
            return false;
        if (accountsProcess.running || accountsRunActive) {
            if (force)
                accountsRestartPending = true;
            return false;
        }
        clearAccountsBuffers();
        accountsRunActive = true;
        accountsWatchdog.restart();
        try {
            accountsProcess.running = true;
        } catch (_error) {
            accountsRunActive = false;
            accountsWatchdog.stop();
            accountsAccessDenied = false;
            accountsUpdatedAt = 0;
            clearAccounts();
            if (!busy)
                setPublicError("Account list unavailable");
            return false;
        }
        return true;
    }

    function refreshExitNodes(force) {
        if (!panelActive)
            return false;
        if (exitProcess.running || exitRunActive) {
            if (force)
                exitRestartPending = true;
            return false;
        }
        clearExitBuffers();
        exitRunActive = true;
        exitWatchdog.restart();
        try {
            exitProcess.running = true;
        } catch (_error) {
            exitRunActive = false;
            exitWatchdog.stop();
            exitUpdatedAt = 0;
            clearExitNodes();
            if (!busy)
                setPublicError("Exit node list unavailable");
            return false;
        }
        return true;
    }

    function finalizeStatus() {
        if (!statusRunActive || !statusExited || !statusStdoutDone || !statusStderrDone)
            return;
        statusRunActive = false;
        var runSerial = statusRunSerial;
        var started = statusStarted;
        var timedOut = statusTimedOut;
        var exitCode = statusExitCode;
        var output = statusStdoutText;
        var usable = false;
        clearStatusBuffers();
        if (!started) {
            applyUnavailableStatus("Tailscale unavailable", false);
            if (!busy)
                setPublicError("Tailscale status unavailable");
        } else if (timedOut || exitCode !== 0) {
            installed = true;
            applyUnavailableStatus("Tailscale unavailable", true);
            if (!busy)
                setPublicError("Tailscale status unavailable");
        } else {
            installed = true;
            var parsed = Model.parseStatus(output);
            if (parsed && parsed.ok === true && parsed.unavailable !== true) {
                applyStatus(parsed);
                usable = true;
            } else {
                applyUnavailableStatus("Tailscale unavailable", true);
                if (!busy)
                    setPublicError("Tailscale status unavailable");
            }
        }

        var restart = statusRestartPending;
        if (restart)
            statusRestartPending = false;
        if (pendingMutation && pendingMutation.statusRunSerial === runSerial) {
            // A forced refresh that arrived while this one was running must win.
            if (restart)
                pendingMutation.statusRunSerial = runSerial + 1;
            else if (!usable)
                failPendingMutation();
            else
                resolvePendingMutation();
        }
        if (restart) {
            Qt.callLater(function() {
                if (root.pendingMutation && root.pendingMutation.statusRunSerial === runSerial + 1)
                    root.startPendingStatusRefresh();
                else
                    root.refreshStatus(false);
            });
        }
    }

    function accessDeniedHint(text) {
        var lower = String(text || "").toLowerCase();
        return lower.indexOf("access denied") >= 0 || lower.indexOf("permission denied") >= 0 || lower.indexOf("not allowed") >= 0 || (lower.indexOf("operator") >= 0 && (lower.indexOf("authorize") >= 0 || lower.indexOf("denied") >= 0));
    }

    function requiresAuthorization(text) {
        return accessDeniedHint(text);
    }

    function applySelectedAccount(parsed) {
        accounts = Array.isArray(parsed.accounts) ? parsed.accounts : [];
        selectedAccountId = Model.normalizeOpaqueId(parsed.selectedAccountId || "");
        selectedAccountLabel = boundedPublicText(parsed.selectedAccountLabel || "", "");
        var selected = null;
        for (var i = 0; i < accounts.length; ++i) {
            if (accounts[i] && accounts[i].id === selectedAccountId) {
                selected = accounts[i];
                break;
            }
        }
        if (!selected && accounts.length > 0) {
            for (i = 0; i < accounts.length; ++i) {
                if (accounts[i] && accounts[i].selected === true) {
                    selected = accounts[i];
                    break;
                }
            }
        }
        if (selected) {
            selectedAccount = {
                "id": String(selected.id || ""),
                "nickname": String(selected.nickname || ""),
                "tailnet": String(selected.tailnet || ""),
                "account": String(selected.account || ""),
                "selected": selected.selected === true,
                "label": boundedPublicText(Model.accountLabel(selected), "")
            };
            if (selectedAccountId === "")
                selectedAccountId = String(selected.id || "");
            if (selectedAccountLabel === "")
                selectedAccountLabel = selectedAccount.label;
        } else {
            selectedAccount = {
                "id": "",
                "nickname": "",
                "tailnet": "",
                "account": "",
                "selected": false,
                "label": ""
            };
            selectedAccountId = "";
            selectedAccountLabel = "";
        }
    }

    function finalizeAccounts() {
        if (!accountsRunActive || !accountsExited || !accountsStdoutDone || !accountsStderrDone)
            return;
        accountsRunActive = false;
        var started = accountsStarted;
        var timedOut = accountsTimedOut;
        var exitCode = accountsExitCode;
        var output = accountsStdoutText;
        var stderrText = accountsStderrText;
        clearAccountsBuffers();
        if (!started || timedOut) {
            accountsAccessDenied = false;
            accountsUpdatedAt = 0;
            clearAccounts();
            if (!busy)
                setPublicError("Account list unavailable");
        } else {
            var denied = accessDeniedHint(stderrText) && exitCode !== 0;
            var parsed = Model.parseAccounts(output);
            var usable = exitCode === 0;
            if (usable)
                applySelectedAccount(parsed);
            else
                clearAccounts();
            accountsAccessDenied = denied;
            accountsUpdatedAt = usable ? nowMs() : 0;
            if (denied && accounts.length === 0 && !busy)
                setPublicError("Account list requires authorization");
            else if (!usable && !busy)
                setPublicError("Account list unavailable");
            else
                clearRefreshErrorIfRecovered();
        }
        if (accountsRestartPending) {
            accountsRestartPending = false;
            Qt.callLater(function() {
                root.refreshAccounts(false);
            });
        }
    }

    function finalizeExitNodes() {
        if (!exitRunActive || !exitExited || !exitStdoutDone || !exitStderrDone)
            return;
        exitRunActive = false;
        var started = exitStarted;
        var timedOut = exitTimedOut;
        var exitCode = exitExitCode;
        var output = exitStdoutText;
        clearExitBuffers();
        var usable = false;
        if (!started || timedOut) {
            exitUpdatedAt = 0;
            clearExitNodes();
            if (!busy)
                setPublicError("Exit node list unavailable");
        } else {
            var parsed = Model.parseExitNodeList(output);
            usable = exitCode === 0;
            if (usable) {
                exitNodeList = parsed;
                mullvadRegions = Model.mullvadRegionOptions(exitNodeList);
                exitUpdatedAt = nowMs();
                clearRefreshErrorIfRecovered();
            } else {
                exitUpdatedAt = 0;
                clearExitNodes();
                if (!busy)
                    setPublicError("Exit node list unavailable");
            }
        }
        var restart = exitRestartPending;
        exitRestartPending = false;
        if (pendingMutation && pendingMutation.kind === "setExitNode" && pendingMutation.waitingForExit === true) {
            if (restart) {
                Qt.callLater(function() {
                    if (!root.refreshExitNodes(false))
                        root.failPendingMutation();
                });
            } else if (!usable) {
                failPendingMutation();
            } else {
                resolvePendingExitMutation();
            }
        } else if (restart) {
            Qt.callLater(function() {
                root.refreshExitNodes(false);
            });
        }
    }

    function instantAction(successMessage, failureMessage) {
        var id = nextId();
        lastStartedActionId = id;
        lastFinishedActionId = id;
        if (failureMessage && failureMessage !== "") {
            lastFailedActionId = id;
            setActionText(boundedPublicText(successMessage, "Action failed"));
            setPublicError(failureMessage);
        } else {
            lastSuccessfulActionId = id;
            setActionText(successMessage);
            errorMessage = "";
        }
        return id;
    }

    function startAction(kind, command, startedMessage, context, timeoutMs) {
        if (busy)
            return 0;
        if (!Array.isArray(command) || command.length < 2 || command[0] !== helperExecutable)
            return 0;
        var request = command.slice(1);
        var id = nextId();
        lastStartedActionId = id;
        activeActionId = id;
        clearActionBuffers();
        actionKind = String(kind || "");
        actionContext = context || ({ });
        actionStartedText = String(startedMessage || "");
        setActionText(startedMessage);
        errorMessage = "";
        actionRunTimeoutMs = timeoutMs > 0 ? timeoutMs : actionTimeoutMs;
        actionWatchdog.interval = 5000;
        actionWatchdog.restart();
        actionProcess.environment = ({ "QUICKSHELL_TAILSCALE_REQUEST": JSON.stringify(request) });
        actionProcess.command = [helperExecutable, "request"];
        actionRunActive = true;
        try {
            actionProcess.running = true;
        } catch (_error) {
            actionRunActive = false;
            actionWatchdog.stop();
            activeActionId = 0;
            actionProcess.command = [];
            actionProcess.environment = ({ });
            setActionText("Action failed");
            setPublicError(actionFailureMessage(kind, false, ""));
            lastFinishedActionId = id;
            lastFailedActionId = id;
            clearActionBuffers();
            return 0;
        }
        return id;
    }

    function failActionStartup() {
        if (!actionRunActive || actionStarted)
            return;
        var id = activeActionId;
        var kind = actionKind;
        actionRunActive = false;
        activeActionId = 0;
        lastFinishedActionId = id;
        lastFailedActionId = id;
        actionWatchdog.stop();
        actionProcess.command = [];
        actionProcess.environment = ({ });
        clearActionBuffers();
        setActionText("Action failed");
        setPublicError(actionFailureMessage(kind, false, ""));
    }

    function actionFailureMessage(kind, timedOut, stderrText) {
        if (timedOut) {
            if (kind === "sendFiles")
                return "File transfer timed out";
            return "Tailscale action timed out";
        }
        if (kind === "authorizeOperator")
            return "Operator authorization failed";
        if (requiresAuthorization(stderrText))
            return "Tailscale requires authorization";
        if (kind === "switchAccount")
            return "Account switch failed";
        if (kind === "setExitNode")
            return "Exit node update failed";
        if (kind === "sendFiles")
            return "File transfer failed";
        return "Tailscale action failed";
    }

    function actionSuccessMessage(kind, context) {
        if (kind === "down")
            return "Disconnected";
        if (kind === "authorizeOperator")
            return "Operator authorized";
        if (kind === "switchAccount")
            return "Account switched";
        if (kind === "setExitNode")
            return context && context.clear === true ? "Exit node cleared" : "Exit node updated";
        if (kind === "sendFiles")
            return "Files sent";
        if (kind === "loginOrUp")
            return retainedAuthUrl !== "" ? "Login ready" : "Tailscale updated";
        return "Action complete";
    }

    function findAuthUrl(text) {
        var limited = String(text || "");
        if (limited.length > loginOutputLimit)
            limited = limited.slice(0, loginOutputLimit);
        var matches = limited.match(/https?:\/\/[^\s"'<>]+/g);
        if (!matches)
            return "";
        for (var i = 0; i < matches.length; ++i) {
            var url = Model.validateAuthUrl(matches[i]);
            if (url !== "")
                return url;
        }
        return "";
    }

    function finalizeAction() {
        if (!actionRunActive || !actionExited || !actionStdoutDone || !actionStderrDone)
            return;
        actionRunActive = false;
        var id = activeActionId;
        var kind = actionKind;
        var context = actionContext || ({ });
        var started = actionStarted;
        var timedOut = actionTimedOut;
        var exitCode = actionExitCode;
        var stdoutText = actionStdoutText;
        var stderrText = actionStderrText;
        actionProcess.command = [];
        actionProcess.environment = ({ });
        activeActionId = 0;
        lastFinishedActionId = id;
        clearActionBuffers();
        if (!started || timedOut || exitCode !== 0) {
            lastFailedActionId = id;
            setActionText(kind === "sendFiles" ? "File transfer failed" : "Action failed");
            setPublicError(actionFailureMessage(kind, timedOut || !started, stderrText));
        } else {
            if (kind === "loginOrUp") {
                var authUrl = findAuthUrl(stdoutText);
                if (authUrl === "")
                    authUrl = findAuthUrl(stderrText);
                if (authUrl !== "")
                    retainedAuthUrl = authUrl;
            }
            lastSuccessfulActionId = id;
            setActionText(actionSuccessMessage(kind, context));
            errorMessage = "";
        }
        Qt.callLater(function() {
            root.refresh(true);
        });
    }

    function statusIsFresh() {
        return statusUpdatedAt > 0 && nowMs() - statusUpdatedAt <= refreshFreshMs;
    }

    function accountsAreFresh() {
        return accountsUpdatedAt > 0 && nowMs() - accountsUpdatedAt <= refreshFreshMs;
    }

    function exitsAreFresh() {
        return exitUpdatedAt > 0 && nowMs() - exitUpdatedAt <= refreshFreshMs;
    }

    function failPendingMutation() {
        pendingMutation = null;
        setActionText("List changed; try again");
        setPublicError("List changed; try again");
        return 0;
    }

    function queuePendingMutation(mutation) {
        if (!mutation || pendingMutation !== null || activeActionId > 0) {
            setActionText("Action pending");
            setPublicError("List changed; try again");
            return 0;
        }
        var statusWasRunning = statusProcess.running || statusRunActive;
        pendingMutation = mutation;
        if (statusWasRunning) {
            // refreshStatus(true) records a restart; never use this in-flight result.
            mutation.statusRunSerial = statusRunSerial + 1;
            refreshStatus(true);
        } else {
            if (!refreshStatus(true))
                return failPendingMutation();
            mutation.statusRunSerial = statusRunSerial;
        }
        setActionText("Refreshing list…");
        return 0;
    }

    function startPendingStatusRefresh() {
        if (!pendingMutation)
            return;
        if (!refreshStatus(false))
            failPendingMutation();
    }

    function resolvePendingMutation() {
        var mutation = pendingMutation;
        if (!mutation)
            return 0;

        if (mutation.kind === "sendFiles") {
            var peer = findPeer(mutation.peerId);
            var eligible = !!peer && Model.isTaildropTarget(peer, selfUserId);
            var destination = peer ? sendFileTarget(peer) : "";
            if (!peer || fileSharing !== mutation.fileSharing || selfUserId !== mutation.selfUserId
                    || eligible !== mutation.taildropEligible || !eligible
                    || destination === "" || destination !== mutation.target)
                return failPendingMutation();

            var sendCommand = [helperExecutable, "send", destination];
            for (var i = 0; i < mutation.paths.length; ++i)
                sendCommand.push(mutation.paths[i]);
            pendingMutation = null;
            return startAction("sendFiles", sendCommand, "Sending files…", ({ "peerId": peer.id }), taildropTimeoutMs);
        }

        if (mutation.kind === "setExitNode") {
            if (mutation.mullvad !== true) {
                var statusNode = findNodeById(tailnetExitNodes, mutation.nodeId);
                var statusTarget = statusNode ? exitTargetToken(statusNode) : "";
                if (!statusNode || statusNode.ExitNodeOption !== mutation.exitCapability
                        || (statusNode.ExitNode === true) !== mutation.wasSelected
                        || statusTarget === "" || statusTarget !== mutation.target)
                    return failPendingMutation();
            }
            mutation.waitingForExit = true;
            if (exitProcess.running || exitRunActive) {
                exitRestartPending = true;
                return 0;
            }
            if (!refreshExitNodes(true))
                return failPendingMutation();
            return 0;
        }

        return failPendingMutation();
    }

    function resolvePendingExitMutation() {
        var mutation = pendingMutation;
        if (!mutation || mutation.kind !== "setExitNode" || mutation.waitingForExit !== true)
            return failPendingMutation();
        var node = findFreshExitMutationNode(mutation);
        var target = node ? exitTargetToken(node) : "";
        var capability = !!node && node.ExitNodeOption === true;
        var selected = !!node && node.ExitNode === true;
        if (!node || capability !== mutation.exitCapability || selected !== mutation.wasSelected
                || target === "" || target !== mutation.target)
            return failPendingMutation();

        pendingMutation = null;
        if (mutation.clear === true)
            return startAction("setExitNode", [helperExecutable, "set-exit", ""], "Clearing exit node…", ({ "clear": true }), actionTimeoutMs);
        return startAction("setExitNode", [helperExecutable, "set-exit", target], "Updating exit node…", ({ "clear": false, "target": target }), actionTimeoutMs);
    }

    function validateUserName(value) {
        var text = String(value || "").trim();
        if (!/^[A-Za-z_][A-Za-z0-9._-]{0,31}$/.test(text))
            return "";
        return text;
    }

    function findPeer(peerId) {
        var wanted = Model.normalizeOpaqueId(peerId || "");
        if (wanted === "")
            return null;
        for (var i = 0; i < peers.length; ++i) {
            if (peers[i] && peers[i].id === wanted)
                return peers[i];
        }
        return null;
    }

    function requireFreshPeer(peerId) {
        if (!statusIsFresh()) {
            refreshStatus(true);
            setActionText("Refreshing devices…");
            setPublicError("Device list changed; try again");
            return null;
        }
        var peer = findPeer(peerId);
        if (!peer) {
            setActionText("Device unavailable");
            setPublicError("Device is no longer available");
            return null;
        }
        return peer;
    }

    function copyPeerName(peerId) {
        var peer = requireFreshPeer(peerId);
        if (!peer)
            return 0;
        var text = boundedPublicText(peer.DisplayName || peer.HostName || "", "");
        if (text === "")
            return instantAction("Nothing to copy", "Nothing to copy");
        Quickshell.clipboardText = text;
        return instantAction("Copied name", "");
    }

    function copyPeerDnsName(peerId) {
        var peer = requireFreshPeer(peerId);
        if (!peer)
            return 0;
        var text = Model.cleanDnsName(peer.DNSName || peer.HostName || "");
        if (text === "")
            return instantAction("Nothing to copy", "Nothing to copy");
        Quickshell.clipboardText = text;
        return instantAction("Copied DNS name", "");
    }

    function copyPeerIp(peerId) {
        var peer = requireFreshPeer(peerId);
        if (!peer)
            return 0;
        var text = "";
        if (peer.TailscaleIPs && peer.TailscaleIPs.length > 0)
            text = Model.normalizeTailnetIPv4(peer.TailscaleIPs[0]);
        if (text === "" && peer.TailscaleIPv6 && peer.TailscaleIPv6.length > 0)
            text = Model.normalizeTailnetIPv6(peer.TailscaleIPv6[0]);
        if (text === "")
            return instantAction("Nothing to copy", "Nothing to copy");
        Quickshell.clipboardText = text;
        return instantAction("Copied address", "");
    }

    function toggle() {
        if (running)
            return down();
        return loginOrUp();
    }

    function down() {
        if (!installed && !statusRunActive) {
            refreshStatus(true);
            setActionText("Refreshing status…");
            setPublicError("Tailscale unavailable");
            return 0;
        }
        return startAction("down", [helperExecutable, "down"], "Disconnecting…", ({ }), actionTimeoutMs);
    }

    function loginOrUp() {
        var plan = Model.loginPlan(needsLogin, retainedAuthUrl);
        if (plan.authUrl !== "") {
            retainedAuthUrl = plan.authUrl;
            return openLogin();
        }
        return startAction("loginOrUp", [helperExecutable, "up"], needsLogin ? "Starting login…" : "Connecting…", ({ }), actionTimeoutMs);
    }

    function openLogin() {
        var url = Model.validateAuthUrl(retainedAuthUrl);
        if (url === "") {
            if (needsLogin)
                return instantAction("Login link unavailable", "Login link unavailable");
            return 0;
        }
        if (Qt.openUrlExternally(url))
            return instantAction("Opened login page", "");
        return instantAction("Login page unavailable", "Unable to open login page");
    }

    function authorizeOperator() {
        var user = validateUserName(Quickshell.env("USER"));
        if (user === "") {
            setActionText("Authorization unavailable");
            setPublicError("Operator authorization is unavailable");
            return 0;
        }
        return startAction("authorizeOperator", [helperExecutable, "authorize", user], "Authorizing operator…", ({ }), actionTimeoutMs);
    }

    function findAccount(accountId) {
        var wanted = Model.normalizeOpaqueId(accountId || "");
        if (wanted === "")
            return null;
        for (var i = 0; i < accounts.length; ++i) {
            if (accounts[i] && accounts[i].id === wanted)
                return accounts[i];
        }
        return null;
    }

    function switchAccount(accountId) {
        var wanted = Model.normalizeOpaqueId(accountId || "");
        if (wanted === "") {
            setActionText("Account unavailable");
            setPublicError("Selected account is invalid");
            return 0;
        }
        if (!accountsAreFresh()) {
            if (panelActive)
                refreshAccounts(true);
            setActionText("Refreshing accounts…");
            setPublicError("Account list changed; try again");
            return 0;
        }
        var account = findAccount(wanted);
        if (!account) {
            setActionText("Account unavailable");
            setPublicError("Selected account is no longer available");
            return 0;
        }
        if (account.selected === true)
            return instantAction("Account already selected", "");
        return startAction("switchAccount", [helperExecutable, "switch", account.id], "Switching account…", ({ "accountId": account.id }), actionTimeoutMs);
    }

    function combinedExitTargets() {
        var result = [];
        var seen = { };
        function appendNode(node) {
            if (!node || typeof node !== "object")
                return;
            var key = String(node.id || "");
            if (key === "")
                key = String(node.DNSName || node.HostName || "");
            if (key === "" || seen[key] === true)
                return;
            seen[key] = true;
            result.push(node);
        }
        for (var i = 0; i < tailnetExitNodes.length; ++i)
            appendNode(tailnetExitNodes[i]);
        for (i = 0; i < mullvadRegions.length; ++i)
            appendNode(mullvadRegions[i]);
        for (i = 0; i < exitNodeList.length; ++i)
            appendNode(exitNodeList[i]);
        return result;
    }

    function exitTargetToken(node) {
        if (!node || typeof node !== "object")
            return "";
        var dns = Model.cleanDnsName(node.DNSName || node.HostName || "");
        if (dns !== "")
            return dns;
        if (node.TailscaleIPs && node.TailscaleIPs.length > 0) {
            var ipv4 = Model.normalizeTailnetIPv4(node.TailscaleIPs[0]);
            if (ipv4 !== "")
                return ipv4;
        }
        if (node.TailscaleIPv6 && node.TailscaleIPv6.length > 0) {
            var ipv6 = Model.normalizeTailnetIPv6(node.TailscaleIPv6[0]);
            if (ipv6 !== "")
                return ipv6;
        }
        return "";
    }

    function findNodeById(source, nodeId) {
        var wanted = Model.normalizeOpaqueId(nodeId || "");
        if (wanted === "" || !Array.isArray(source))
            return null;
        for (var i = 0; i < source.length; ++i) {
            if (source[i] && String(source[i].id || "") === wanted)
                return source[i];
        }
        return null;
    }

    function findFreshExitMutationNode(mutation) {
        if (!mutation)
            return null;
        var fresh = exitNodeList.concat(mullvadRegions);
        var byId = findNodeById(fresh, mutation.nodeId);
        if (byId && exitTargetToken(byId) === mutation.target)
            return byId;
        for (var i = 0; i < fresh.length; ++i) {
            if (fresh[i] && exitTargetToken(fresh[i]) === mutation.target)
                return fresh[i];
        }
        return null;
    }

    function findExitTargetById(nodeId) {
        return findNodeById(combinedExitTargets(), nodeId);
    }

    function findExitTarget(target) {
        var raw = target;
        if (raw && typeof raw === "object")
            raw = raw.id || raw.DNSName || raw.HostName || "";
        var wantedId = Model.normalizeOpaqueId(raw || "");
        var wantedDns = Model.cleanDnsName(raw || "");
        var wantedIpv4 = Model.normalizeTailnetIPv4(raw || "");
        var wantedIpv6 = Model.normalizeTailnetIPv6(raw || "");
        var all = combinedExitTargets();
        for (var i = 0; i < all.length; ++i) {
            var node = all[i];
            if (!node)
                continue;
            if (wantedId !== "" && String(node.id || "") === wantedId)
                return node;
            if (wantedDns !== "" && Model.cleanDnsName(node.DNSName || node.HostName || "") === wantedDns)
                return node;
            var token = exitTargetToken(node);
            if (wantedIpv4 !== "" && token === wantedIpv4)
                return node;
            if (wantedIpv6 !== "" && token === wantedIpv6)
                return node;
        }
        return null;
    }

    function selectedExitNodePresent() {
        var all = combinedExitTargets();
        for (var i = 0; i < all.length; ++i) {
            if (all[i] && all[i].ExitNode === true)
                return true;
        }
        return false;
    }

    function setExitNode(target) {
        if (pendingMutation !== null || activeActionId > 0) {
            setActionText("Action pending");
            setPublicError("List changed; try again");
            return 0;
        }
        if (!exitsAreFresh()) {
            if (panelActive)
                refreshExitNodes(true);
            setActionText("Refreshing exit nodes…");
            setPublicError("List changed; try again");
            return 0;
        }

        var clear = target === undefined || target === null || String(target) === "";
        var node = null;
        if (clear) {
            var all = combinedExitTargets();
            for (var i = 0; i < all.length; ++i) {
                if (all[i] && all[i].ExitNode === true) {
                    node = all[i];
                    break;
                }
            }
            if (!node)
                return instantAction("Exit node already cleared", "");
        } else {
            node = findExitTarget(target);
            if (!node || node.ExitNode === true) {
                setActionText("Exit node unavailable");
                setPublicError("List changed; try again");
                return 0;
            }
        }

        var nodeId = Model.normalizeOpaqueId(node.id || "");
        var token = exitTargetToken(node);
        if (nodeId === "" || token === "" || node.ExitNodeOption !== true) {
            setActionText("Exit node unavailable");
            setPublicError("List changed; try again");
            return 0;
        }
        return queuePendingMutation({
            "kind": "setExitNode",
            "nodeId": nodeId,
            "target": token,
            "exitCapability": node.ExitNodeOption === true,
            "wasSelected": node.ExitNode === true,
            "mullvad": node.Mullvad === true || node.MullvadRegion === true,
            "clear": clear
        });
    }

    function canSendFiles(peerId) {
        if (fileSharing !== true)
            return false;
        if (peerId === undefined || peerId === null || peerId === "") {
            for (var i = 0; i < peers.length; ++i) {
                if (peers[i] && Model.isTaildropTarget(peers[i], selfUserId))
                    return true;
            }
            return false;
        }
        var peer = findPeer(peerId);
        return !!peer && Model.isTaildropTarget(peer, selfUserId);
    }

    function validateAbsolutePaths(paths) {
        if (!Array.isArray(paths) || paths.length === 0 || paths.length > maximumFiles)
            return null;
        var result = [];
        for (var i = 0; i < paths.length; ++i) {
            if (typeof paths[i] !== "string")
                return null;
            var value = String(paths[i]);
            if (value.length === 0 || value.length > 4096 || value.charAt(0) !== "/" || value.indexOf("\u0000") >= 0)
                return null;
            result.push(value);
        }
        return result;
    }

    function sendFileTarget(peer) {
        if (!peer || typeof peer !== "object")
            return "";
        var dns = Model.cleanDnsName(peer.DNSName || peer.HostName || "");
        if (dns !== "")
            return dns;
        if (peer.TailscaleIPs && peer.TailscaleIPs.length > 0) {
            var ipv4 = Model.normalizeTailnetIPv4(peer.TailscaleIPs[0]);
            if (ipv4 !== "")
                return ipv4;
        }
        if (peer.TailscaleIPv6 && peer.TailscaleIPv6.length > 0) {
            var ipv6 = Model.normalizeTailnetIPv6(peer.TailscaleIPv6[0]);
            if (ipv6 !== "")
                return ipv6;
        }
        return "";
    }

    function sendFiles(peerId, paths) {
        if (pendingMutation !== null || activeActionId > 0) {
            setActionText("Action pending");
            setPublicError("List changed; try again");
            return 0;
        }
        var validatedPaths = validateAbsolutePaths(paths);
        if (!validatedPaths) {
            setActionText("File transfer unavailable");
            setPublicError("Selected files are invalid");
            return 0;
        }
        var peer = findPeer(peerId);
        if (!peer || fileSharing !== true || !Model.isTaildropTarget(peer, selfUserId)) {
            setActionText("File transfer unavailable");
            setPublicError("List changed; try again");
            return 0;
        }
        var destination = sendFileTarget(peer);
        if (destination === "") {
            setActionText("File transfer unavailable");
            setPublicError("List changed; try again");
            return 0;
        }
        return queuePendingMutation({
            "kind": "sendFiles",
            "peerId": peer.id,
            "target": destination,
            "taildropEligible": Model.isTaildropTarget(peer, selfUserId),
            "fileSharing": fileSharing,
            "selfUserId": selfUserId,
            "paths": validatedPaths.slice()
        });
    }

    onPanelActiveChanged: {
        if (panelActive)
            refresh(true);
        else if (pendingMutation !== null)
            pendingMutation = null;
    }

    Component.onCompleted: refresh(true)
    Component.onDestruction: pendingMutation = null

    Process {
        id: statusProcess

        command: [root.helperExecutable, "status"]
        onStarted: {
            root.statusStarted = true;
            statusWatchdog.restart();
        }
        onExited: function(code) {
            root.statusExitCode = code;
            root.statusExited = true;
            statusWatchdog.stop();
            Qt.callLater(root.finalizeStatus);
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.statusStdoutText = String(text || "");
                root.statusStdoutDone = true;
                Qt.callLater(root.finalizeStatus);
            }
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.statusStderrText = String(text || "").slice(0, root.stderrHintLimit);
                root.statusStderrDone = true;
                Qt.callLater(root.finalizeStatus);
            }
        }
    }

    Timer {
        id: statusWatchdog

        interval: root.refreshTimeoutMs
        onTriggered: {
            if (!root.statusRunActive)
                return;
            root.statusTimedOut = true;
            if (!root.statusStarted) {
                root.statusExitCode = -1;
                root.statusExited = true;
                root.statusStdoutDone = true;
                root.statusStderrDone = true;
                Qt.callLater(root.finalizeStatus);
            } else if (statusProcess.running) {
                statusProcess.running = false;
            }
        }
    }

    Process {
        id: accountsProcess

        command: [root.helperExecutable, "accounts"]
        onStarted: {
            root.accountsStarted = true;
            accountsWatchdog.restart();
        }
        onExited: function(code) {
            root.accountsExitCode = code;
            root.accountsExited = true;
            accountsWatchdog.stop();
            Qt.callLater(root.finalizeAccounts);
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.accountsStdoutText = String(text || "");
                root.accountsStdoutDone = true;
                Qt.callLater(root.finalizeAccounts);
            }
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.accountsStderrText = String(text || "").slice(0, root.stderrHintLimit);
                root.accountsStderrDone = true;
                Qt.callLater(root.finalizeAccounts);
            }
        }
    }

    Timer {
        id: accountsWatchdog

        interval: root.refreshTimeoutMs
        onTriggered: {
            if (!root.accountsRunActive)
                return;
            root.accountsTimedOut = true;
            if (!root.accountsStarted) {
                root.accountsExitCode = -1;
                root.accountsExited = true;
                root.accountsStdoutDone = true;
                root.accountsStderrDone = true;
                Qt.callLater(root.finalizeAccounts);
            } else if (accountsProcess.running) {
                accountsProcess.running = false;
            }
        }
    }

    Process {
        id: exitProcess

        command: [root.helperExecutable, "exit-nodes"]
        onStarted: {
            root.exitStarted = true;
            exitWatchdog.restart();
        }
        onExited: function(code) {
            root.exitExitCode = code;
            root.exitExited = true;
            exitWatchdog.stop();
            Qt.callLater(root.finalizeExitNodes);
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.exitStdoutText = String(text || "");
                root.exitStdoutDone = true;
                Qt.callLater(root.finalizeExitNodes);
            }
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.exitStderrText = String(text || "").slice(0, root.stderrHintLimit);
                root.exitStderrDone = true;
                Qt.callLater(root.finalizeExitNodes);
            }
        }
    }

    Timer {
        id: exitWatchdog

        interval: root.refreshTimeoutMs
        onTriggered: {
            if (!root.exitRunActive)
                return;
            root.exitTimedOut = true;
            if (!root.exitStarted) {
                root.exitExitCode = -1;
                root.exitExited = true;
                root.exitStdoutDone = true;
                root.exitStderrDone = true;
                Qt.callLater(root.finalizeExitNodes);
            } else if (exitProcess.running) {
                exitProcess.running = false;
            }
        }
    }

    Process {
        id: actionProcess

        command: []
        onStarted: {
            root.actionStarted = true;
            actionProcess.environment = ({ });
            actionWatchdog.interval = root.actionRunTimeoutMs;
            actionWatchdog.restart();
        }
        onExited: function(code) {
            root.actionExitCode = code;
            root.actionExited = true;
            actionWatchdog.stop();
            Qt.callLater(root.finalizeAction);
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var maximum = root.actionKind === "loginOrUp" ? root.loginOutputLimit : root.stderrHintLimit;
                root.actionStdoutText = String(text || "").slice(0, maximum);
                root.actionStdoutDone = true;
                Qt.callLater(root.finalizeAction);
            }
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var maximum = root.actionKind === "loginOrUp" ? root.loginOutputLimit : root.stderrHintLimit;
                root.actionStderrText = String(text || "").slice(0, maximum);
                root.actionStderrDone = true;
                Qt.callLater(root.finalizeAction);
            }
        }
    }

    Timer {
        id: actionWatchdog

        interval: root.actionTimeoutMs
        onTriggered: {
            if (!root.actionRunActive)
                return;
            if (!root.actionStarted) {
                root.failActionStartup();
                return;
            }
            root.actionTimedOut = true;
            if (actionProcess.running)
                actionProcess.running = false;
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }
}
