pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications

Item {
    id: root

    property var entries: []
    property int revision: 0
    property bool dnd: false
    readonly property int maximumToasts: 5
    readonly property int entryCount: entries.length

    signal notificationReceived(var notification)

    function bounded(value, maximum) {
        return String(value === undefined || value === null ? "" : value).slice(0, maximum);
    }

    function oneLine(value, maximum) {
        return bounded(value, maximum * 2).replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim().slice(0, maximum);
    }

    function focusedScreenName() {
        var monitor = Hyprland.focusedMonitor;
        if (monitor && monitor.name)
            return bounded(monitor.name, 160);
        var screens = Quickshell.screens;
        return screens.length > 0 ? bounded(screens[0].name, 160) : "";
    }

    function snapshotActions(notification) {
        var result = [];
        var actions = notification && notification.actions ? notification.actions : [];
        for (var i = 0; i < actions.length && result.length < 3; ++i) {
            var action = actions[i];
            if (!action)
                continue;
            var identifier = bounded(action.identifier, 128);
            if (identifier === "")
                continue;
            result.push({
                "identifier": identifier,
                "text": oneLine(action.text || "Action", 80)
            });
        }
        return result;
    }

    function notificationHasDefaultAction(notification) {
        var actions = notification && notification.actions ? notification.actions : [];
        for (var i = 0; i < actions.length; ++i) {
            if (actions[i] && String(actions[i].identifier) === "default")
                return true;
        }
        return false;
    }

    function copyEntry(entry) {
        var copy = {};
        for (var key in entry)
            copy[key] = entry[key];
        return copy;
    }

    function entryFromNotification(notification, previous, received) {
        var old = previous || null;
        return {
            "id": Number(notification.id),
            "appName": oneLine(notification.appName || "Application", 80),
            "icon": bounded(notification.appIcon, 160),
            "summary": oneLine(notification.summary || "Notification", 180),
            "body": bounded(notification.body, 1000),
            "urgency": Number(notification.urgency),
            "actions": snapshotActions(notification),
            "hasDefaultAction": notificationHasDefaultAction(notification),
            "live": notification,
            "actionable": true,
            "timestamp": received || !old ? Date.now() : old.timestamp,
            "screenName": received || !old ? focusedScreenName() : old.screenName,
            "toast": !dnd
        };
    }

    function indexForId(identifier) {
        var numericId = Number(identifier);
        for (var i = 0; i < entries.length; ++i) {
            if (Number(entries[i].id) === numericId)
                return i;
        }
        return -1;
    }

    function publish(nextEntries) {
        var kept = nextEntries.slice(0, maximumToasts);
        var dropped = nextEntries.slice(maximumToasts);
        entries = kept;
        ++revision;

        for (var i = 0; i < dropped.length; ++i) {
            var entry = dropped[i];
            if (!entry || !entry.actionable || !entry.live)
                continue;
            try {
                entry.live.expire();
            } catch (error) {
            }
        }
    }

    function receiveNotification(notification) {
        if (!notification)
            return;
        var index = indexForId(notification.id);
        var previous = index >= 0 ? entries[index] : null;
        var entry = entryFromNotification(notification, previous, true);
        var nextEntries = entries.slice();
        if (index >= 0)
            nextEntries.splice(index, 1);
        nextEntries.unshift(entry);
        publish(nextEntries);
        notificationReceived(notification);
    }

    function adoptNotification(notification) {
        if (!notification)
            return;
        var index = indexForId(notification.id);
        if (index >= 0) {
            updateNotification(notification);
            return;
        }
        var nextEntries = entries.slice();
        nextEntries.unshift(entryFromNotification(notification, null, false));
        publish(nextEntries);
    }

    function updateNotification(notification) {
        if (!notification)
            return;
        var index = indexForId(notification.id);
        if (index < 0)
            return;
        var nextEntries = entries.slice();
        var updated = entryFromNotification(notification, entries[index], false);
        updated.toast = entries[index].toast && !dnd;
        nextEntries[index] = updated;
        publish(nextEntries);
    }

    function finalizeNotification(notification) {
        if (!notification)
            return;
        var index = indexForId(notification.id);
        if (index < 0)
            return;
        var nextEntries = entries.slice();
        nextEntries.splice(index, 1);
        publish(nextEntries);
    }

    function toastEntries(screenName) {
        if (dnd)
            return [];
        var wanted = bounded(screenName, 160);
        var result = [];
        for (var i = 0; i < entries.length && result.length < maximumToasts; ++i) {
            if (entries[i].toast && entries[i].screenName === wanted)
                result.push(entries[i]);
        }
        return result;
    }

    function dismissEntry(identifier) {
        var index = indexForId(identifier);
        if (index < 0)
            return;
        var entry = entries[index];
        if (!entry.live)
            return;
        try {
            entry.live.dismiss();
        } catch (error) {
        }
    }

    function dismissLatest() {
        for (var i = 0; i < entries.length; ++i) {
            if (entries[i].live) {
                dismissEntry(entries[i].id);
                return;
            }
        }
    }

    function clearAll() {
        var live = [];
        for (var i = 0; i < entries.length; ++i) {
            if (entries[i].live)
                live.push(entries[i].live);
        }
        entries = [];
        ++revision;
        for (var j = 0; j < live.length; ++j) {
            try {
                live[j].dismiss();
            } catch (error) {
            }
        }
    }

    function toggleDnd() {
        dnd = !dnd;
        if (dnd)
            clearAll();
        else
            ++revision;
    }

    function invokeNamedAction(identifier, actionIdentifier) {
        var index = indexForId(identifier);
        if (index < 0 || !entries[index].live)
            return;
        var wanted = bounded(actionIdentifier, 128);
        var actions = entries[index].live.actions || [];
        for (var i = 0; i < actions.length; ++i) {
            var action = actions[i];
            if (action && String(action.identifier) === wanted) {
                try {
                    action.invoke();
                } catch (error) {
                }
                return;
            }
        }
    }

    function invokeDefault(identifier) {
        invokeNamedAction(identifier, "default");
    }

    NotificationServer {
        id: server

        keepOnReload: false
        persistenceSupported: false
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: false
        inlineReplySupported: false
        onNotification: function(notification) {
            if (root.dnd) {
                notification.tracked = false;
                return;
            }
            notification.tracked = true;
            root.receiveNotification(notification);
        }
    }

    Instantiator {
        model: server.trackedNotifications

        delegate: NotificationTracker {
            required property var modelData

            service: root
            notification: modelData
        }
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "notifications-dismiss"
        description: "Dismiss latest notification"
        onPressed: root.dismissLatest()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "notifications-clear"
        description: "Dismiss all notifications"
        onPressed: root.clearAll()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "notifications-dnd"
        description: "Toggle notification do not disturb"
        onPressed: root.toggleDnd()
    }

    IpcHandler {
        target: "notifications"

        function dismissLatest(): void {
            root.dismissLatest();
        }

        function clearAll(): void {
            root.clearAll();
        }

        function toggleDnd(): void {
            root.toggleDnd();
        }

        function currentDnd(): bool {
            return root.dnd;
        }

        function entryCount(): int {
            return root.entryCount;
        }

        function toastCount(): int {
            return root.toastEntries(root.focusedScreenName()).length;
        }
    }
}
