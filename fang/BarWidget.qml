import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.System

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property string screenName: screen?.name ?? ""
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)
    readonly property string barPosition: Settings.data.bar.position || "top"
    readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"

    readonly property var mainInstance: pluginApi?.mainInstance

    // Show all devices reported by fang (filtered by HasBattery in the script)
    readonly property var visibleDevices: mainInstance?.devices ?? []

    readonly property bool hasDevices: visibleDevices.length > 0

    readonly property real contentWidth: {
        if (!hasDevices) return 0
        if (barIsVertical) return capsuleHeight
        return deviceRow.implicitWidth + Style.marginM * 2
    }
    readonly property real contentHeight: capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight
    visible: hasDevices

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout {
            id: deviceRow
            anchors.centerIn: parent
            spacing: Style.marginS

            Repeater {
                model: root.visibleDevices

                delegate: RowLayout {
                    spacing: Style.marginS

                    // Thin divider between multiple devices
                    Rectangle {
                        visible: index > 0
                        width: 1
                        height: root.capsuleHeight * 0.5
                        color: Style.capsuleBorderColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    NIcon {
                        icon: "mouse"
                        applyUiScale: false
                        color: {
                            if (modelData.charging)
                                return Color.mPrimary
                            if (modelData.battery <= 20)
                                return Color.mError
                            return mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                        }
                    }

                    NText {
                        visible: !root.barIsVertical
                        pointSize: root.barFontSize
                        text: modelData.charging
                            ? ("⚡" + modelData.battery + "%")
                            : (modelData.battery + "%")
                        color: {
                            if (modelData.battery <= 20)
                                return Color.mError
                            return mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton

        onClicked: mainInstance?.poll()
    }
}
