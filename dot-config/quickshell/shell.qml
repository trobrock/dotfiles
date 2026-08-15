import QtQuick
import Quickshell

ShellRoot {
    id: shell
    property Theme theme: Theme {}
    property Services services: Services {}

    Bar {
        theme: shell.theme
        services: shell.services
    }

    Launcher {
        theme: shell.theme
    }
}
