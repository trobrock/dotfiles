import QtQuick
import Quickshell

ShellRoot {
    id: shell
    property Theme theme: Theme {}
    property Services services: Services {}
    property NotificationService notifications: NotificationService {}

    Bar {
        theme: shell.theme
        services: shell.services
        osd: osd
    }

    Launcher {
        theme: shell.theme
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
