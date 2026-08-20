import "../components"
import QtQuick
import Quickshell.Bluetooth
import Quickshell.Services.UPower

Pill {
    id: root

    required property var bar
    property var osd: null
    required property var bluetoothMenu
    required property var wifiMenu
    required property var tailscaleMenu
    required property var tailscaleService
    required property var panelScreen
    property bool compact: false
    property bool narrow: false
    property bool iconOnly: false
    property bool monochrome: false
    readonly property var services: bar.services
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var bluetoothDevices: adapter && adapter.devices ? adapter.devices.values : []
    readonly property var battery: UPower.displayDevice
    readonly property int batteryCriticalPercent: 10
    readonly property int batteryWarningPercent: 20
    readonly property int statusIconSlotWidth: narrow ? 24 : 28
    readonly property real nativeStatusIconSize: 11

    function connectedBluetoothCount() {
        var count = 0;
        var candidateCount = Math.min(bluetoothDevices.length, 50);
        for (var i = 0; i < candidateCount; i++) {
            if (bluetoothDevices[i].connected)
                count++;

        }
        return count;
    }

    function batteryPercent() {
        // Quickshell normalizes UPower's 0..100 D-Bus value to 0..1.
        var percent = battery && battery.isPresent ? Number(battery.percentage) * 100 : 0;
        return isFinite(percent) ? Math.max(0, Math.min(100, percent)) : 0;
    }

    function batteryIsCharging() {
        return battery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.PendingCharge);
    }

    function batteryIsDischarging() {
        return battery && (battery.state === UPowerDeviceState.Discharging || battery.state === UPowerDeviceState.PendingDischarge);
    }

    function batteryIcon() {
        if (!battery || !battery.isPresent)
            return "";

        if (batteryIsCharging())
            return "󰂄";

        if (battery.state === UPowerDeviceState.FullyCharged)
            return "󰁹";

        var p = batteryPercent();
        return p >= 90 ? "" : p >= 65 ? "" : p >= 40 ? "" : p >= 15 ? "" : "";
    }

    function batteryStateText() {
        if (!battery)
            return "Unknown";

        if (batteryIsCharging())
            return "Charging";

        if (batteryIsDischarging())
            return "Discharging";

        if (battery.state === UPowerDeviceState.FullyCharged)
            return "Fully charged";

        if (battery.state === UPowerDeviceState.Empty)
            return "Empty";

        return "Unknown state";
    }

    function formatEta(seconds) {
        var value = Math.max(0, Math.round(Number(seconds || 0)));
        if (!value)
            return "";

        var hours = Math.floor(value / 3600);
        var minutes = Math.floor((value % 3600) / 60);
        return (hours ? hours + "h " : "") + minutes + "m";
    }

    function batteryText() {
        var p = batteryPercent();
        var rate = battery ? Number(battery.changeRate || 0) : 0;
        var critical = p <= batteryCriticalPercent;
        var direction = batteryIsCharging() ? "↑" : batteryIsDischarging() ? "↓" : "";
        if (root.iconOnly || root.narrow)
            return (critical ? "! " : "") + batteryIcon();

        return (critical ? "! " : "") + batteryIcon() + " " + Math.round(p) + "%" + (Math.abs(rate) > 0.05 ? " " + direction + Math.abs(rate).toFixed(1) + "W" : "");
    }

    function batteryTooltip() {
        if (!battery || !battery.isPresent)
            return "";

        var eta = "";
        if (batteryIsCharging())
            eta = formatEta(battery.timeToFull);
        else if (batteryIsDischarging())
            eta = formatEta(battery.timeToEmpty);
        var rate = Number(battery.changeRate || 0);
        var direction = batteryIsCharging() ? "charging at " : batteryIsDischarging() ? "discharging at " : "power rate ";
        return batteryStateText() + " · " + Math.round(batteryPercent()) + "%" + (Math.abs(rate) > 0.05 ? " · " + direction + Math.abs(rate).toFixed(1) + "W" : "") + (eta ? " · ETA " + eta : "");
    }

    function batteryColor() {
        var p = batteryPercent();
        if (p <= batteryCriticalPercent)
            return theme.red;

        if (p <= batteryWarningPercent)
            return theme.yellow;

        if (batteryIsCharging())
            return theme.green;

        return theme.text;
    }

    function profileName() {
        if (!services.powerProfilesAvailable)
            return services.powerProfilesState === "unknown" ? "unknown" : "unavailable";

        if (PowerProfiles.profile === PowerProfile.Performance)
            return "performance";

        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            return "power saver";

        if (PowerProfiles.profile === PowerProfile.Balanced)
            return "balanced";

        return "unknown";
    }

    function profileIcon() {
        if (!services.powerProfilesAvailable)
            return "?";

        return PowerProfiles.profile === PowerProfile.Performance ? "" : PowerProfiles.profile === PowerProfile.PowerSaver ? "" : PowerProfiles.profile === PowerProfile.Balanced ? "" : "?";
    }

    function profileColor() {
        if (!services.powerProfilesAvailable)
            return theme.overlay;

        return PowerProfiles.profile === PowerProfile.Performance ? theme.red : PowerProfiles.profile === PowerProfile.PowerSaver ? theme.green : PowerProfiles.profile === PowerProfile.Balanced ? theme.yellow : theme.overlay;
    }

    function powerProfileKnown() {
        return services.powerProfilesAvailable && (PowerProfiles.profile === PowerProfile.PowerSaver || PowerProfiles.profile === PowerProfile.Balanced || PowerProfiles.profile === PowerProfile.Performance);
    }

    function cyclePowerProfile() {
        if (!powerProfileKnown())
            return ;

        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced;
        else if (PowerProfiles.profile === PowerProfile.Balanced)
            PowerProfiles.profile = PowerProfiles.hasPerformanceProfile ? PowerProfile.Performance : PowerProfile.PowerSaver;
        else
            PowerProfiles.profile = PowerProfile.PowerSaver;

        if (osd && typeof osd.showPowerProfile === "function")
            Qt.callLater(function() {
                root.osd.showPowerProfile();
            });
    }

    theme: bar.theme

    Row {
        spacing: 0

        StatusButton {
            id: tailscaleButton

            visible: !root.narrow
            text: ""
            allowSecondary: true
            foreground: root.tailscaleService.running ? (root.monochrome ? root.theme.subtext : root.theme.lavender) : root.tailscaleService.needsLogin ? root.theme.yellow : root.theme.overlay
            tooltip: "Tailscale · " + String(root.tailscaleService.statusText || "Unavailable") + "\nLeft click: open · Right click: toggle"
            onActivated: root.tailscaleMenu.showOnScreen(root.panelScreen)
            onSecondaryActivated: root.tailscaleService.toggle()

            TailscaleIcon {
                anchors.centerIn: parent
                iconSize: root.nativeStatusIconSize
                foreground: tailscaleButton.foreground
                badgeColor: root.theme.red
                crossed: !root.tailscaleService.running && !root.tailscaleService.needsLogin
                warning: root.tailscaleService.needsLogin
            }
        }

        StatusButton {
            visible: !root.compact
            text: root.services.idleInhibited ? "󰅶" : "󰛊"
            foreground: root.monochrome ? root.theme.subtext : root.services.idleInhibited ? root.theme.green : root.theme.yellow
            tooltip: root.services.idleInhibited ? "Idle inhibited (click to allow idle)" : "Idle allowed (click to inhibit)"
            onActivated: root.services.idleInhibited = !root.services.idleInhibited
        }

        StatusButton {
            visible: !!root.adapter && !root.narrow
            text: root.adapter && root.adapter.enabled ? "" : "󰂲"
            foreground: root.adapter && root.adapter.enabled ? (root.monochrome ? root.theme.subtext : root.connectedBluetoothCount() ? root.theme.green : root.theme.blue) : root.theme.overlay
            tooltip: root.adapter ? (root.adapter.enabled ? "Bluetooth · " + root.connectedBluetoothCount() + " connected" : "Bluetooth disabled") : "No Bluetooth adapter"
            onActivated: root.bluetoothMenu.showOnScreen(root.panelScreen)
        }

        StatusButton {
            text: root.profileIcon()
            foreground: root.monochrome ? root.theme.subtext : root.profileColor()
            tooltip: root.powerProfileKnown() ? "Power profile: " + root.profileName() + (PowerProfiles.hasPerformanceProfile ? "" : " (performance unavailable)") + "\nClick to cycle" : "Power profile " + root.profileName()
            onActivated: root.cyclePowerProfile()
        }

        StatusButton {
            text: String(root.services.network.icon || "󰖪")
            foreground: root.services.network.connected ? (root.monochrome ? root.theme.subtext : root.theme.sapphire) : root.theme.red
            tooltip: String(root.services.network.tooltip || "Network unavailable")
            onActivated: root.wifiMenu.showOnScreen(root.panelScreen)
        }

        StatusButton {
            visible: root.services.voxText !== "" && !root.compact
            text: root.services.voxText
            foreground: root.services.voxAvailable ? (root.monochrome ? root.theme.subtext : root.theme.mauve) : root.theme.red
            tooltip: root.services.voxTooltip
            onActivated: root.services.restartVox()
        }

        StatusButton {
            visible: String(root.services.recording.text || "") !== ""
            fixedIconSlot: false
            text: "● " + String(root.services.recording.text || "")
            foreground: root.theme.red
            highlighted: true
            tooltip: String(root.services.recording.tooltip || "Screen recording active")
            onActivated: root.services.toggleRecording()
        }

        ModuleButton {
            visible: root.battery && root.battery.isPresent
            bar: root.bar
            theme: root.theme
            actionable: false
            horizontalPadding: root.iconOnly ? 5 : 7
            text: root.batteryText()
            foreground: root.monochrome && root.batteryPercent() > root.batteryWarningPercent ? root.theme.subtext : root.batteryColor()
            tooltip: root.batteryTooltip()
        }

    }

    component StatusButton: ModuleButton {
        property bool allowSecondary: false
        property bool fixedIconSlot: true
        signal activated()
        signal secondaryActivated()

        bar: root.bar
        theme: root.theme
        width: fixedIconSlot ? root.statusIconSlotWidth : implicitWidth
        horizontalPadding: fixedIconSlot ? 0 : (root.narrow ? 5 : 7)
        acceptedButtons: allowSecondary ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
        actionable: true
        onClicked: function(button) {
            if (button === Qt.LeftButton)
                activated();
            else if (allowSecondary && button === Qt.RightButton)
                secondaryActivated();

        }
    }

}
