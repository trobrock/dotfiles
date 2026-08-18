import "../components"
import QtQuick
import Quickshell

Pill {
    id: root

    required property var bar
    property bool compact: false
    property bool monochrome: false
    property date now: clock.date
    property bool popupOpen: false
    property bool popupPinned: false
    property bool hoverOpen: false
    property bool hoverSuppressed: false
    property int viewYear: now.getFullYear()
    property int viewMonth: now.getMonth()

    function closePopup() {
        hoverDelay.stop();
        hoverCloseDelay.stop();
        popupPinned = false;
        hoverOpen = false;
        popupOpen = false;
    }

    function goToToday() {
        viewYear = now.getFullYear();
        viewMonth = now.getMonth();
    }

    function moveMonth(delta) {
        var next = new Date(viewYear, viewMonth + delta, 1);
        viewYear = next.getFullYear();
        viewMonth = next.getMonth();
    }

    function cellDate(index) {
        var first = new Date(viewYear, viewMonth, 1);
        var mondayOffset = (first.getDay() + 6) % 7;
        return new Date(viewYear, viewMonth, index - mondayOffset + 1);
    }

    function isToday(date) {
        return date.toDateString() === now.toDateString();
    }

    function isoWeek(date) {
        var value = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        var day = value.getUTCDay() || 7;
        value.setUTCDate(value.getUTCDate() + 4 - day);
        var yearStart = new Date(Date.UTC(value.getUTCFullYear(), 0, 1));
        return Math.ceil((((value - yearStart) / 8.64e+07) + 1) / 7);
    }

    function yearProgress() {
        var start = new Date(now.getFullYear(), 0, 1);
        var end = new Date(now.getFullYear() + 1, 0, 1);
        return Math.max(0, Math.min(100, (now - start) / (end - start) * 100));
    }

    function scheduleHoverClose() {
        if (!popupPinned)
            hoverCloseDelay.restart();

    }

    theme: bar.theme

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Timer {
        id: hoverDelay

        interval: 350
        onTriggered: {
            if (!button.tooltipHovered || root.popupPinned || root.hoverSuppressed || root.popupOpen)
                return ;

            if (root.bar.activePopup && root.bar.activePopup !== root)
                return ;

            root.goToToday();
            root.hoverOpen = true;
            root.popupOpen = true;
        }
    }

    Timer {
        id: hoverCloseDelay

        interval: 180
        onTriggered: {
            if (root.popupPinned || button.tooltipHovered || calendarPopup.containsMouse)
                return ;

            root.hoverOpen = false;
            root.popupOpen = false;
        }
    }

    ModuleButton {
        id: button

        bar: root.bar
        theme: root.theme
        text: Qt.formatDateTime(root.now, "MMM d · h:mm AP")
        // The rich calendar below replaces the old plain-text tooltip.
        tooltip: ""
        foreground: root.monochrome ? root.theme.text : root.theme.lavender
        horizontalPadding: 2
        acceptedButtons: Qt.LeftButton
        onTooltipHoveredChanged: {
            if (tooltipHovered) {
                hoverCloseDelay.stop();
                if (!root.popupPinned && !root.hoverSuppressed && !root.popupOpen)
                    hoverDelay.restart();

            } else {
                hoverDelay.stop();
                root.hoverSuppressed = false;
                root.scheduleHoverClose();
            }
        }
        onClicked: function(button) {
            if (button !== Qt.LeftButton)
                return ;

            if (root.popupPinned) {
                root.closePopup();
                root.hoverSuppressed = true;
                return ;
            }
            if (!root.popupOpen)
                root.goToToday();

            root.hoverOpen = false;
            root.popupPinned = true;
            root.popupOpen = true;
        }
    }

    PopupCard {
        id: calendarPopup

        anchorItem: button
        bar: root.bar
        owner: root
        open: root.popupOpen
        triggerMode: root.popupPinned ? "click" : "hover"
        onContainsMouseChanged: {
            if (containsMouse)
                hoverCloseDelay.stop();
            else if (!button.tooltipHovered)
                root.scheduleHoverClose();
        }
        onOpenChanged: root.popupOpen = open
        cardWidth: 420
        cardHeight: 410

        Column {
            width: parent.width
            spacing: 10

            Column {
                width: parent.width
                spacing: 2

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(root.now, "dddd")
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(root.now, "d MMMM yyyy") + "  ·  Week " + root.isoWeek(root.now)
                    color: root.theme.subtext
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                }

            }

            Column {
                width: parent.width
                spacing: 5

                Row {
                    width: parent.width

                    Text {
                        text: String(root.now.getFullYear())
                        color: root.theme.subtext
                        font.family: root.theme.fontFamily
                        font.pixelSize: 11
                    }

                    Item {
                        width: Math.max(0, parent.width - parent.children[0].width - yearPercent.width)
                        height: 1
                    }

                    Text {
                        id: yearPercent

                        text: Math.floor(root.yearProgress()) + "% of year"
                        color: root.theme.subtext
                        font.family: root.theme.fontFamily
                        font.pixelSize: 11
                    }

                }

                Rectangle {
                    width: parent.width
                    height: 5
                    radius: 3
                    color: root.theme.base

                    Rectangle {
                        width: parent.width * root.yearProgress() / 100
                        height: parent.height
                        radius: parent.radius
                        color: root.theme.mauve
                    }

                }

            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.theme.surface1
            }

            Row {
                width: parent.width

                MonthButton {
                    label: "󰅁"
                    accessibleName: "Previous month"
                    onActivated: root.moveMonth(-1)
                }

                Text {
                    width: parent.width - 72
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                    color: root.theme.peach
                    font.family: root.theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                }

                MonthButton {
                    label: "󰅂"
                    accessibleName: "Next month"
                    onActivated: root.moveMonth(1)
                }

            }

            Grid {
                id: weekdayHeader

                width: parent.width
                columns: 8
                columnSpacing: 2

                Repeater {
                    model: ["Wk", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

                    Text {
                        required property int index
                        required property string modelData

                        width: index === 0 ? 28 : (weekdayHeader.width - 42) / 7
                        height: 20
                        text: modelData
                        horizontalAlignment: Text.AlignHCenter
                        color: index === 0 ? root.theme.overlay : root.theme.subtext
                        font.family: root.theme.fontFamily
                        font.pixelSize: 10
                        font.bold: index > 0
                    }

                }

            }

            Grid {
                id: calendarGrid

                width: parent.width
                columns: 8
                columnSpacing: 2
                rowSpacing: 2

                Repeater {
                    model: 48

                    Rectangle {
                        required property int index
                        readonly property int weekRow: Math.floor(index / 8)
                        readonly property int weekColumn: index % 8
                        readonly property bool weekCell: weekColumn === 0
                        readonly property date day: root.cellDate(weekRow * 7 + weekColumn - 1)

                        width: weekCell ? 28 : (calendarGrid.width - 42) / 7
                        height: 34
                        radius: 8
                        color: !weekCell && root.isToday(day) ? root.theme.blue : "transparent"
                        border.width: !weekCell && day.getMonth() === root.viewMonth && !root.isToday(day) ? 1 : 0
                        border.color: root.theme.surface1

                        Text {
                            anchors.centerIn: parent
                            text: parent.weekCell ? root.isoWeek(root.cellDate(parent.weekRow * 7)) : parent.day.getDate()
                            color: parent.weekCell ? root.theme.overlay : root.isToday(parent.day) ? root.theme.base : parent.day.getMonth() === root.viewMonth ? root.theme.text : root.theme.overlay
                            font.family: root.theme.fontFamily
                            font.pixelSize: parent.weekCell ? 10 : 13
                            font.bold: !parent.weekCell && root.isToday(parent.day)
                        }

                    }

                }

            }

        }

    }

    component MonthButton: Rectangle {
        required property string label
        required property string accessibleName

        signal activated()

        width: 36
        height: 26
        radius: 8
        color: monthMouse.containsMouse ? root.theme.surface1 : "transparent"
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Accessible.onPressAction: activated()
        border.width: activeFocus ? 2 : 0
        border.color: root.theme.lavender
        Keys.onEnterPressed: activated()
        Keys.onReturnPressed: activated()
        Keys.onSpacePressed: activated()

        Text {
            anchors.centerIn: parent
            text: label
            color: root.theme.text
            font.family: root.theme.fontFamily
        }

        MouseArea {
            id: monthMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }

    }

}
