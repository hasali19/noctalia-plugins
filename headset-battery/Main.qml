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

    // Array of { name, batteryStatus, batteryLevel } for devices that report battery status.
    // batteryStatus: "BATTERY_AVAILABLE" | "BATTERY_CHARGING" | "BATTERY_UNAVAILABLE"
    // batteryLevel: 0-100, or -1 when charging and level is unknown
    property var devices: []

    Process {
        id: pollProcess
        running: false
        command: ["headsetcontrol", "-o", "json"]

        stdout: StdioCollector {
            id: stdoutCollector
        }

        stderr: StdioCollector {}

        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) {
                Logger.e("HeadsetBattery", "headsetcontrol exited with code:", exitCode)
                root.devices = []
                return
            }

            var output = stdoutCollector.text
            if (output.length === 0) {
                root.devices = []
                return
            }

            try {
                var data = JSON.parse(output)
                var result = []

                for (var i = 0; i < data.devices.length; i++) {
                    var dev = data.devices[i]
                    if (dev.status === "success" && dev.battery) {
                        result.push({
                            name: dev.device,
                            batteryStatus: dev.battery.status,
                            batteryLevel: dev.battery.level
                        })
                    }
                }

                root.devices = result
                Logger.d("HeadsetBattery", "Polled", result.length, "device(s)")
            } catch (e) {
                Logger.e("HeadsetBattery", "JSON parse error:", e.message)
                root.devices = []
            }
        }
    }

    Timer {
        interval: (cfg.pollInterval ?? defaults.pollInterval ?? 30) * 1000
        running: true
        repeat: true
        onTriggered: root.poll()
    }

    Component.onCompleted: Qt.callLater(root.poll)

    function poll() {
        if (!pollProcess.running)
            pollProcess.running = true
    }

    IpcHandler {
        target: "plugin:headset-battery"

        function refresh() {
            root.poll()
        }
    }
}
