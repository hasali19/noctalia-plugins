import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root
    property var pluginApi: null

    readonly property var cfg: pluginApi?.pluginSettings ?? ({})
    readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})

    // Array of { path, battery, charging, connected }
    property var devices: []

    readonly property string _scriptPath: Qt.resolvedUrl("./get_devices.py").toString().replace("file://", "")

    // Monitor fang DBus signals via gdbus. Outputs one line per signal:
    //   /path: com.Interface.Signal (args,)
    Process {
        id: monitorProcess
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "dev.hasali.Fang"]

        onRunningChanged: {
            if (!running) {
                root.devices = []
                monitorRestartTimer.restart()
            }
        }

        stdout: SplitParser {
            onRead: line => root.handleSignal(line)
        }

        stderr: StdioCollector {}
    }

    // Restart monitor after fang stops and possibly restarts
    Timer {
        id: monitorRestartTimer
        interval: 5000
        repeat: false
        onTriggered: {
            monitorProcess.running = true
            root.poll()
        }
    }

    // Periodic polling fallback — catches state drift between signals
    Timer {
        interval: (cfg.pollInterval ?? defaults.pollInterval ?? 30) * 1000
        running: true
        repeat: true
        onTriggered: root.poll()
    }

    // One-shot process to fetch device states from DBus via the helper script
    Process {
        id: fetchProcess
        running: false
        command: ["python3", root._scriptPath]

        stdout: StdioCollector {
            id: fetchCollector
        }

        stderr: StdioCollector {}

        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) {
                root.devices = []
                return
            }
            try {
                var data = JSON.parse(fetchCollector.text)
                if (Array.isArray(data.devices)) {
                    root.devices = data.devices
                    Logger.d("Fang", "Updated", data.devices.length, "device(s)")
                }
            } catch(e) {
                Logger.e("Fang", "JSON parse error:", e.message)
            }
        }
    }

    // Debounce rapid back-to-back signals before triggering a refresh
    Timer {
        id: refreshDebounce
        interval: 500
        repeat: false
        onTriggered: root.poll()
    }

    function handleSignal(line) {
        var trimmed = line.trim()
        if (!trimmed) return

        // gdbus monitor line format: "{path}: {iface}.{member} ({args},)"
        var colonIdx = trimmed.indexOf(': ')
        if (colonIdx < 0) return

        var sigPath = trimmed.substring(0, colonIdx)
        var rest = trimmed.substring(colonIdx + 2)

        var parenIdx = rest.lastIndexOf(' (')
        if (parenIdx < 0) return

        var fullName = rest.substring(0, parenIdx)
        var argsStr = rest.substring(parenIdx + 2, rest.length - 1)

        var lastDot = fullName.lastIndexOf('.')
        if (lastDot < 0) return

        var iface = fullName.substring(0, lastDot)
        var member = fullName.substring(lastDot + 1)

        // Remove the device immediately on DeviceRemoved without waiting for the poll
        if (iface === "dev.hasali.Fang.DeviceManager" && member === "DeviceRemoved") {
            var removedPath = extractFirstStringArg(argsStr)
            if (removedPath) {
                root.devices = root.devices.filter(d => d.path !== removedPath)
                Logger.d("Fang", "Device removed:", removedPath)
            }
        }

        refreshDebounce.restart()
    }

    function extractFirstStringArg(argsStr) {
        // Handles "'value'" or "'value'," (gdbus uses single-quoted strings/object paths)
        if (!argsStr.startsWith("'")) return null
        var endQ = argsStr.indexOf("'", 1)
        return endQ > 0 ? argsStr.substring(1, endQ) : null
    }

    function poll() {
        if (!fetchProcess.running)
            fetchProcess.running = true
    }

    Component.onCompleted: Qt.callLater(root.poll)

    IpcHandler {
        target: "plugin:fang"

        function refresh() {
            root.poll()
        }
    }
}
