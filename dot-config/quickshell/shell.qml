import QtQuick
import Quickshell

ShellRoot {
    id: shell
    property Theme theme: Theme {}
    property Services services: Services {}
    property NotificationService notifications: NotificationService {}
    property WifiService wifiService: WifiService {}

    Bar {
        theme: shell.theme
        services: shell.services
        osd: osd
        bluetoothMenu: bluetoothMenu
        wifiMenu: wifiMenu
    }

    Launcher {
        theme: shell.theme
    }

    PowerMenu {
        theme: shell.theme
    }

    BluetoothMenu {
        id: bluetoothMenu

        theme: shell.theme
    }

    WifiMenu {
        id: wifiMenu

        theme: shell.theme
        service: shell.wifiService
    }

    NotificationToasts {
        service: shell.notifications
        theme: shell.theme
    }


    Osd {
        id: osd

        theme: shell.theme
        services: shell.services
        notificationService: shell.notifications
    }
}
