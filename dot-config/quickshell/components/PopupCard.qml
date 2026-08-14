import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: root

    required property Item anchorItem
    required property var bar
    required property var owner
    property bool open: false
    property int cardWidth: 360
    property int cardHeight: 240
    property int padding: 18
    // Click popups grab focus and close on outside click. Hover popups stay
    // passive so the pointer can move between their trigger and content.
    property string triggerMode: "click"
    readonly property bool containsMouse: popupHover.hovered
    default property alias content: contentHolder.data
    readonly property var anchorWindow: anchorItem && anchorItem.QsWindow ? anchorItem.QsWindow.window : null
    readonly property real screenWidth: anchorWindow && anchorWindow.screen ? anchorWindow.screen.width : cardWidth
    readonly property real screenHeight: anchorWindow && anchorWindow.screen ? anchorWindow.screen.height : cardHeight

    function close() {
        if (root.owner && typeof root.owner.closePopup === "function")
            root.owner.closePopup();
        else
            root.open = false;
    }

    function scrollToTop() {
        if (!scroller)
            return ;

        scroller.cancelFlick();
        scroller.contentY = scroller.originY;
    }

    visible: open
    color: "transparent"
    implicitWidth: Math.max(180, Math.min(cardWidth, screenWidth - 24))
    implicitHeight: Math.max(100, Math.min(cardHeight, screenHeight - 60))
    onOpenChanged: {
        if (open)
            bar.claimPopup(owner);
        else
            bar.releasePopup(owner);
    }

    HyprlandFocusGrab {
        active: root.open && root.triggerMode === "click"
        windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
        onCleared: root.close()
    }

    anchor {
        id: popupAnchor

        window: root.anchorWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1
        onAnchoring: {
            if (!root.anchorWindow || !root.anchorItem)
                return ;

            var x = root.anchorItem.width / 2 - root.implicitWidth / 2;
            var y = root.bar.testMode ? -root.implicitHeight - 8 : root.anchorItem.height + 8;
            var point = root.anchorWindow.contentItem.mapFromItem(root.anchorItem, x, y);
            point.x = Math.max(8, Math.min(point.x, root.anchorWindow.width - root.implicitWidth - 8));
            popupAnchor.rect.x = Math.round(point.x);
            popupAnchor.rect.y = Math.round(point.y);
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.bar.theme.radius + 2
        color: root.bar.theme.surfaceSolid
        border.width: 1
        border.color: root.bar.theme.surface1
        clip: true

        HoverHandler {
            id: popupHover
        }

        Flickable {
            id: scroller

            anchors.fill: parent
            anchors.margins: root.padding
            clip: true
            contentWidth: width
            contentHeight: Math.max(height, contentHolder.childrenRect.height)
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Item {
                id: contentHolder

                width: scroller.width
                height: childrenRect.height
            }

        }

        Item {
            anchors.fill: parent
            focus: root.open
            Keys.onEscapePressed: root.close()
        }

        Shortcut {
            sequence: "Escape"
            enabled: root.open
            context: Qt.WindowShortcut
            onActivated: root.close()
        }

    }

}
