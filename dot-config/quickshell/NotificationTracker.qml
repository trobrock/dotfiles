import QtQuick

Item {
    id: root

    required property var service
    required property var notification

    visible: false
    width: 0
    height: 0

    function effectiveTimeout() {
        if (!notification)
            return 0;
        var requested = Number(notification.expireTimeout);
        if (!isFinite(requested) || requested <= 0)
            return Number(notification.urgency) === 2 ? 15000 : 7000;
        return Math.max(1500, Math.min(15000, Math.round(requested)));
    }

    function restartExpiry() {
        expiry.stop();
        var timeout = effectiveTimeout();
        if (timeout > 0) {
            expiry.interval = timeout;
            expiry.restart();
        }
    }

    function scheduleUpdate() {
        if (notification) {
            coalesce.restart();
            restartExpiry();
        }
    }

    function syncNow() {
        coalesce.stop();
        var current = notification;
        if (current)
            service.updateNotification(current);
    }

    Component.onCompleted: {
        if (notification) {
            service.adoptNotification(notification);
            restartExpiry();
        }
    }

    Connections {
        target: root.notification
        ignoreUnknownSignals: false

        function onAppNameChanged() {
            root.scheduleUpdate();
        }

        function onSummaryChanged() {
            root.scheduleUpdate();
        }

        function onBodyChanged() {
            root.scheduleUpdate();
        }

        function onAppIconChanged() {
            root.scheduleUpdate();
        }

        function onUrgencyChanged() {
            root.scheduleUpdate();
        }

        function onActionsChanged() {
            root.scheduleUpdate();
        }

        function onTransientChanged() {
            root.scheduleUpdate();
        }

        function onExpireTimeoutChanged() {
            root.scheduleUpdate();
        }

        function onClosed(reason) {
            var current = root.notification;
            expiry.stop();
            coalesce.stop();
            if (current) {
                root.service.updateNotification(current);
                root.service.finalizeNotification(current, reason);
            }
            root.notification = null;
        }
    }

    Connections {
        target: root.service

        function onNotificationReceived(received) {
            if (root.notification && received === root.notification)
                root.restartExpiry();
        }
    }

    Timer {
        id: coalesce

        interval: 0
        onTriggered: root.syncNow()
    }

    Timer {
        id: expiry

        repeat: false
        onTriggered: {
            var current = root.notification;
            if (!current)
                return;
            try {
                current.expire();
            } catch (error) {
            }
        }
    }
}
