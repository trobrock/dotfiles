import QtQuick
import Quickshell

ShellRoot {
    id: shell
    property Theme theme: Theme {}
    property Services services: Services {}
    property NotificationService notifications: NotificationService {}
    property WifiService wifiService: WifiService {}
    property TailscaleService tailscaleService: TailscaleService {}

    Bar {
        theme: shell.theme
        services: shell.services
        osd: osd
        bluetoothMenu: bluetoothMenu
        wifiMenu: wifiMenu
        tailscaleMenu: tailscaleMenu
        tailscaleService: shell.tailscaleService
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

    TailscaleMenu {
        id: tailscaleMenu

        theme: shell.theme
        service: shell.tailscaleService
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
