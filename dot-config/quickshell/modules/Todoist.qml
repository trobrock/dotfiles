import QtQuick
import "../components"

Pill {
    id: root

    required property var bar
    readonly property var service: bar.todoistService
    readonly property string displayError: service.actionError !== "" ? service.actionError : service.error
    property bool popupOpen: false

    function closePopup() {
        popupOpen = false;
    }

    function summaryText() {
        return String(service.count);
    }

    function buttonText() {
        var summary = summaryText();
        return "" + (summary === "" ? "" : " " + summary);
    }

    theme: bar.theme

    ModuleButton {
        id: button

        bar: root.bar
        theme: root.theme
        text: root.buttonText()
        tooltip: root.displayError !== "" ? root.displayError : root.service.count === 1 ? "1 Todoist task due" : root.service.count + " Todoist tasks due"
        foreground: root.displayError !== "" && !root.service.stale ? root.theme.red : root.service.count > 0 ? root.theme.blue : root.theme.subtext
        horizontalPadding: 1
        onClicked: function(mouseButton) {
            if (mouseButton === Qt.LeftButton) {
                root.popupOpen = !root.popupOpen;
                if (root.popupOpen)
                    root.service.refresh();
            }
        }
    }

    PopupCard {
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.popupOpen
        onOpenChanged: root.popupOpen = open
        cardWidth: 400
        cardHeight: Math.min(430, 126 + Math.max(1, Math.min(8, root.service.tasks.length)) * 48)
        padding: 14

        Column {
            width: parent.width
            spacing: 10

            Row {
                width: parent.width
                spacing: 8

                Text {
                    width: parent.width - openButton.width - refreshButton.width - parent.spacing * 2
                    text: "Todoist · Today"
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 17
                    font.bold: true
                    elide: Text.ElideRight
                }

                HeaderButton {
                    id: refreshButton
                    label: root.service.refreshing ? "󰑐" : "󰑐"
                    accessibleLabel: "Refresh Todoist"
                    onActivated: root.service.refresh()
                }

                HeaderButton {
                    id: openButton
                    label: "󰏌"
                    accessibleLabel: "Open Todoist"
                    onActivated: root.service.openUrl("https://app.todoist.com/app/today")
                }
            }

            Text {
                visible: root.displayError !== ""
                width: parent.width
                text: (root.service.stale ? "Showing saved tasks · " : "") + root.displayError
                textFormat: Text.PlainText
                color: root.theme.red
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Text {
                visible: root.displayError === "" && root.service.tasks.length === 0
                width: parent.width
                text: root.service.refreshing ? "Loading tasks…" : "Nothing due today."
                color: root.theme.subtext
                font.family: root.theme.fontFamily
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                topPadding: 18
            }

            Repeater {
                model: root.service.tasks.slice(0, 8)

                delegate: Rectangle {
                    required property var modelData

                    width: parent.width
                    height: 40
                    radius: 8
                    color: taskMouse.containsMouse ? root.theme.surface1 : root.theme.base

                    MouseArea {
                        id: taskMouse

                        anchors.left: parent.left
                        anchors.right: completeButton.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.service.openUrl(String(parent.modelData.url || ""))
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: completeButton.left
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: String(modelData.content || "Untitled task")
                            textFormat: Text.PlainText
                            color: root.theme.text
                            font.family: root.theme.fontFamily
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: String(modelData.due || "Due today")
                            textFormat: Text.PlainText
                            color: root.theme.subtext
                            font.family: root.theme.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: completeButton

                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        radius: 7
                        color: completeMouse.containsMouse ? root.theme.green : "transparent"
                        border.width: 1
                        border.color: root.theme.green
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: "Complete " + String(modelData.content || "task")
                        Keys.onEnterPressed: root.service.completeTask(String(modelData.id || ""))
                        Keys.onReturnPressed: root.service.completeTask(String(modelData.id || ""))
                        Keys.onSpacePressed: root.service.completeTask(String(modelData.id || ""))

                        Text {
                            anchors.centerIn: parent
                            text: root.service.completingTaskId === String(modelData.id || "") ? "…" : "✓"
                            color: completeMouse.containsMouse ? root.theme.base : root.theme.green
                            font.family: root.theme.fontFamily
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: completeMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.service.completeTask(String(modelData.id || ""))
                        }
                    }
                }
            }

            Text {
                visible: root.service.tasks.length > 8
                width: parent.width
                text: "+ " + (root.service.tasks.length - 8) + " more in Todoist"
                color: root.theme.subtext
                font.family: root.theme.fontFamily
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    component HeaderButton: Rectangle {
        required property string label
        required property string accessibleLabel
        signal activated()

        width: 30
        height: 26
        radius: 7
        color: headerMouse.containsMouse ? root.theme.surface1 : root.theme.base
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: accessibleLabel
        Keys.onEnterPressed: activated()
        Keys.onReturnPressed: activated()
        Keys.onSpacePressed: activated()

        Text {
            anchors.centerIn: parent
            text: label
            color: root.theme.subtext
            font.family: root.theme.fontFamily
            font.pixelSize: 13
        }

        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }
}
