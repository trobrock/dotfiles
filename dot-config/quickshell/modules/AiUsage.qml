import "../components"
import QtQuick

Pill {
    id: root

    required property var bar
    readonly property var usageData: bar.services.agentUsage || null
    readonly property var rawProviders: usageData && Array.isArray(usageData.providers) ? usageData.providers : []
    readonly property var providers: usableProviders(rawProviders)
    readonly property int providerIndex: indexForProvider(selectedProviderId)
    readonly property var provider: providers.length > 0 ? providers[providerIndex] : null
    readonly property var limits: limitWindows(provider)
    readonly property var headline: bindingWindow(provider)
    readonly property var balance: balanceValue(provider)
    readonly property bool balanceAlarming: balance && balance.funded > 0 && balance.remaining / balance.funded <= 0.1
    readonly property bool hasProviderProblem: providerProblemTitle(provider) !== ""
    readonly property bool alarming: (headline && headline.percent >= 0.9) || balanceAlarming || hasProviderProblem
    readonly property bool hasProviders: providers.length > 0
    property string defaultProviderId: "codex"
    property string selectedProviderId: ""
    property bool popupOpen: false
    property double nowMs: Date.now()

    function isFiniteNumber(value) {
        return typeof value === "number" && isFinite(value);
    }

    function numberValue(value, fallback) {
        return isFiniteNumber(value) ? value : (fallback === undefined ? 0 : fallback);
    }

    function nonnegativeNumber(value, fallback) {
        return isFiniteNumber(value) && value >= 0 ? value : (fallback === undefined ? 0 : fallback);
    }

    function dataString(value) {
        return typeof value === "string" ? value : "";
    }

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    function alpha(color, amount) {
        return Qt.rgba(color.r, color.g, color.b, amount);
    }

    function providerId(providerData) {
        if (!providerData)
            return "";

        return dataString(providerData.providerId) || dataString(providerData.id);
    }

    function providerName(providerData) {
        if (!providerData)
            return "Unknown provider";

        var id = providerId(providerData);
        var name = dataString(providerData.providerName) || dataString(providerData.name) || id || "Unknown provider";
        if (name.toLowerCase() === "claude")
            return "Claude";

        if (name.toLowerCase() === "codex")
            return "Codex";

        if (name.toLowerCase() === "fireworks")
            return "Fireworks";

        return name;
    }

    function providerHasData(providerData) {
        if (!providerData || typeof providerData !== "object" || Array.isArray(providerData))
            return false;

        var countFields = ["totalPrompts", "totalSessions", "activeDays", "todayPrompts", "todaySessions"];
        for (var i = 0; i < countFields.length; i++) {
            if (isFiniteNumber(providerData[countFields[i]]) && providerData[countFields[i]] > 0)
                return true;

        }
        return limitWindows(providerData).length > 0 || balanceValue(providerData) !== null;
    }

    function usableProviders(list) {
        var result = [];
        for (var i = 0; i < list.length; i++) {
            var candidate = list[i];
            if (!candidate || typeof candidate !== "object" || providerId(candidate) === "")
                continue;

            if (providerHasData(candidate))
                result.push(candidate);

        }
        return result;
    }

    function indexForProvider(id) {
        for (var i = 0; i < providers.length; i++) {
            if (providerId(providers[i]) === id)
                return i;

        }
        return 0;
    }

    function hasProvider(id) {
        for (var i = 0; i < providers.length; i++) {
            if (providerId(providers[i]) === id)
                return true;

        }
        return false;
    }

    function ensureSelection() {
        if (!providers.length) {
            selectedProviderId = "";
            return ;
        }
        if (selectedProviderId === "" || !hasProvider(selectedProviderId))
            selectedProviderId = hasProvider(defaultProviderId) ? defaultProviderId : providerId(providers[0]);

    }

    function selectProvider(index) {
        if (!providers.length)
            return ;

        var wrapped = ((index % providers.length) + providers.length) % providers.length;
        selectedProviderId = providerId(providers[wrapped]);
        Qt.callLater(function() {
            detailsPopup.scrollToTop();
        });
    }

    function refreshNow(force) {
        if (bar.services && typeof bar.services.refreshAgentUsage === "function")
            bar.services.refreshAgentUsage(force === true);

    }

    function refreshLimits() {
        if (bar.services && typeof bar.services.refreshAgentLimits === "function")
            bar.services.refreshAgentLimits();

    }

    function closePopup() {
        popupOpen = false;
    }

    function windowIsLong(label) {
        var text = String(label || "").toLowerCase();
        return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0 || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0;
    }

    function windowSpanMs(label) {
        var text = String(label || "").toLowerCase();
        if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0)
            return 30 * 24 * 3600 * 1000;

        if (text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0)
            return 7 * 24 * 3600 * 1000;

        var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/);
        if (hours)
            return Number(hours[1]) * 3600 * 1000;

        var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/);
        if (minutes)
            return Number(minutes[1]) * 60 * 1000;

        return 0;
    }

    function windowTitle(label) {
        var text = String(label || "").toLowerCase();
        if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0)
            return "Monthly";

        if (text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0)
            return "Weekly";

        if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0)
            return "Session";

        var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim();
        return plain === "" ? "Limit" : friendlyModelName(plain);
    }

    function normalizedPercent(entry) {
        if (!entry || typeof entry !== "object")
            return -1;

        var raw = entry.percent;
        if (raw === undefined)
            raw = entry.usedPercent;

        if (raw === undefined)
            raw = entry.utilization;

        if (!isFiniteNumber(raw) || raw < 0)
            return -1;

        var value = raw;
        if (!isFinite(value) || value < 0)
            return -1;

        if (value > 100)
            return -1;

        if (value > 1)
            value /= 100;

        return value;
    }

    function limitWindows(providerData) {
        if (!providerData)
            return [];

        var list = Array.isArray(providerData.limits) ? providerData.limits : [];
        var result = [];
        for (var i = 0; i < list.length; i++) {
            var entry = list[i] || {
            };
            var percent = normalizedPercent(entry);
            if (percent < 0)
                continue;

            var label = dataString(entry.label) || dataString(entry.window) || dataString(entry.name);
            var explicitTitle = dataString(entry.title);
            result.push({
                "title": explicitTitle !== "" ? explicitTitle : windowTitle(label),
                "label": label,
                "percent": percent,
                "resetAt": dataString(entry.resetsAt) || dataString(entry.resetAt) || dataString(entry.reset_at),
                "pace": dataString(entry.paceText) || dataString(entry.paceStatus) || dataString(entry.pace)
            });
        }
        return result;
    }

    function bindingWindow(providerData) {
        var windows = limitWindows(providerData);
        var best = null;
        for (var i = 0; i < windows.length; i++) {
            if (!best || windows[i].percent > best.percent)
                best = windows[i];

        }
        return best;
    }

    function resetMsFor(windowData) {
        if (!windowData || windowData.resetAt === "")
            return -1;

        var timestamp = new Date(windowData.resetAt).getTime();
        return isFinite(timestamp) ? timestamp - nowMs : -1;
    }

    function formatDuration(milliseconds) {
        if (!(milliseconds > 0))
            return "now";

        var minutes = Math.floor(milliseconds / 60000);
        var hours = Math.floor(minutes / 60);
        var days = Math.floor(hours / 24);
        if (days > 0)
            return days + "d " + hours % 24 + "h";

        if (hours > 0)
            return hours + "h " + minutes % 60 + "m";

        return Math.max(1, minutes) + "m";
    }

    function paceInfo(windowData) {
        if (!windowData)
            return {
            "text": "",
            "tone": "dim"
        };

        if (windowData.pace !== "")
            return {
            "text": windowData.pace,
            "tone": String(windowData.pace).toLowerCase().indexOf("ahead") >= 0 || String(windowData.pace).toLowerCase().indexOf("above") >= 0 ? "warn" : "good"
        };

        var span = windowSpanMs(windowData.label);
        var remaining = resetMsFor(windowData);
        if (!(span > 0) || !(remaining > 0) || remaining > span)
            return {
            "text": "",
            "tone": "dim"
        };

        var elapsed = clamp(1 - remaining / span, 0, 1);
        var delta = windowData.percent - elapsed;
        if (delta > 0.05)
            return {
            "text": "Above pace by " + Math.round(delta * 100) + "%",
            "tone": "warn"
        };

        if (delta < -0.05)
            return {
            "text": "Below pace by " + Math.round(-delta * 100) + "%",
            "tone": "good"
        };

        return {
            "text": "On pace",
            "tone": "dim"
        };
    }

    function balanceValue(providerData) {
        var raw = providerData && providerData.balance ? providerData.balance : null;
        if (!raw || typeof raw !== "object")
            return null;

        var remaining = raw.remaining;
        var funded = raw.funded;
        if (!isFiniteNumber(remaining) || remaining < 0)
            return null;

        return {
            "remaining": remaining,
            "funded": isFiniteNumber(funded) && funded > 0 ? funded : 0,
            "spent": isFiniteNumber(raw.spent) && raw.spent >= 0 ? raw.spent : -1,
            "currency": dataString(raw.currency) || "USD",
            "estimated": raw.estimated === true
        };
    }

    function currencyPrefix(currency) {
        var code = String(currency || "USD").toUpperCase();
        if (code === "USD")
            return "$";

        if (code === "EUR")
            return "€";

        if (code === "GBP")
            return "£";

        return code + " ";
    }

    function formatMoney(value, currency) {
        return currencyPrefix(currency) + numberValue(value, 0).toFixed(2);
    }

    function balanceDetailText(balanceData) {
        if (!balanceData)
            return "";

        var pieces = [];
        if (balanceData.spent >= 0)
            pieces.push(formatMoney(balanceData.spent, balanceData.currency) + " spent");

        if (balanceData.funded > 0)
            pieces.push(formatMoney(balanceData.funded, balanceData.currency) + " funded");

        if (balanceData.estimated)
            pieces.push("estimated");

        return pieces.join(" · ");
    }

    function heroStatus(providerData) {
        if (!providerData)
            return "";

        var status = dataString(providerData.usageStatusText).trim();
        return status !== "" ? status : heroMeta(providerData);
    }

    function heroMeta(providerData) {
        if (!providerData)
            return "";

        var tier = dataString(providerData.tierLabel) || dataString(providerData.tier) || dataString(providerData.plan);
        tier = tier.trim();
        if (tier !== "")
            return tier.charAt(0).toUpperCase() + tier.slice(1);

        return balanceValue(providerData) ? "Prepaid" : "";
    }

    function providerProblemTitle(providerData) {
        if (!providerData)
            return "Provider unavailable";

        var direct = dataString(providerData.usageStatusText) || dataString(providerData.endpointStatusText) || dataString(providerData.errorText) || dataString(providerData.authError) || dataString(providerData.endpointError) || dataString(providerData.error);
        direct = direct.trim();
        if (direct !== "")
            return direct;

        var rawStatus = dataString(providerData.status);
        var status = rawStatus.toLowerCase();
        if (status !== "" && status !== "ready" && status !== "ok" && status !== "healthy")
            return rawStatus;

        if (providerData.ready === false)
            return "Provider unavailable";

        if (providerData.stale === true)
            return "Data may be stale";

        return "";
    }

    function providerProblemDetail(providerData) {
        if (!providerData)
            return "No provider record is available.";

        var help = dataString(providerData.authHelpText) || dataString(providerData.endpointHelpText) || dataString(providerData.errorDetail);
        if (help !== "")
            return help;

        return providerProblemTitle(providerData);
    }

    function formatTokenCount(value) {
        var amount = Math.max(0, numberValue(value, 0));
        if (amount >= 1e+09)
            return (amount / 1e+09).toFixed(1) + "B";

        if (amount >= 1e+06)
            return (amount / 1e+06).toFixed(1) + "M";

        if (amount >= 1000)
            return (amount / 1000).toFixed(1) + "K";

        return String(Math.round(amount));
    }

    function modelWordCase(word) {
        var lower = String(word || "").toLowerCase();
        if (lower === "gpt")
            return "GPT";

        if (lower === "deepseek")
            return "DeepSeek";

        if (lower === "kimi")
            return "Kimi";

        return lower.charAt(0).toUpperCase() + lower.slice(1);
    }

    function friendlyModelName(id) {
        if (!id)
            return "Unknown";

        var name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "");
        var parts = name.split("-");
        var words = [];
        var version = [];
        for (var i = 0; i < parts.length; i++) {
            var part = parts[i];
            if (part === "")
                continue;

            if (/^\d/.test(part)) {
                version.push(part);
                continue;
            }
            if (version.length > 0) {
                words.push(version.join("."));
                version = [];
            }
            words.push(modelWordCase(part));
        }
        if (version.length > 0)
            words.push(version.join("."));

        return words.length > 0 ? words.join(" ") : "Unknown";
    }

    function todayDate() {
        var now = new Date(nowMs);
        return now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0");
    }

    function dayName(date) {
        var parsed = new Date(String(date || "") + "T00:00:00");
        if (isNaN(parsed.getTime()))
            return String(date || "");

        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()];
    }

    function dayLabel(date, today) {
        return today ? "Today" : dayName(date);
    }

    function dateDetail(date) {
        var parsed = new Date(String(date || "") + "T00:00:00");
        if (isNaN(parsed.getTime()))
            return String(date || "");

        return dayName(date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate();
    }

    function dayTokens(day) {
        if (!day || typeof day !== "object")
            return 0;

        var value = day.messageCount !== undefined ? day.messageCount : (day.totalTokens !== undefined ? day.totalTokens : day.tokens);
        return nonnegativeNumber(value, 0);
    }

    function recentDayRows(providerData) {
        var source = providerData && Array.isArray(providerData.recentDays) ? providerData.recentDays : [];
        var rows = [];
        for (var i = 0; i < source.length; i++) {
            var row = source[i];
            if (!row || typeof row !== "object" || Array.isArray(row) || typeof row.date !== "string")
                continue;

            var value = row.messageCount !== undefined ? row.messageCount : (row.totalTokens !== undefined ? row.totalTokens : row.tokens);
            if (isFiniteNumber(value) && value > 0)
                rows.push(row);

        }
        rows.sort(function(a, b) {
            return String(a.date || "").localeCompare(String(b.date || ""));
        });
        return rows.slice(Math.max(0, rows.length - 7));
    }

    function weekPeak(providerData) {
        var days = recentDayRows(providerData);
        var peak = 0;
        for (var i = 0; i < days.length; i++) peak = Math.max(peak, dayTokens(days[i]))
        return peak;
    }

    function dayDetail(day, today) {
        if (!day)
            return "";

        var text = dateDetail(day.date) + " · " + formatTokenCount(dayTokens(day)) + " tokens";
        if (today && provider && provider.hasPromptStats !== false)
            text += " · " + Math.max(0, numberValue(provider.todayPrompts, 0)) + " prompts · " + Math.max(0, numberValue(provider.todaySessions, 0)) + " sessions";

        return text;
    }

    function modelRows(providerData) {
        var usage = providerData && providerData.modelUsage && typeof providerData.modelUsage === "object" && !Array.isArray(providerData.modelUsage) ? providerData.modelUsage : {
        };
        var rows = [];
        for (var id in usage) {
            var bucket = usage[id];
            if (!bucket || typeof bucket !== "object" || Array.isArray(bucket))
                continue;

            var rawInput = bucket.inputTokens !== undefined ? bucket.inputTokens : bucket.input;
            var rawOutput = bucket.outputTokens !== undefined ? bucket.outputTokens : bucket.output;
            var rawCacheRead = bucket.cacheReadInputTokens !== undefined ? bucket.cacheReadInputTokens : bucket.cacheReadTokens;
            var rawCacheWrite = bucket.cacheCreationInputTokens !== undefined ? bucket.cacheCreationInputTokens : bucket.cacheWriteTokens;
            var hasNumericValue = isFiniteNumber(rawInput) && rawInput >= 0 || isFiniteNumber(rawOutput) && rawOutput >= 0 || isFiniteNumber(rawCacheRead) && rawCacheRead >= 0 || isFiniteNumber(rawCacheWrite) && rawCacheWrite >= 0;
            if (!hasNumericValue)
                continue;

            var input = nonnegativeNumber(rawInput, 0);
            var output = nonnegativeNumber(rawOutput, 0);
            var cacheRead = nonnegativeNumber(rawCacheRead, 0);
            var cacheWrite = nonnegativeNumber(rawCacheWrite, 0);
            var total = input + output + cacheRead + cacheWrite;
            if (!isFiniteNumber(total) || total <= 0)
                continue;

            rows.push({
                "name": friendlyModelName(id),
                "total": total,
                "input": Math.max(0, input),
                "output": Math.max(0, output),
                "cacheRead": Math.max(0, cacheRead),
                "cacheWrite": Math.max(0, cacheWrite)
            });
        }
        rows.sort(function(a, b) {
            return b.total - a.total;
        });
        return rows.slice(0, 4);
    }

    function modelDetail(row) {
        if (!row)
            return "";

        return "In " + formatTokenCount(row.input) + " · out " + formatTokenCount(row.output) + " · cache read " + formatTokenCount(row.cacheRead) + " · cache write " + formatTokenCount(row.cacheWrite);
    }

    function todaySummary(providerData) {
        if (!providerData)
            return "";

        var tokens = Math.max(0, numberValue(providerData.todayTotalTokens, 0));
        var prompts = Math.max(0, numberValue(providerData.todayPrompts, 0));
        var sessions = Math.max(0, numberValue(providerData.todaySessions, 0));
        if (tokens === 0 && prompts === 0 && sessions === 0)
            return "";

        var parts = [formatTokenCount(tokens) + " tokens"];
        if (providerData.hasPromptStats !== false) {
            parts.push(prompts + " prompt" + (prompts === 1 ? "" : "s"));
            parts.push(sessions + " session" + (sessions === 1 ? "" : "s"));
        }
        return parts.join(" · ");
    }

    function errorText() {
        var messages = [];
        var serviceError = String(bar.services.agentUsageError || "");
        if (serviceError !== "")
            messages.push(serviceError);

        var errors = usageData && Array.isArray(usageData.errors) ? usageData.errors : [];
        for (var i = 0; i < errors.length; i++) {
            var entry = errors[i];
            var text = typeof entry === "string" ? entry : (entry && typeof entry === "object" ? dataString(entry.message) || dataString(entry.error) || dataString(entry.detail) : "");
            if (text !== "" && messages.indexOf(text) < 0)
                messages.push(text);

        }
        return messages.join(" · ");
    }

    function formatUpdated(value) {
        if (value === undefined || value === null || value === "")
            return "";

        if (!isFiniteNumber(value) && typeof value !== "string")
            return "";

        var date = typeof value === "number" && value < 1e+12 ? new Date(value * 1000) : new Date(value);
        if (isNaN(date.getTime()))
            return "";

        return date.toLocaleString(Qt.locale(), "MMM d, h:mm AP");
    }

    function footerText() {
        var sync = usageData && usageData.sync && typeof usageData.sync === "object" ? usageData.sync : null;
        if (sync) {
            var rawStatus = sync.statusText || sync.error || sync.status || "";
            var status = typeof rawStatus === "object" && rawStatus ? dataString(rawStatus.message) || dataString(rawStatus.error) || dataString(rawStatus.state) : dataString(rawStatus);
            if (status !== "" && status.toLowerCase() !== "ok" && status.toLowerCase() !== "ready")
                return status;

            var count = numberValue(sync.deviceCount, Array.isArray(sync.devices) ? sync.devices.length : 0);
            if (sync.enabled === true && count > 0)
                return "Merged from " + count + " device" + (count === 1 ? "" : "s");

        }
        if (provider && provider.syncEnabled && numberValue(provider.syncDeviceCount, 0) > 0) {
            var providerCount = numberValue(provider.syncDeviceCount, 0);
            return "Merged from " + providerCount + " device" + (providerCount === 1 ? "" : "s");
        }
        var updated = provider ? formatUpdated(provider.updatedAt) : "";
        if (updated === "" && usageData)
            updated = formatUpdated(usageData.generatedAt);

        return updated !== "" ? "Updated " + updated : "";
    }

    function tooltipText() {
        if (!provider)
            return "AI usage unavailable";

        var summary = providerName(provider);
        if (headline)
            summary += " · " + headline.title + " " + Math.round(headline.percent * 100) + "% used";
        else if (balance)
            summary += " · " + formatMoney(balance.remaining, balance.currency) + " remaining";
        var problem = providerProblemTitle(provider);
        if (problem !== "")
            summary += " · " + problem;

        if (errorText() !== "")
            summary += " · Error: " + errorText();

        summary += "\nLeft: details · Middle: next provider · Right: launch agent";
        return summary.replace(/</g, "‹").replace(/>/g, "›").slice(0, 512);
    }

    function colorChannelLuminance(value) {
        var channel = Number(value);
        if (!isFinite(channel))
            return 0;

        return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
    }

    function colorLuminance(color) {
        return 0.2126 * colorChannelLuminance(color.r) + 0.7152 * colorChannelLuminance(color.g) + 0.0722 * colorChannelLuminance(color.b);
    }

    function iconCandidates(providerData) {
        var id = providerId(providerData).toLowerCase().replace(/[^a-z0-9_-]/g, "");
        if (id === "")
            return [];

        var candidates = [];
        if (colorLuminance(theme.surfaceSolid) >= 0.5)
            candidates.push(Qt.resolvedUrl("../assets/ai-usage/" + id + "-light.svg"));

        candidates.push(Qt.resolvedUrl("../assets/ai-usage/" + id + ".svg"));
        return candidates;
    }

    onProvidersChanged: Qt.callLater(ensureSelection)
    visible: hasProviders
    onPopupOpenChanged: {
        if (popupOpen) {
            nowMs = Date.now();
            refreshLimits();
            Qt.callLater(function() {
                panel.forceActiveFocus();
            });
        }
    }
    theme: bar.theme
    implicitWidth: hasProviders ? button.implicitWidth + (embedded ? 4 : 20) : 0
    implicitHeight: hasProviders ? 27 : 0
    color: hasProviders && !embedded ? theme.surface : "transparent"
    border.width: hasProviders && !embedded ? 1 : 0
    Accessible.name: hasProviders ? "AI usage" : ""

    Timer {
        interval: 30000
        running: root.popupOpen
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    ModuleButton {
        id: button

        visible: root.hasProviders
        bar: root.bar
        theme: root.theme
        text: "󱙺"
        foreground: root.alarming ? root.theme.red : root.theme.subtext
        tooltip: root.tooltipText()
        horizontalPadding: 5
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        Accessible.description: "Left click for details, middle click for the next provider, right click to launch the AI agent"
        onClicked: function(mouseButton) {
            if (mouseButton === Qt.MiddleButton)
                root.selectProvider(root.providerIndex + 1);
            else if (mouseButton === Qt.RightButton)
                root.bar.services.launchAiAgent();
            else if (mouseButton === Qt.LeftButton)
                root.popupOpen = !root.popupOpen;
        }
    }

    PopupCard {
        id: detailsPopup

        anchorItem: button
        bar: root.bar
        owner: root
        open: root.popupOpen
        onOpenChanged: root.popupOpen = open
        cardWidth: 430
        cardHeight: Math.min(680, Math.max(100, panel.implicitHeight + padding * 2))
        padding: 18

        Column {
            id: panel

            width: parent.width
            spacing: 14
            activeFocusOnTab: true
            Accessible.role: Accessible.Pane
            Accessible.name: "AI usage details"
            Keys.onLeftPressed: root.selectProvider(root.providerIndex - 1)
            Keys.onRightPressed: root.selectProvider(root.providerIndex + 1)
            Keys.onEscapePressed: root.closePopup()
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_H) {
                    root.selectProvider(root.providerIndex - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_L) {
                    root.selectProvider(root.providerIndex + 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_R) {
                    root.refreshNow(true);
                    event.accepted = true;
                }
            }

            Item {
                width: parent.width
                height: Math.max(titleBlock.implicitHeight, refreshButton.implicitHeight)

                Column {
                    id: titleBlock

                    anchors.left: parent.left
                    anchors.right: refreshButton.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: "AI usage"
                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 19
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: root.bar.services.agentUsageRefreshing ? "Refreshing provider data…" : "Limits and token activity"
                        color: root.bar.services.agentUsageRefreshing ? root.theme.blue : root.theme.overlay
                        font.family: root.theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                }

                ActionButton {
                    id: refreshButton

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 112
                    text: root.bar.services.agentUsageRefreshing ? "󰑐 Refreshing" : "󰑐 Refresh"
                    accessibleName: "Refresh AI usage"
                    accentColor: root.theme.blue
                    enabled: !root.bar.services.agentUsageRefreshing
                    onActivated: root.refreshNow(true)
                }

            }

            Rectangle {
                visible: root.errorText() !== ""
                width: parent.width
                implicitHeight: globalError.implicitHeight + 20
                radius: root.theme.radius
                color: root.alpha(root.theme.red, 0.1)
                border.width: 1
                border.color: root.alpha(root.theme.red, 0.4)

                Text {
                    id: globalError

                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 10
                    text: "󰅚 " + root.errorText() + "\nShowing the most recent available data."
                    color: root.theme.red
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    maximumLineCount: 6
                    elide: Text.ElideRight
                }

            }

            Item {
                visible: !!root.provider
                width: parent.width
                implicitHeight: Math.max(52, heroText.implicitHeight)

                Item {
                    id: heroMark

                    property var candidates: root.iconCandidates(root.provider)
                    property string candidatesKey: candidates.join("\n")
                    property int candidateIndex: 0

                    onCandidatesKeyChanged: candidateIndex = 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    height: 48

                    Image {
                        id: heroImage

                        anchors.fill: parent
                        source: heroMark.candidateIndex < heroMark.candidates.length ? heroMark.candidates[heroMark.candidateIndex] : ""
                        sourceSize.width: 96
                        sourceSize.height: 96
                        fillMode: Image.PreserveAspectFit
                        onStatusChanged: {
                            if (status === Image.Error && heroMark.candidateIndex < heroMark.candidates.length)
                                Qt.callLater(function() {
                                heroMark.candidateIndex++;
                            });

                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: heroImage.status !== Image.Ready
                        text: "󱚣"
                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 30
                    }

                }

                Column {
                    id: heroText

                    anchors.left: heroMark.right
                    anchors.leftMargin: 13
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: root.providerName(root.provider)
                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 21
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: root.heroStatus(root.provider)
                        color: root.dataString(root.provider && root.provider.usageStatusText).trim() !== "" ? root.theme.red : root.theme.subtext
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                }

            }

            Flow {
                id: providerSwitch

                readonly property int columns: Math.max(1, Math.min(3, root.providers.length))
                readonly property real chipWidth: Math.max(82, (width - spacing * (columns - 1)) / columns)

                visible: root.providers.length > 1
                width: parent.width
                spacing: 7
                height: childrenRect.height

                Repeater {
                    model: root.providers

                    ActionButton {
                        required property var modelData
                        required property int index

                        width: providerSwitch.chipWidth
                        text: root.providerName(modelData)
                        accessibleName: "Show " + text + " usage"
                        selected: index === root.providerIndex
                        accentColor: root.theme.mauve
                        onActivated: root.selectProvider(index)
                    }

                }

            }

            Rectangle {
                visible: root.providerProblemTitle(root.provider) !== ""
                width: parent.width
                implicitHeight: providerStatusColumn.implicitHeight + 20
                radius: root.theme.radius
                color: root.alpha(root.theme.red, 0.09)
                border.width: 1
                border.color: root.alpha(root.theme.red, 0.35)

                Column {
                    id: providerStatusColumn

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 10
                    spacing: 4

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: root.providerProblemTitle(root.provider)
                        color: root.theme.red
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    Text {
                        textFormat: Text.PlainText
                        visible: text !== "" && text !== root.providerProblemTitle(root.provider)
                        width: parent.width
                        text: root.providerProblemDetail(root.provider)
                        color: root.theme.subtext
                        font.family: root.theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        maximumLineCount: 5
                        elide: Text.ElideRight
                    }

                }

            }

            Separator {
                visible: balanceSection.visible || limitsSection.visible
            }

            Column {
                id: balanceSection

                readonly property real ratio: root.balance && root.balance.funded > 0 ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1) : -1

                visible: !!root.balance
                width: parent.width
                spacing: 9

                SectionTitle {
                    text: "BALANCE"
                }

                Item {
                    width: parent.width
                    height: Math.max(balanceLabel.implicitHeight, balanceAmount.implicitHeight)

                    Text {
                        id: balanceLabel

                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: balanceAmount.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Prepaid credits"
                        color: root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    Text {
                        id: balanceAmount

                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width * 0.55)
                        text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) + " remaining" : ""
                        color: root.balanceAlarming ? root.theme.red : root.theme.text
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }

                }

                Meter {
                    visible: balanceSection.ratio >= 0
                    value: balanceSection.ratio
                    alarming: root.balanceAlarming
                    draining: true
                }

                Text {
                    textFormat: Text.PlainText
                    visible: text !== ""
                    width: parent.width
                    text: root.balanceDetailText(root.balance)
                    color: root.theme.overlay
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

            }

            Column {
                id: limitsSection

                visible: !!root.provider
                width: parent.width
                spacing: 10

                SectionTitle {
                    text: "LIMITS"
                }

                Repeater {
                    model: root.limits

                    LimitRow {
                        required property var modelData

                        width: limitsSection.width
                        windowData: modelData
                    }

                }

                Text {
                    textFormat: Text.PlainText
                    visible: root.limits.length === 0
                    width: parent.width
                    text: root.balance ? "No rate-limit windows reported; this provider uses prepaid credits." : (root.providerProblemTitle(root.provider) !== "" ? "Limit data is unavailable while the provider reports an error." : "No limit data is available for this provider.")
                    color: root.theme.overlay
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

            }

            Column {
                visible: root.todaySummary(root.provider) !== ""
                width: parent.width
                spacing: 7

                SectionTitle {
                    text: "TODAY"
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: root.todaySummary(root.provider)
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

            }

            Separator {
                visible: daySection.visible
            }

            Column {
                id: daySection

                readonly property var days: root.recentDayRows(root.provider)
                readonly property real peak: Math.max(1, root.weekPeak(root.provider))

                visible: days.length > 0
                width: parent.width
                spacing: 6

                SectionTitle {
                    text: "TOKENS BY DAY"
                }

                Repeater {
                    model: daySection.days

                    DayRow {
                        required property var modelData

                        width: daySection.width
                        day: modelData
                        ratio: root.dayTokens(modelData) / daySection.peak
                        today: String(modelData.date || "") === root.todayDate()
                    }

                }

            }

            Text {
                textFormat: Text.PlainText
                visible: !!root.provider && root.recentDayRows(root.provider).length === 0
                width: parent.width
                text: "No seven-day token history is available."
                color: root.theme.overlay
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Separator {
                visible: modelSection.visible
            }

            Column {
                id: modelSection

                readonly property var rows: root.modelRows(root.provider)

                visible: rows.length > 0
                width: parent.width
                spacing: 7

                SectionTitle {
                    text: "TOKENS BY MODEL"
                }

                Repeater {
                    model: modelSection.rows

                    ModelRow {
                        required property var modelData

                        width: modelSection.width
                        rowData: modelData
                        share: modelData.total / Math.max(1, modelSection.rows[0].total)
                    }

                }

            }

            Text {
                textFormat: Text.PlainText
                visible: !!root.provider && root.modelRows(root.provider).length === 0
                width: parent.width
                text: "No model token breakdown is available."
                color: root.theme.overlay
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Text {
                textFormat: Text.PlainText
                visible: text !== ""
                width: parent.width
                topPadding: 2
                bottomPadding: 2
                text: root.footerText()
                color: root.theme.overlay
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

        }

    }

    component ActionButton: Item {
        id: action

        property string text: ""
        property string accessibleName: text
        property color accentColor: root.theme.blue
        property bool selected: false

        signal activated()

        implicitWidth: Math.max(72, actionLabel.implicitWidth + 20)
        implicitHeight: 30
        activeFocusOnTab: enabled
        opacity: enabled ? 1 : 0.65
        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Accessible.onPressAction: {
            if (!enabled)
                return ;

            activated();
        }
        Keys.onEnterPressed: {
            if (!enabled)
                return ;

            activated();
        }
        Keys.onReturnPressed: {
            if (!enabled)
                return ;

            activated();
        }
        Keys.onSpacePressed: {
            if (!enabled)
                return ;

            activated();
        }

        Rectangle {
            anchors.fill: parent
            radius: Math.max(4, root.theme.radius - 2)
            color: action.selected ? root.alpha(action.accentColor, 0.2) : actionMouse.containsMouse ? root.theme.surface1 : root.theme.base
            border.width: action.activeFocus ? 2 : 1
            border.color: action.selected || action.activeFocus ? action.accentColor : root.theme.surface1
        }

        Text {
            id: actionLabel

            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            anchors.verticalCenter: parent.verticalCenter
            text: action.text
            color: action.selected ? action.accentColor : root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: 12
            font.bold: action.selected
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        MouseArea {
            id: actionMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: action.enabled
            cursorShape: action.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: action.activated()
        }

    }

    component SectionTitle: Item {
        id: sectionTitle

        property string text: ""

        width: parent ? parent.width : 0
        implicitHeight: sectionLabel.implicitHeight

        Text {
            id: sectionLabel

            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: sectionTitle.text
            color: root.theme.overlay
            font.family: root.theme.fontFamily
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1
        }

        Rectangle {
            anchors.left: sectionLabel.right
            anchors.leftMargin: 9
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: root.theme.surface1
        }

    }

    component Separator: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: root.theme.surface1
    }

    component Meter: Item {
        id: meter

        property real value: -1
        property bool alarming: false
        property bool draining: false

        implicitHeight: 6

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.theme.base
        }

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width) * root.clamp(meter.value, 0, 1)
            height: parent.height
            radius: height / 2
            color: meter.alarming ? root.theme.red : meter.draining ? root.theme.peach : root.theme.mauve

            Behavior on width {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

    component LimitRow: Column {
        id: limitRow

        property var windowData: null
        readonly property bool alarming: windowData && windowData.percent >= 0.9
        readonly property var pace: root.paceInfo(windowData)

        spacing: 5

        Item {
            width: parent.width
            height: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

            Text {
                id: limitLabel

                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: limitValue.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: limitRow.windowData ? limitRow.windowData.title : ""
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            Text {
                id: limitValue

                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: limitRow.windowData ? Math.round(limitRow.windowData.percent * 100) + "% used" : "—"
                color: limitRow.alarming ? root.theme.red : root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }

        }

        Meter {
            width: parent.width
            value: limitRow.windowData ? limitRow.windowData.percent : -1
            alarming: limitRow.alarming
        }

        Text {
            textFormat: Text.PlainText
            width: parent.width
            text: {
                var pieces = [];
                var remaining = root.resetMsFor(limitRow.windowData);
                if (remaining > 0)
                    pieces.push("Resets in " + root.formatDuration(remaining));

                if (limitRow.pace.text !== "")
                    pieces.push(limitRow.pace.text);

                return pieces.join(" · ");
            }
            color: limitRow.pace.tone === "warn" ? root.theme.yellow : limitRow.pace.tone === "good" ? root.theme.green : root.theme.overlay
            font.family: root.theme.fontFamily
            font.pixelSize: 10
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

    }

    component DayRow: Item {
        id: dayRow

        property var day: null
        property real ratio: 0
        property bool today: false
        property bool hovered: dayHover.containsMouse

        implicitHeight: 25 + (hovered ? dayDetailText.implicitHeight + 5 : 0)

        Item {
            id: dayMain

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 25

            Text {
                id: dayNameLabel

                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
                color: dayRow.today ? root.theme.text : root.theme.overlay
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                font.bold: dayRow.today
                elide: Text.ElideRight
            }

            Rectangle {
                anchors.left: dayNameLabel.right
                anchors.right: dayTokenLabel.left
                anchors.leftMargin: 7
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                height: 6
                radius: 3
                color: root.theme.base

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width) * root.clamp(dayRow.ratio, 0, 1)
                    height: parent.height
                    radius: parent.radius
                    color: dayRow.today ? root.theme.mauve : root.alpha(root.theme.text, 0.5)

                    Behavior on width {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }

                    }

                }

            }

            Text {
                id: dayTokenLabel

                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 62
                text: root.formatTokenCount(root.dayTokens(dayRow.day))
                color: dayRow.today ? root.theme.text : root.theme.subtext
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                font.bold: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }

        }

        Text {
            id: dayDetailText

            textFormat: Text.PlainText
            visible: dayRow.hovered
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: dayMain.bottom
            anchors.topMargin: 3
            text: root.dayDetail(dayRow.day, dayRow.today)
            color: root.theme.subtext
            font.family: root.theme.fontFamily
            font.pixelSize: 10
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        MouseArea {
            id: dayHover

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.WhatsThisCursor
            Accessible.role: Accessible.StaticText
            Accessible.name: root.dayDetail(dayRow.day, dayRow.today)
        }

    }

    component ModelRow: Item {
        id: modelRow

        property var rowData: null
        property real share: 0
        property bool hovered: modelHover.containsMouse

        implicitHeight: 31 + (hovered ? modelDetailText.implicitHeight + 7 : 0)

        Rectangle {
            id: modelMain

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 31
            radius: Math.max(4, root.theme.radius - 2)
            color: root.alpha(root.theme.text, 0.05)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, parent.width) * root.clamp(modelRow.share, 0, 1)
                radius: parent.radius
                color: root.alpha(root.theme.mauve, 0.15)

                Behavior on width {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }

                }

            }

            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.right: modelTokens.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: modelRow.rowData ? modelRow.rowData.name : ""
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            Text {
                id: modelTokens

                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: modelRow.rowData ? root.formatTokenCount(modelRow.rowData.total) : ""
                color: root.theme.subtext
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }

        }

        Text {
            id: modelDetailText

            textFormat: Text.PlainText
            visible: modelRow.hovered
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: modelMain.bottom
            anchors.topMargin: 4
            text: root.modelDetail(modelRow.rowData)
            color: root.theme.subtext
            font.family: root.theme.fontFamily
            font.pixelSize: 10
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        MouseArea {
            id: modelHover

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.WhatsThisCursor
            Accessible.role: Accessible.StaticText
            Accessible.name: root.modelDetail(modelRow.rowData)
        }

    }

}
