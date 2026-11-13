import QtQuick
import Quickshell
import Quickshell.Io

// One shared Todoist model feeds every monitor's bar.
Item {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.config/scripts/todoist-bar"
    property var tasks: []
    property int count: 0
    property bool refreshing: false
    property bool refreshQueued: false
    property bool fetchResponseApplied: false
    property bool fetchProcessExited: false
    property bool fetchStreamFinished: false
    property bool stale: false
    property string error: "Waiting for Todoist"
    property string actionError: ""
    property string completingTaskId: ""

    function applyTasks(text) {
        var raw = String(text || "").trim();
        if (raw !== "") {
            try {
                var data = JSON.parse(raw);
                if (!Array.isArray(data.tasks))
                    throw new Error("Missing task list");
                tasks = data.tasks;
                count = Number(data.count) || 0;
                stale = data.stale === true;
                error = String(data.error || "");
                fetchResponseApplied = true;
            } catch (parseError) {
                error = "Could not read Todoist data";
                stale = tasks.length > 0;
            }
        }
        fetchStreamFinished = true;
        if (fetchProcessExited)
            finishFetch();
    }

    function refresh() {
        if (refreshing) {
            refreshQueued = true;
            return;
        }
        refreshing = true;
        fetchResponseApplied = false;
        fetchProcessExited = false;
        fetchStreamFinished = false;
        fetchProcess.command = [helper, "fetch"];
        fetchProcess.running = true;
    }

    function completeTask(taskId) {
        var id = String(taskId || "");
        if (id === "" || completeProcess.running)
            return;
        actionError = "";
        completingTaskId = id;
        completeProcess.command = [helper, "complete", id];
        completeProcess.running = true;
    }

    function finishFetch() {
        fetchFinishTimer.stop();
        refreshing = false;
        if (!fetchResponseApplied) {
            error = "Todoist helper failed";
            stale = tasks.length > 0;
        }
        if (refreshQueued) {
            refreshQueued = false;
            refresh();
        }
    }

    function openUrl(url) {
        var target = String(url || "https://app.todoist.com/app/today");
        Quickshell.execDetached(["xdg-open", target]);
    }

    Process {
        id: fetchProcess

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyTasks(text)
        }

        onExited: function(code) {
            root.fetchProcessExited = true;
            if (root.fetchStreamFinished)
                root.finishFetch();
            else
                fetchFinishTimer.restart();
        }
    }

    Process {
        id: completeProcess

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var result = JSON.parse(String(text || "{}"));
                    if (result.ok === true)
                        root.actionError = "";
                    else
                        root.actionError = String(result.error || "Could not complete task");
                } catch (parseError) {
                    root.actionError = "Could not complete task";
                }
            }
        }

        onExited: function(code) {
            root.completingTaskId = "";
            root.refresh();
        }
    }

    Timer {
        id: fetchFinishTimer
        interval: 1000
        onTriggered: root.finishFetch()
    }

    Timer {
        interval: 300000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
