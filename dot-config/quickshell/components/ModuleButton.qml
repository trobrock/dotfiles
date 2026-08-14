import QtQuick

Item {
    id: root

    property var bar
    property var theme
    property string text: ""
    property url iconSource: ""
    property real iconSize: 16
    property string tooltip: ""
    property color foreground: theme ? theme.text : "white"
    property color background: "transparent"
    property color indicatorColor: "transparent"
    property real indicatorWidth: 12
    property real indicatorHeight: 2
    property int horizontalPadding: 8
    property bool highlighted: false
    property bool actionable: true
    property bool wheelable: false
    property int acceptedButtons: Qt.LeftButton
    property real maxTextWidth: Number.POSITIVE_INFINITY
    readonly property bool tooltipHovered: mouse.containsMouse

    signal clicked(int button)
    signal wheel(int delta)

    function dismissTransientUi() {
        if (!bar)
            return ;

        bar.clearTooltip(root);
        var owner = bar.activePopup;
        if (!owner || typeof owner.closePopup !== "function")
            return ;

        // Popup owners are module ancestors of their primary ModuleButton.
        // Closing here prevents a responsive parent disappearing while its
        // detached PopupWindow remains on screen.
        var ancestor = root.parent;
        while (ancestor) {
            if (ancestor === owner) {
                owner.closePopup();
                return ;
            }
            ancestor = ancestor.parent;
        }
    }

    implicitWidth: Math.max(0, buttonContent.implicitWidth + horizontalPadding * 2)
    implicitHeight: 25
    activeFocusOnTab: actionable
    onVisibleChanged: {
        if (!visible)
            dismissTransientUi();

    }
    Component.onDestruction: {
        if (bar)
            bar.clearTooltip(root);

    }
    Accessible.role: actionable ? Accessible.Button : Accessible.StaticText
    Accessible.name: tooltip || text
    Keys.onEnterPressed: {
        if (root.actionable)
            root.clicked(Qt.LeftButton);

    }
    Keys.onReturnPressed: {
        if (root.actionable)
            root.clicked(Qt.LeftButton);

    }
    Keys.onSpacePressed: {
        if (root.actionable)
            root.clicked(Qt.LeftButton);

    }

    Rectangle {
        anchors.fill: parent
        radius: theme ? Math.max(2, theme.radius - 2) : 8
        color: root.background.a > 0 ? root.background : root.highlighted ? (theme ? theme.surface1 : "#45475a") : "transparent"
        border.width: root.activeFocus ? 2 : 0
        border.color: theme ? theme.lavender : "white"
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: root.indicatorWidth
        height: root.indicatorHeight
        radius: height / 2
        color: root.indicatorColor
        visible: color.a > 0
    }

    Row {
        id: buttonContent

        anchors.centerIn: parent
        spacing: providerIcon.visible && label.visible ? 5 : 0

        Image {
            id: providerIcon

            anchors.verticalCenter: parent.verticalCenter
            visible: String(root.iconSource) !== ""
            width: visible ? root.iconSize : 0
            height: visible ? root.iconSize : 0
            source: root.iconSource
            sourceSize.width: Math.ceil(root.iconSize * 2)
            sourceSize.height: Math.ceil(root.iconSize * 2)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Text {
            id: label

            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""
            width: visible ? Math.min(labelMeasure.implicitWidth, root.maxTextWidth) : 0
            text: root.text
            textFormat: Text.PlainText
            color: root.foreground
            font.family: theme ? theme.fontFamily : "monospace"
            font.pixelSize: theme ? theme.fontSize : 14
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    Text {
        id: labelMeasure

        visible: false
        text: root.text
        font.family: theme ? theme.fontFamily : "monospace"
        font.pixelSize: theme ? theme.fontSize : 14
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: root.actionable ? root.acceptedButtons : Qt.NoButton
        cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: {
            if (root.bar && root.tooltip)
                root.bar.requestTooltip(root, root.tooltip);

        }
        onExited: {
            if (root.bar)
                root.bar.clearTooltip(root);

        }
        onClicked: function(event) {
            if (root.actionable)
                root.clicked(event.button);

        }
        onWheel: function(event) {
            if (root.wheelable)
                root.wheel(event.angleDelta.y);

        }
    }

}
