import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "code/cliStatus.js" as CliStatus

ColumnLayout {
    id: about

    required property var plasmoidRoot

    signal backRequested()

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing * 2

        CritterIcon {
            providerId: "codex"
            remainingPrimary: 80
            remainingSecondary: 60
            Layout.preferredWidth: Kirigami.Units.iconSizes.large
            Layout.preferredHeight: Kirigami.Units.iconSizes.large
        }

        ColumnLayout {
            spacing: 0

            PlasmaComponents3.Label {
                text: "CodexBar"
                font.weight: Font.Bold
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            }

            PlasmaComponents3.Label {
                text: i18n("Plasma port, v0.3.1 — data via codexbar CLI")
                opacity: 0.6
                font: Kirigami.Theme.smallFont
            }
        }
    }

    Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("Keeps AI coding-provider limits visible in your panel. A KDE Plasma re-creation of Peter Steinberger's CodexBar for macOS, driven by the official CodexBar CLI.")
        wrapMode: Text.WordWrap
        opacity: 0.75
        font: Kirigami.Theme.smallFont
    }

    Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: {
            about.plasmoidRoot.rev
            var state = about.plasmoidRoot.cliState
            if (about.plasmoidRoot.cliInstallRunning)
                return i18n("CodexBar CLI: installing…")
            if (state.code === CliStatus.CHECKING)
                return i18n("CodexBar CLI: checking…")
            if (state.detectedVersion !== "")
                return state.code === CliStatus.INCOMPATIBLE
                    ? i18n("CodexBar CLI: %1 installed, %2 or newer required", state.detectedVersion, CliStatus.MINIMUM_VERSION)
                    : i18n("CodexBar CLI: %1 installed", state.detectedVersion)
            if (state.code === CliStatus.MISSING)
                return i18n("CodexBar CLI: not found")
            return i18n("CodexBar CLI: unavailable")
        }
        wrapMode: Text.WordWrap
        opacity: 0.75
        font: Kirigami.Theme.smallFont
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: !about.plasmoidRoot.cliInstallRunning
                 && about.plasmoidRoot.cliInstallExitCode >= 0
        text: {
            var lines = about.plasmoidRoot.cliInstallOutput.split("\n")
            return lines.slice(-3).join("\n")
        }
        wrapMode: Text.WrapAnywhere
        color: about.plasmoidRoot.cliInstallExitCode === 0
               ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
        font: Kirigami.Theme.smallFont
    }

    MenuRow {
        iconName: "download-symbolic"
        label: about.plasmoidRoot.cliInstallRunning
               ? i18n("Installing CodexBar CLI…")
               : (about.plasmoidRoot.cliState.detectedVersion !== ""
                  ? i18n("Update CodexBar CLI to the latest release")
                  : i18n("Install CodexBar CLI"))
        interactive: !about.plasmoidRoot.cliInstallRunning
                     && about.plasmoidRoot.cliInstallerPath !== ""
        onActivated: about.plasmoidRoot.installCli()
    }

    MenuRow {
        iconName: "internet-services-symbolic"
        label: i18n("CodexBar on GitHub")
        onActivated: Qt.openUrlExternally("https://github.com/steipete/CodexBar")
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
    }

    MenuRow {
        iconName: "go-previous-symbolic"
        label: i18n("Back")
        onActivated: about.backRequested()
    }
}
