pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Rectangle {
    id: root

    required property var service
    required property var entry
    required property var theme
    property bool compact: true
    readonly property var actionEntries: {
        var result = [];
        var actions = entry && entry.actions ? entry.actions : [];
        for (var i = 0; i < actions.length && result.length < 2; ++i) {
            if (actions[i].identifier !== "default")
                result.push(actions[i]);
        }
        return result;
    }
    readonly property bool hasBody: entry && String(entry.body || "").trim() !== ""
    readonly property bool hasActions: actionEntries.length > 0
    readonly property bool hasDefaultAction: entry && entry.hasDefaultAction === true
    readonly property color accent: Number(entry.urgency) === 2 ? theme.red : theme.lavender

    function safeIconSource() {
        var name = String(entry && entry.icon || "").slice(0, 160);
        if (!/^[A-Za-z0-9._+-]+$/.test(name))
            return "";
        return Quickshell.iconPath(name, true);
    }

    implicitWidth: 420
    implicitHeight: Math.max(68, Math.ceil(10 + appName.contentHeight + 2 + summary.contentHeight + (hasBody ? 5 + body.contentHeight : 0) + (hasActions ? 38 : 10)))
    radius: 10
    color: theme.base
    border.width: 2
    border.color: accent
    clip: true
    activeFocusOnTab: hasDefaultAction
    Accessible.role: hasDefaultAction ? Accessible.Button : Accessible.Pane
    Accessible.name: String(entry.appName || "Application") + ": " + String(entry.summary || "Notification")
    Keys.onPressed: function(event) {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && root.hasDefaultAction) {
            root.service.invokeDefault(root.entry.id);
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            root.service.dismissEntry(root.entry.id);
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.hasDefaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: function(event) {
            if (event.button === Qt.RightButton)
                root.service.dismissEntry(root.entry.id);
            else if (root.hasDefaultAction)
                root.service.invokeDefault(root.entry.id);
        }
    }

    Item {
        id: iconFrame

        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.top: parent.top
        anchors.topMargin: 13
        width: 32
        height: 32

        Image {
            id: appIcon

            anchors.fill: parent
            source: root.safeIconSource()
            sourceSize.width: 64
            sourceSize.height: 64
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
        }

        Text {
            anchors.fill: parent
            visible: String(appIcon.source) === "" || appIcon.status === Image.Error
            text: Number(root.entry.urgency) === 2 ? "" : ""
            textFormat: Text.PlainText
            color: root.accent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: root.theme.fontFamily
            font.pixelSize: 18
        }
    }

    Text {
        id: appName

        anchors.left: iconFrame.right
        anchors.leftMargin: 12
        anchors.right: closeButton.left
        anchors.rightMargin: 8
        anchors.top: parent.top
        anchors.topMargin: 10
        text: String(root.entry.appName || "Application").slice(0, 80)
        textFormat: Text.PlainText
        color: root.theme.subtext
        elide: Text.ElideRight
        font.family: root.theme.fontFamily
        font.pixelSize: 10
    }

    Text {
        id: summary

        anchors.left: appName.left
        anchors.right: closeButton.left
        anchors.rightMargin: 8
        anchors.top: appName.bottom
        anchors.topMargin: 2
        text: String(root.entry.summary || "Notification").slice(0, 180)
        textFormat: Text.PlainText
        color: root.theme.text
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.family: root.theme.fontFamily
        font.pixelSize: 14
        font.bold: true
    }

    Text {
        id: body

        anchors.left: appName.left
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.top: summary.bottom
        anchors.topMargin: 5
        visible: root.hasBody
        text: String(root.entry.body || "").slice(0, 1000)
        textFormat: Text.PlainText
        color: root.theme.subtext
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 2
        elide: Text.ElideRight
        font.family: root.theme.fontFamily
        font.pixelSize: 11
    }

    Rectangle {
        id: closeButton

        anchors.top: parent.top
        anchors.topMargin: 9
        anchors.right: parent.right
        anchors.rightMargin: 9
        width: 25
        height: 25
        radius: 7
        color: closeHover.hovered ? root.theme.surface1 : "transparent"
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: "Dismiss notification"
        Keys.onEnterPressed: root.service.dismissEntry(root.entry.id)
        Keys.onReturnPressed: root.service.dismissEntry(root.entry.id)
        Keys.onSpacePressed: root.service.dismissEntry(root.entry.id)

        Text {
            anchors.centerIn: parent
            text: "×"
            textFormat: Text.PlainText
            color: root.theme.subtext
            font.family: root.theme.fontFamily
            font.pixelSize: 17
        }

        HoverHandler {
            id: closeHover
        }

        TapHandler {
            onTapped: root.service.dismissEntry(root.entry.id)
        }
    }

    Row {
        anchors.left: appName.left
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        spacing: 8
        visible: root.hasActions

        Repeater {
            model: root.actionEntries

            delegate: Rectangle {
                id: actionButton

                required property var modelData

                width: Math.min(112, actionLabel.implicitWidth + 22)
                height: 28
                radius: 7
                color: actionHover.hovered ? root.theme.surface1 : root.theme.surfaceSolid
                border.width: activeFocus ? 2 : 1
                border.color: activeFocus ? root.theme.lavender : root.theme.surface1
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: String(modelData.text || "Action")
                Keys.onEnterPressed: root.service.invokeNamedAction(root.entry.id, modelData.identifier)
                Keys.onReturnPressed: root.service.invokeNamedAction(root.entry.id, modelData.identifier)
                Keys.onSpacePressed: root.service.invokeNamedAction(root.entry.id, modelData.identifier)

                Text {
                    id: actionLabel

                    anchors.centerIn: parent
                    width: Math.min(90, implicitWidth)
                    text: String(actionButton.modelData.text || "Action").slice(0, 80)
                    textFormat: Text.PlainText
                    color: root.theme.text
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root.theme.fontFamily
                    font.pixelSize: 10
                }

                HoverHandler {
                    id: actionHover
                }

                TapHandler {
                    onTapped: root.service.invokeNamedAction(root.entry.id, actionButton.modelData.identifier)
                }
            }
        }
    }
}
