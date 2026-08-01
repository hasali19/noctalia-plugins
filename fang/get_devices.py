#!/usr/bin/env python3
"""Query dev.hasali.Fang DBus service for Razer mouse battery status.

Usage:
  get_devices.py           - enumerate all devices, output {"devices": [...]}
  get_devices.py <path>    - query a specific device object path, output a single device object
"""

import subprocess
import json
import sys

SERVICE = "dev.hasali.Fang"
DEVICE_IFACE = "dev.hasali.Fang.Device"
MOUSE_IFACE = "dev.hasali.Fang.Mouse"
BASE_PATH = "/dev/hasali/Fang"


def busctl_get_property(path, iface, prop):
    result = subprocess.run(
        ["busctl", "--system", "get-property", SERVICE, path, iface, prop],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    # Output format: "TYPE value\n", e.g. "b true", "y 75"
    parts = result.stdout.strip().split(None, 1)
    return parts[1] if len(parts) >= 2 else None


def get_device(path):
    has_battery = busctl_get_property(path, MOUSE_IFACE, "HasBattery")
    if has_battery != "true":
        return None

    battery_str = busctl_get_property(path, MOUSE_IFACE, "BatteryLevel")
    if battery_str is None:
        return None
    try:
        battery = int(battery_str)
    except ValueError:
        return None

    charging_str = busctl_get_property(path, MOUSE_IFACE, "IsCharging")
    connected_str = busctl_get_property(path, MOUSE_IFACE, "IsConnected")
    # Name lives on the Device interface, shared with the mouse dock.
    name_str = busctl_get_property(path, DEVICE_IFACE, "Name")

    # busctl wraps string values in double quotes; json.loads strips them cleanly
    try:
        name = json.loads(name_str) if name_str else ""
    except (ValueError, TypeError):
        name = name_str or ""

    return {
        "path": path,
        "name": name,
        "battery": battery,
        "charging": charging_str == "true",
        "connected": connected_str == "true",
    }


def get_all_devices():
    result = subprocess.run(
        ["busctl", "tree", "--system", "--no-pager", SERVICE],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []

    devices = []
    seen = set()
    for line in result.stdout.splitlines():
        if BASE_PATH + "/" not in line:
            continue
        idx = line.find(BASE_PATH + "/")
        parts = line[idx:].split()
        if not parts:
            continue
        path = parts[0]
        # Only direct children of BASE_PATH (no further nesting)
        rest = path[len(BASE_PATH) + 1:]
        if not rest or "/" in rest or path in seen:
            continue
        seen.add(path)
        device = get_device(path)
        if device is not None:
            devices.append(device)

    return devices


def main():
    if len(sys.argv) > 1:
        device = get_device(sys.argv[1])
        print(json.dumps(device if device is not None else {"error": "not found"}))
    else:
        print(json.dumps({"devices": get_all_devices()}))


if __name__ == "__main__":
    main()
