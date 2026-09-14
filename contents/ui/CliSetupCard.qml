import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "code/cliStatus.js" as CliStatus

Rectangle {
    id: card

    required property var plasmoidRoot

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
    radius: Kirigami.Units.cornerRadius
    color: Qt.alpha(Kirigami.Theme.neutralTextColor, 0.08)
    border.color: Qt.alpha(Kirigami.Theme.neutralTextColor, 0.35)
    border.width: 1

    readonly property string explanation: {
        var state = plasmoidRoot.cliState
        if (state.code === CliStatus.MISSING)
            return i18n("CLI not found. Install CodexBar CLI %1 or newer, or configure its executable path.", CliStatus.MINIMUM_VERSION)
        if (state.code === CliStatus.TIMEOUT)
            return i18n("CLI timed out. Check the configured executable and try again.")
        if (state.code === CliStatus.INCOMPATIBLE && state.detectedVersion !== "")
            return i18n("CLI needs to be updated. Version %1 is installed; version %2 or newer is required.", state.detectedVersion, CliStatus.MINIMUM_VERSION)
        if (state.code === CliStatus.INCOMPATIBLE)
            return i18n("CLI crashed or is incompatible. Install CodexBar CLI %1 or newer, then try again.", CliStatus.MINIMUM_VERSION)
        return i18n("CLI returned unexpected output. Check the installation and try again.")
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "dialog-warning-symbolic"
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: i18n("CodexBar CLI required")
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: card.explanation
            wrapMode: Text.WordWrap
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: i18n("To set a custom CLI path, right-click the widget and choose Configure CodexBar…")
            wrapMode: Text.WordWrap
            opacity: 0.75
            font: Kirigami.Theme.smallFont
        }

        PlasmaComponents3.Button {
            Layout.fillWidth: true
            text: card.plasmoidRoot.cliInstallRunning
                  ? i18n("Installing CodexBar CLI…")
                  : (card.plasmoidRoot.cliState.reason === CliStatus.REASON_VERSION_TOO_OLD
                     ? i18n("Update CodexBar CLI") : i18n("Install CodexBar CLI"))
            icon.name: "download-symbolic"
            enabled: !card.plasmoidRoot.cliInstallRunning
                     && card.plasmoidRoot.cliInstallerPath !== ""
            Accessible.name: text
            onClicked: card.plasmoidRoot.installCli()
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: i18n("Downloads the official CodexBar CLI release for this computer into ~/.local/share/codexbar-cli, verifies its checksum and links ~/.local/bin/codexbar. No root required.")
            wrapMode: Text.WordWrap
            opacity: 0.75
            font: Kirigami.Theme.smallFont
        }

        RowLayout {
            Layout.fillWidth: true
            visible: card.plasmoidRoot.cliInstallRunning
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                running: card.plasmoidRoot.cliInstallRunning
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: i18n("Downloading and verifying the CLI (about 160 MB)…")
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: !card.plasmoidRoot.cliInstallRunning
                     && card.plasmoidRoot.cliInstallExitCode > 0
            text: {
                var lines = card.plasmoidRoot.cliInstallOutput.split("\n")
                return i18n("Installation failed:") + "\n" + lines.slice(-4).join("\n")
            }
            wrapMode: Text.WrapAnywhere
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
        }

        PlasmaComponents3.Button {
            Layout.fillWidth: true
            text: i18n("Open installation guide")
            icon.name: "documentation-symbolic"
            Accessible.name: text
            onClicked: Qt.openUrlExternally("https://github.com/psimaker/codexbar-plasmoid#install-the-codexbar-cli")
        }

        PlasmaComponents3.Button {
            Layout.fillWidth: true
            text: i18n("Open CodexBar CLI documentation")
            icon.name: "internet-web-browser-symbolic"
            Accessible.name: text
            onClicked: Qt.openUrlExternally("https://github.com/steipete/CodexBar/blob/main/docs/cli.md")
        }

        PlasmaComponents3.Button {
            Layout.fillWidth: true
            text: i18n("Retry")
            icon.name: "view-refresh-symbolic"
            Accessible.name: text
            onClicked: card.plasmoidRoot.retryCli()
        }
    }
}
