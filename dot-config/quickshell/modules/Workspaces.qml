import "../components"
import QtQuick
import Quickshell.Hyprland

Pill {
    id: root

    required property var bar
    required property var panelScreen
    property bool compact: false
    property bool narrow: false
    property bool minimal: false
    property real maximumWidth: Number.POSITIVE_INFINITY
    readonly property var displayedWorkspaceIds: workspaceIds()
    readonly property int workspaceCount: displayedWorkspaceIds.length
    readonly property real buttonWidthBudget: workspaceCount > 0 ? Math.max(18, (maximumWidth - (embedded ? 4 : 20) - Math.max(0, workspaceCount - 1) * (embedded ? 1 : 7)) / workspaceCount) : 18

    function workspaceById(id) {
        var values = Hyprland.workspaces.values;
        for (var i = 0; i < values.length; i++) {
            if (values[i].id === id)
                return values[i];

        }
        return null;
    }

    function workspaceIds() {
        var ids = [1, 2, 3, 4, 5];
        var values = Hyprland.workspaces.values;
        for (var i = 0; i < values.length; i++) {
            var id = values[i].id;
            // Keep the five fixed launch targets and only occupied extras in
            // the supported 6-10 range. Special and higher workspaces do not
            // get to make every monitor's bar grow without bound.
            if (id >= 6 && id <= 10 && ids.indexOf(id) < 0)
                ids.push(id);

        }
        ids.sort(function(a, b) {
            return a - b;
        });
        return ids;
    }

    function icon(id) {
        return ({
            "1": "",
            "2": "",
            "3": "",
            "4": "",
            "5": "",
            "6": "󰄛"
        })[id] || "";
    }

    function label(id) {
        var glyph = icon(id);
        if (minimal || narrow)
            return String(id);

        if (compact)
            return glyph ? id + ":" + glyph : String(id);

        return glyph ? id + ": " + glyph : String(id);
    }

    theme: bar.theme

    Row {
        spacing: 1

        Repeater {
            model: root.displayedWorkspaceIds

            ModuleButton {
                required property int modelData
                readonly property var workspace: root.workspaceById(modelData)
                readonly property bool focused: !!workspace && workspace.focused
                readonly property bool active: !!workspace && workspace.active
                readonly property bool urgent: !!workspace && workspace.urgent
                readonly property bool onThisMonitor: active && workspace.monitor && root.panelScreen && workspace.monitor.name === root.panelScreen.name

                bar: root.bar
                theme: root.theme
                text: (urgent ? "!" : "") + root.label(modelData)
                foreground: root.minimal ? (urgent ? root.theme.red : focused ? root.theme.lavender : onThisMonitor ? root.theme.blue : workspace ? root.theme.subtext : root.theme.overlay) : urgent || focused || onThisMonitor ? root.theme.base : workspace ? root.theme.text : root.theme.overlay
                background: root.minimal ? "transparent" : urgent ? root.theme.red : focused ? root.theme.lavender : onThisMonitor ? root.theme.blue : "transparent"
                indicatorColor: root.minimal ? (urgent ? root.theme.red : focused ? root.theme.lavender : onThisMonitor ? root.theme.blue : "transparent") : "transparent"
                indicatorWidth: 14
                horizontalPadding: root.minimal ? 8 : root.narrow ? 5 : root.compact ? 6 : 8
                maxTextWidth: Math.max(8, root.buttonWidthBudget - horizontalPadding * 2)
                tooltip: urgent ? "Workspace " + modelData + " has an urgent window" : active ? "Workspace " + modelData + (onThisMonitor ? " active on this monitor" : " active on another monitor") : "Switch to workspace " + modelData
                acceptedButtons: Qt.LeftButton
                onClicked: function(button) {
                    if (button !== Qt.LeftButton)
                        return ;

                    if (workspace)
                        workspace.activate();
                    else
                        Hyprland.dispatch("workspace " + modelData);
                }
            }

        }

    }

}
