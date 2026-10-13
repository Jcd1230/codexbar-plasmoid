import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Thin rounded progress bar. Weekly callers can add 24-hour dividers and
// an expected-usage marker without changing the compact/session bars.
Rectangle {
    id: track

    property real percent: 0          // 0..100 (used)
    property color fillColor: Kirigami.Theme.highlightColor
    property int segmentCount: 0      // weekly windows use 7
    property real markerPercent: -1   // -1 = unavailable/hidden
    property string markerText: markerPercent >= 0
        ? i18n("On pace: %1% used", Math.round(markerPercent)) : ""

    readonly property bool hasMarker: isFinite(markerPercent) && markerPercent >= 0
    readonly property real clampedMarker: Math.max(0, Math.min(100, markerPercent))

    implicitHeight: hasMarker ? 14 : 5
    color: "transparent"

    Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 5
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.14)

        Rectangle {
            visible: track.percent > 0
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: parent.radius
            color: track.fillColor
            width: Math.max(parent.height * 1.4,
                            parent.width * Math.min(100, Math.max(0, track.percent)) / 100)
        }

        // Six dividers make seven equal 24-hour slices of a weekly quota.
        Repeater {
            model: track.segmentCount > 1 ? track.segmentCount - 1 : 0

            Rectangle {
                required property int index
                x: Math.round((index + 1) * bar.width / track.segmentCount)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Qt.alpha(Kirigami.Theme.textColor, 0.42)
            }
        }
    }

    Item {
        id: paceMarker
        visible: track.hasMarker
        width: 14
        height: track.height
        x: bar.width * track.clampedMarker / 100 - width / 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -1
            text: "▼"
            color: Kirigami.Theme.textColor
            font.pixelSize: 10
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 1
            height: bar.height + 1
            color: Kirigami.Theme.textColor
        }

        HoverHandler { id: markerHover }
        QQC2.ToolTip.visible: markerHover.hovered && track.markerText !== ""
        QQC2.ToolTip.delay: 300
        QQC2.ToolTip.text: track.markerText
    }
}
