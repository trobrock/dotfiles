import "../components"
import QtQuick

Pill {
    id: root

    required property var bar
    property bool compact: false
    property bool monochrome: false
    readonly property var sink: bar.services.audioSink
    readonly property bool available: !!(sink && sink.audio)
    readonly property real volume: available ? sink.audio.volume : 0
    readonly property bool muted: available ? sink.audio.muted : true
    readonly property string sinkName: sink ? String(sink.name || "").toLowerCase() : ""
    readonly property bool bluetooth: sinkName.indexOf("bluez") !== -1
    readonly property bool headphones: sinkName.indexOf("headphone") !== -1 || sinkName.indexOf("headset") !== -1
    property bool popupOpen: false
    property real wheelRemainder: 0

    function icon() {
        if (!available || muted || volume <= 0)
            return "";

        if (headphones)
            return "";

        if (volume >= 0.67)
            return "";

        if (volume >= 0.34)
            return "";

        return "";
    }

    function setVolume(value) {
        if (available)
            sink.audio.volume = Math.max(0, Math.min(1, value));

    }

    function toggleMute() {
        if (available)
            sink.audio.muted = !sink.audio.muted;

    }

    function closePopup() {
        popupOpen = false;
    }

    theme: bar.theme

    ModuleButton {
        id: button

        bar: root.bar
        theme: root.theme
        text: (root.compact ? root.icon() : (root.muted ? root.icon() : Math.round(root.volume * 100) + "% " + root.icon())) + (root.bluetooth ? " " : "")
        tooltip: root.available ? (root.muted ? "Audio muted" : "Volume " + Math.round(root.volume * 100) + "%") + "\nRight click to mute · scroll to adjust" : "No PipeWire output"
        foreground: root.muted ? root.theme.overlay : root.monochrome ? root.theme.subtext : root.theme.pink
        horizontalPadding: 2
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        wheelable: true
        onClicked: function(button) {
            if (button === Qt.RightButton)
                root.toggleMute();
            else if (button === Qt.LeftButton)
                root.popupOpen = !root.popupOpen;
        }
        onWheel: function(delta) {
            root.wheelRemainder += delta;
            var steps = root.wheelRemainder > 0 ? Math.floor(root.wheelRemainder / 120) : Math.ceil(root.wheelRemainder / 120);
            if (steps === 0)
                return ;

            root.wheelRemainder -= steps * 120;
            root.setVolume(root.volume + steps * 0.05);
        }
    }

    PopupCard {
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.popupOpen
        onOpenChanged: root.popupOpen = open
        cardWidth: 320
        cardHeight: 140

        Column {
            width: parent.width
            spacing: 15

            Text {
                text: "Audio  " + (root.available ? Math.round(root.volume * 100) + "%" : "unavailable")
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 17
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: 9
                radius: 5
                color: root.theme.base
                activeFocusOnTab: true
                Accessible.role: Accessible.Slider
                Accessible.name: "Output volume"
                border.width: activeFocus ? 2 : 0
                border.color: root.theme.lavender
                Keys.onLeftPressed: root.setVolume(root.volume - 0.05)
                Keys.onRightPressed: root.setVolume(root.volume + 0.05)

                Rectangle {
                    width: parent.width * Math.min(1, root.volume)
                    height: parent.height
                    radius: parent.radius
                    color: root.muted ? root.theme.overlay : root.theme.pink
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: function(event) {
                        root.setVolume(event.x / width);
                    }
                    onPositionChanged: function(event) {
                        if (pressed)
                            root.setVolume(event.x / width);

                    }
                }

            }

            Row {
                spacing: 10

                PopupButton {
                    label: root.muted ? "󰝟 Unmute" : "󰝟 Mute"
                    onActivated: root.toggleMute()
                }

                PopupButton {
                    label: "󰓃 pavucontrol"
                    onActivated: root.bar.services.openPavucontrol()
                }

            }

        }

    }

    component PopupButton: Rectangle {
        required property string label

        signal activated()

        width: popupText.implicitWidth + 20
        height: 30
        radius: 8
        color: popupMouse.containsMouse ? root.theme.surface1 : root.theme.base
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        border.width: activeFocus ? 2 : 0
        border.color: root.theme.lavender
        Keys.onEnterPressed: activated()
        Keys.onReturnPressed: activated()
        Keys.onSpacePressed: activated()

        Text {
            id: popupText

            anchors.centerIn: parent
            text: label
            color: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: 13
        }

        MouseArea {
            id: popupMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }

    }

}
