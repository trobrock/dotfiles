pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

Item {
    id: root

    required property var service
    required property var theme

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: toastWindow

                required property var modelData
                readonly property var entries: {
                    root.service.revision;
                    return root.service.toastEntries(modelData.name);
                }

                screen: modelData
                visible: entries.length > 0
                color: "transparent"
                implicitWidth: Math.max(1, Math.min(420, modelData.width - 28))
                implicitHeight: Math.max(1, toastStack.implicitHeight)
                exclusionMode: ExclusionMode.Ignore
                focusable: false
                surfaceFormat.opaque: false
                WlrLayershell.namespace: "quickshell-notification-toasts"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors {
                    top: true
                    right: true
                }

                margins.top: 44
                margins.right: 14

                Column {
                    id: toastStack

                    width: toastWindow.implicitWidth
                    spacing: 8

                    Repeater {
                        model: toastWindow.entries

                        delegate: NotificationCard {
                            required property var modelData

                            width: toastStack.width
                            service: root.service
                            entry: modelData
                            theme: root.theme
                            compact: true
                        }
                    }
                }
            }
        }
    }
}
