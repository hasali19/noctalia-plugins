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

    // --- HID device monitoring ---

    // Watch for HID device add/remove events via udev and re-poll when they occur.
    // A short debounce gives the driver time to finish initialising before we query.
    Process {
        id: udevMonitor
        running: true
        command: ["udevadm", "monitor", "--subsystem-match=hid", "--udev"]

        stdout: SplitParser {
            onRead: line => {
                if (line.includes(" add ") || line.includes(" remove ")) {
                    Logger.d("HeadsetControl", "HID event:", line.trim())
                    udevDebounce.restart()
                }
            }
        }

        stderr: StdioCollector {}

        onExited: function(exitCode, exitStatus) {
            Logger.w("HeadsetControl", "udevadm monitor exited unexpectedly, restarting in 5s")
            udevRestartTimer.start()
        }
    }

    // Wait for the device to finish initialising before querying headsetcontrol
    Timer {
        id: udevDebounce
        interval: 1500
        repeat: false
        onTriggered: root.poll()
    }

    // Restart the monitor if it ever dies
    Timer {
        id: udevRestartTimer
        interval: 5000
        repeat: false
        onTriggered: udevMonitor.running = true
    }

    // --- Periodic polling ---

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
                Logger.e("HeadsetControl", "headsetcontrol exited with code:", exitCode)
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
                Logger.d("HeadsetControl", "Polled", result.length, "device(s)")
            } catch (e) {
                Logger.e("HeadsetControl", "JSON parse error:", e.message)
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
        target: "plugin:headsetcontrol"

        function refresh() {
            root.poll()
        }
    }
}
