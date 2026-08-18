import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"
import "modules"

Item {
    id: root

    required property var theme
    required property var services
    required property var osd
    required property var bluetoothMenu
    required property var wifiMenu
    readonly property bool testMode: Quickshell.env("QUICKSHELL_BAR_TEST") === "1"
    property var activePopup: null
    property var tooltipTarget: null
    property string tooltipText: ""
    property bool tooltipVisible: false

    function claimPopup(owner) {
        clearTooltip(null);
        if (activePopup && activePopup !== owner && typeof activePopup.closePopup === "function")
            activePopup.closePopup();

        activePopup = owner;
    }

    function releasePopup(owner) {
        if (activePopup === owner)
            activePopup = null;

    }

    function requestTooltip(target, text) {
        tooltipVisible = false;
        tooltipTarget = target;
        tooltipText = text;
        tooltipDelay.restart();
    }

    function clearTooltip(target) {
        if (target && tooltipTarget !== target)
            return ;

        tooltipDelay.stop();
        tooltipVisible = false;
        tooltipTarget = null;
        tooltipText = "";
    }

    Timer {
        id: tooltipDelay

        interval: 450
        onTriggered: {
            if (root.tooltipTarget && root.tooltipTarget.tooltipHovered !== false)
                root.tooltipVisible = true;

        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel

                required property var modelData
                // A continuous density value lets text budgets shrink before modules
                // have to switch to their smallest representation.
                readonly property real density: Math.max(0, Math.min(1, (width - 1000) / 500))
                readonly property bool compact: density < 0.9
                readonly property bool narrow: density < 0.5
                readonly property real rightCoreWidth: status.implicitWidth + audio.implicitWidth + clock.implicitWidth + 26

                screen: modelData
                color: "transparent"
                implicitHeight: root.theme.barHeight
                exclusionMode: root.testMode ? ExclusionMode.Ignore : ExclusionMode.Auto
                surfaceFormat.opaque: false
                WlrLayershell.namespace: root.testMode ? "quickshell-bar-test" : "quickshell-bar"
                WlrLayershell.layer: WlrLayer.Top

                anchors {
                    top: !root.testMode
                    bottom: root.testMode
                    left: true
                    right: true
                }

                IdleInhibitor {
                    window: panel
                    enabled: root.services.idleInhibited
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(root.theme.base.r, root.theme.base.g, root.theme.base.b, 0.78)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Qt.rgba(root.theme.surface1.r, root.theme.surface1.g, root.theme.surface1.b, 0.7)
                }

                Item {
                    id: content

                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8

                    Item {
                        id: leftRegion

                        anchors.left: parent.left
                        anchors.right: rightGroup.left
                        anchors.rightMargin: 12
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        clip: true

                        BarGroup {
                            id: leftGroup

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            flat: true
                            theme: root.theme
                            itemSpacing: 5

                            Workspaces {
                                embedded: true
                                minimal: true
                                bar: root
                                panelScreen: panel.screen
                                compact: panel.compact
                                narrow: panel.narrow
                                maximumWidth: Math.max(160, Math.min(content.width * 0.44, content.width - panel.rightCoreWidth - 48))
                            }
                        }
                    }

                    BarGroup {
                        id: rightGroup

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        flat: true
                        theme: root.theme
                        itemSpacing: 3

                        AiUsage {
                            id: ai

                            embedded: true
                            visible: hasProviders && leftGroup.implicitWidth + panel.rightCoreWidth + implicitWidth + 18 <= content.width
                            bar: root
                            onVisibleChanged: {
                                if (!visible)
                                    closePopup();

                            }
                        }

                        BarDivider {
                            visible: ai.visible
                            theme: root.theme
                        }

                        StatusIsland {
                            id: status

                            embedded: true
                            bar: root
                            compact: panel.compact
                            narrow: panel.narrow
                            iconOnly: true
                            monochrome: true
                            osd: root.osd
                            bluetoothMenu: root.bluetoothMenu
                            wifiMenu: root.wifiMenu
                            panelScreen: panel.screen
                        }

                        BarDivider {
                            theme: root.theme
                        }

                        Audio {
                            id: audio

                            embedded: true
                            bar: root
                            compact: true
                            monochrome: true
                        }

                        BarDivider {
                            theme: root.theme
                        }

                        Clock {
                            id: clock

                            embedded: true
                            bar: root
                            compact: true
                            monochrome: true
                        }
                    }

                    BarGroup {
                        id: contextGroup

                        readonly property real centerSpace: Math.max(0, 2 * Math.min(content.width / 2 - leftGroup.implicitWidth - 10, rightGroup.x - content.width / 2 - 10))
                        readonly property string upcomingTitle: String(root.services.calendar.text || "").trim()
                        readonly property bool hasUpcomingEvent: upcomingTitle !== "" && upcomingTitle.toLowerCase() !== "no upcoming events"

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        visible: centerSpace >= 80 && hasUpcomingEvent
                        flat: true
                        theme: root.theme

                        ScriptPill {
                            id: calendar

                            embedded: true
                            bar: root
                            icon: "󰃭"
                            text: contextGroup.upcomingTitle
                            tooltip: String(root.services.calendar.tooltip || "Calendar")
                            foreground: root.theme.subtext
                            actionable: true
                            maxTextWidth: Math.min(320, Math.max(56, contextGroup.centerSpace - 10))
                            onActivated: root.services.openCalendarEvent()
                        }
                    }
                }

                PopupWindow {
                    id: tooltipWindow

                    readonly property bool forThisWindow: root.tooltipTarget && root.tooltipTarget.QsWindow && root.tooltipTarget.QsWindow.window === panel

                    visible: root.tooltipVisible && forThisWindow && root.tooltipText !== ""
                    color: "transparent"
                    implicitWidth: Math.min(360, tooltipLabel.implicitWidth + 22)
                    implicitHeight: tooltipLabel.implicitHeight + 16

                    anchor {
                        id: tipAnchor

                        window: panel
                        adjustment: PopupAdjustment.Slide
                        edges: Edges.Top | Edges.Left
                        gravity: Edges.Bottom | Edges.Right
                        rect.width: 1
                        rect.height: 1
                        onAnchoring: {
                            if (!tooltipWindow.forThisWindow)
                                return ;

                            var target = root.tooltipTarget;
                            var x = target.width / 2 - tooltipWindow.implicitWidth / 2;
                            var y = root.testMode ? -tooltipWindow.implicitHeight - 6 : target.height + 6;
                            var point = panel.contentItem.mapFromItem(target, x, y);
                            point.x = Math.max(6, Math.min(point.x, panel.width - tooltipWindow.implicitWidth - 6));
                            tipAnchor.rect.x = Math.round(point.x);
                            tipAnchor.rect.y = Math.round(point.y);
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: root.theme.radius
                        color: root.theme.surfaceSolid
                        border.width: 1
                        border.color: root.theme.surface1

                        Text {
                            id: tooltipLabel

                            anchors.centerIn: parent
                            width: Math.min(338, implicitWidth)
                            text: root.tooltipText
                            textFormat: Text.PlainText
                            color: root.theme.text
                            font.family: root.theme.fontFamily
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                        }

                    }

                }

            }

        }

    }

}
