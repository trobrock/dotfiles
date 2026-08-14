import QtQuick
import Quickshell.Services.SystemTray

Row {
    id: root

    required property var bar
    property int maxItems: 99
    // Leave room for the overflow affordance even when a caller asks for an
    // effectively unlimited tray. This keeps an unexpected tray population
    // from consuming the bar.
    readonly property int visibleLimit: Math.max(1, Math.min(maxItems, 7))
    readonly property int activeItemCount: countActiveItems()
    readonly property int shownItemCount: Math.min(visibleLimit, Math.max(0, activeItemCount - pageOffset))
    readonly property int hiddenItemCount: Math.max(0, activeItemCount - shownItemCount)
    property int pageOffset: 0

    function countActiveItems() {
        var values = SystemTray.items.values;
        var count = 0;
        for (var i = 0; i < values.length; i++) {
            if (values[i].status !== Status.Passive)
                count++;

        }
        return count;
    }

    function activeOrdinal(item) {
        var values = SystemTray.items.values;
        var ordinal = 0;
        for (var i = 0; i < values.length; i++) {
            if (values[i] === item)
                return ordinal;

            if (values[i].status !== Status.Passive)
                ordinal++;

        }
        return ordinal;
    }

    function showNextPage() {
        var next = pageOffset + visibleLimit;
        pageOffset = next < activeItemCount ? next : 0;
    }

    spacing: 1
    onActiveItemCountChanged: {
        if (pageOffset >= activeItemCount)
            pageOffset = 0;

    }

    Repeater {
        model: SystemTray.items

        Item {
            required property var modelData
            readonly property int ordinal: root.activeOrdinal(modelData)
            readonly property bool shown: modelData.status !== Status.Passive && ordinal >= root.pageOffset && ordinal < root.pageOffset + root.visibleLimit
            readonly property bool tooltipHovered: trayMouse.containsMouse

            visible: shown
            implicitWidth: shown ? 25 : 0
            implicitHeight: 25
            activeFocusOnTab: shown
            Accessible.role: Accessible.Button
            Accessible.name: String(modelData.tooltipTitle || modelData.title || modelData.id || "Tray item")
            onShownChanged: {
                if (!shown)
                    root.bar.clearTooltip(this);

            }
            Keys.onEnterPressed: modelData.activate()
            Keys.onReturnPressed: modelData.activate()
            Keys.onSpacePressed: modelData.activate()

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: root.bar.theme.lavender
            }

            Image {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: modelData.icon
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                id: trayMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onEntered: root.bar.requestTooltip(parent, String(modelData.tooltipTitle || modelData.title || modelData.id || "Tray item"))
                onExited: root.bar.clearTooltip(parent)
                onClicked: function(event) {
                    if (event.button === Qt.MiddleButton) {
                        modelData.secondaryActivate();
                    } else if (event.button === Qt.RightButton || modelData.onlyMenu) {
                        var point = parent.QsWindow.contentItem.mapFromItem(parent, event.x, event.y);
                        modelData.display(parent.QsWindow.window, point.x, point.y);
                    } else {
                        modelData.activate();
                    }
                }
                onWheel: function(event) {
                    modelData.scroll(event.angleDelta.y, false);
                }
            }

        }

    }

    Item {
        id: overflow

        readonly property bool tooltipHovered: overflowMouse.containsMouse

        visible: root.hiddenItemCount > 0
        implicitWidth: visible ? Math.max(25, overflowLabel.implicitWidth + 8) : 0
        implicitHeight: 25
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: root.hiddenItemCount + " more tray items; show next page"
        onVisibleChanged: {
            if (!visible)
                root.bar.clearTooltip(overflow);

        }
        Keys.onEnterPressed: root.showNextPage()
        Keys.onReturnPressed: root.showNextPage()
        Keys.onSpacePressed: root.showNextPage()

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: overflowMouse.containsMouse ? root.bar.theme.surface1 : "transparent"
            border.width: overflow.activeFocus ? 2 : 0
            border.color: root.bar.theme.lavender
        }

        Text {
            id: overflowLabel

            anchors.centerIn: parent
            text: "+" + root.hiddenItemCount
            color: root.bar.theme.subtext
            font.family: root.bar.theme.fontFamily
            font.pixelSize: 11
        }

        MouseArea {
            id: overflowMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onEntered: root.bar.requestTooltip(overflow, root.hiddenItemCount + " tray items not on this page · click for next page")
            onExited: root.bar.clearTooltip(overflow)
            onClicked: function(event) {
                if (event.button === Qt.RightButton)
                    root.pageOffset = 0;
                else
                    root.showNextPage();
            }
        }

    }

}
