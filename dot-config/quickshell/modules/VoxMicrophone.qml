import "../components"
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    required property var bar
    property bool compact: false
    property bool monochrome: false
    property int iconSlotWidth: 28
    readonly property var services: bar.services
    readonly property string helper: services.configDir + "/scripts/voxtype-microphone"
    property bool popupOpen: false
    property bool loading: false
    property bool switching: false
    property string errorText: ""
    property string pendingSource: ""
    property string defaultSource: ""
    property string defaultDescription: ""
    property var microphones: []

    function closePopup() {
        popupOpen = false;
    }

    function refreshMicrophones() {
        if (listProcess.running)
            return;

        errorText = "";
        loading = true;
        listProcess.running = true;
    }

    function applyMicrophones(raw) {
        try {
            var parsed = JSON.parse(String(raw || ""));
            if (!Array.isArray(parsed))
                throw new Error("expected an array");

            var valid = [];
            var selectedName = "";
            var selectedDescription = "";
            for (var i = 0; i < parsed.length; ++i) {
                var entry = parsed[i];
                if (!entry || typeof entry.name !== "string" || entry.name === "")
                    continue;

                var description = typeof entry.description === "string" && entry.description !== "" ? entry.description : entry.name;
                var isDefault = entry.isDefault === true;
                valid.push({
                    "name": entry.name,
                    "description": description,
                    "isDefault": isDefault
                });
                if (isDefault) {
                    selectedName = entry.name;
                    selectedDescription = description;
                }
            }

            microphones = valid;
            defaultSource = selectedName;
            defaultDescription = selectedDescription;
            if (valid.length === 0)
                errorText = "No microphone inputs found";
        } catch (error) {
            microphones = [];
            errorText = "Could not read microphone inputs";
        }
    }

    function selectMicrophone(sourceName) {
        if (switching || sourceName === "" || sourceName === defaultSource)
            return;

        pendingSource = sourceName;
        errorText = "";
        switching = true;
        selectProcess.command = [root.helper, "--set", sourceName];
        selectProcess.running = true;
    }

    visible: services.voxText !== "" && !compact
    implicitWidth: visible ? iconSlotWidth : 0
    implicitHeight: button.implicitHeight

    Component.onCompleted: refreshMicrophones()

    Process {
        id: listProcess

        command: [root.helper]
        onExited: function(code) {
            root.loading = false;
            if (code !== 0)
                root.errorText = "Could not list microphone inputs";
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyMicrophones(text)
        }
    }

    Process {
        id: selectProcess

        onExited: function(code) {
            root.switching = false;
            if (code === 0) {
                root.defaultSource = root.pendingSource;
                for (var i = 0; i < root.microphones.length; ++i) {
                    if (root.microphones[i].name === root.pendingSource) {
                        root.defaultDescription = root.microphones[i].description;
                        break;
                    }
                }
                root.closePopup();
                root.refreshMicrophones();
            } else {
                root.errorText = "Could not switch microphone";
            }
            root.pendingSource = "";
        }
    }

    ModuleButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        theme: root.bar.theme
        horizontalPadding: 0
        text: String(root.services.voxText || "󰍭")
        foreground: root.services.voxAvailable ? (root.monochrome ? root.bar.theme.subtext : root.bar.theme.mauve) : root.bar.theme.red
        tooltip: String(root.services.voxTooltip || "VoxType")
            + (root.defaultDescription !== "" ? "\nMicrophone: " + root.defaultDescription : "")
            + "\nLeft click: choose microphone · Right click: restart"
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        actionable: true
        onClicked: function(button) {
            if (button === Qt.RightButton) {
                root.services.restartVox();
            } else if (button === Qt.LeftButton) {
                root.popupOpen = !root.popupOpen;
                if (root.popupOpen)
                    root.refreshMicrophones();
            }
        }
    }

    PopupCard {
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.popupOpen
        onOpenChanged: root.popupOpen = open
        cardWidth: 390
        cardHeight: Math.min(370, 92 + Math.max(1, root.microphones.length) * 50)
        padding: 14

        Column {
            width: parent.width
            spacing: 10

            Text {
                width: parent.width
                text: "VoxType microphone"
                color: root.bar.theme.text
                font.family: root.bar.theme.fontFamily
                font.pixelSize: 17
                font.bold: true
            }

            Text {
                visible: root.loading || root.errorText !== ""
                width: parent.width
                text: root.loading ? "Loading microphones…" : root.errorText
                color: root.errorText !== "" ? root.bar.theme.red : root.bar.theme.subtext
                font.family: root.bar.theme.fontFamily
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.microphones

                delegate: Rectangle {
                    id: microphoneRow

                    required property var modelData
                    readonly property bool selected: modelData.name === root.defaultSource
                    readonly property bool pending: modelData.name === root.pendingSource

                    width: parent.width
                    height: 42
                    radius: 8
                    color: rowMouse.containsMouse ? root.bar.theme.surface1 : selected ? root.bar.theme.surfaceSolid : root.bar.theme.base
                    border.width: selected ? 1 : 0
                    border.color: root.bar.theme.mauve
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Use " + modelData.description + " for VoxType"
                    Keys.onEnterPressed: root.selectMicrophone(modelData.name)
                    Keys.onReturnPressed: root.selectMicrophone(modelData.name)
                    Keys.onSpacePressed: root.selectMicrophone(modelData.name)

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Text {
                            width: 22
                            anchors.verticalCenter: parent.verticalCenter
                            text: microphoneRow.pending ? "󰔟" : microphoneRow.selected ? "󰄬" : "󰍬"
                            color: microphoneRow.selected ? root.bar.theme.green : root.bar.theme.subtext
                            font.family: root.bar.theme.fontFamily
                            font.pixelSize: 16
                        }

                        Text {
                            width: parent.width - 32
                            anchors.verticalCenter: parent.verticalCenter
                            text: microphoneRow.modelData.description
                            color: root.bar.theme.text
                            elide: Text.ElideRight
                            font.family: root.bar.theme.fontFamily
                            font.pixelSize: 13
                        }
                    }

                    MouseArea {
                        id: rowMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.switching
                        onClicked: root.selectMicrophone(microphoneRow.modelData.name)
                    }
                }
            }

            Text {
                width: parent.width
                text: "Sets the system default input used by VoxType on its next recording."
                color: root.bar.theme.overlay
                font.family: root.bar.theme.fontFamily
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }
}
