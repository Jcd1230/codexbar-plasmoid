#!/bin/sh
# One-step installer for CodexBar on KDE Plasma 6.
#
# Installs (or updates) the CodexBar Plasma widget from the latest GitHub
# release and then the CodexBar CLI it depends on, both for the current user
# only. No root required.
#
#   curl -fsSL https://raw.githubusercontent.com/psimaker/codexbar-plasmoid/main/scripts/install.sh | sh
#
# Usage: install.sh [--widget-only | --cli-only] [--version vX.Y.Z]
#   --widget-only   install only the Plasma widget
#   --cli-only      install only the CodexBar CLI
#   --version       widget release tag to install (default: latest)
#
# Environment overrides (mainly for tests):
#   CODEXBAR_WIDGET_RELEASE_BASE  base URL of the widget release assets
#   CODEXBAR_WIDGET_LATEST_URL    URL whose redirect names the latest widget tag
#   CODEXBAR_PLASMOID_DIR         where kpackagetool6 installs applets
set -eu

repo="psimaker/codexbar-plasmoid"
plugin_id="com.github.psimaker.codexbar"
release_base="${CODEXBAR_WIDGET_RELEASE_BASE:-https://github.com/$repo/releases/download}"
latest_url="${CODEXBAR_WIDGET_LATEST_URL:-https://github.com/$repo/releases/latest}"
plasmoid_dir="${CODEXBAR_PLASMOID_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids}"
install_widget=true
install_cli=true
requested_version=""

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

fail() {
    printf 'install: %s\n' "$*" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --widget-only) install_cli=false ;;
        --cli-only) install_widget=false ;;
        --version)
            [ $# -ge 2 ] || fail "--version needs a value such as v0.4.0"
            requested_version="$2"
            shift
            ;;
        --version=*) requested_version="${1#--version=}" ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) fail "unknown option: $1 (see --help)" ;;
    esac
    shift
done

if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL --retry 2 -o "$2" "$1"; }
    resolve_redirect() { curl -fsSIL -o /dev/null -w '%{url_effective}' "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -q -O "$2" "$1"; }
    resolve_redirect() {
        wget -q --max-redirect=10 --spider -S "$1" 2>&1 \
            | sed -n 's/^ *Location: *//p' | tail -n 1
    }
else
    fail "neither curl nor wget is available"
fi

if [ "$install_widget" = true ]; then
    command -v kpackagetool6 >/dev/null 2>&1 \
        || fail "kpackagetool6 not found — this installer needs KDE Plasma 6"
    command -v sha256sum >/dev/null 2>&1 || fail "required tool not found: sha256sum"

    version="$requested_version"
    if [ -z "$version" ]; then
        printf 'Looking up the latest CodexBar widget release…\n'
        resolved="$(resolve_redirect "$latest_url" || true)"
        version="${resolved##*/}"
        case "$version" in
            v[0-9]*) ;;
            *) fail "could not determine the latest release from $latest_url" ;;
        esac
    fi
    case "$version" in
        v*) ;;
        *) version="v$version" ;;
    esac
    plain_version="${version#v}"
    package="$plugin_id-$plain_version.plasmoid"

    work="$(mktemp -d "${TMPDIR:-/tmp}/codexbar-widget.XXXXXX")"
    trap 'rm -rf "$work"' EXIT INT TERM HUP

    printf 'Downloading %s…\n' "$package"
    fetch "$release_base/$version/$package" "$work/$package" \
        || fail "download failed: $release_base/$version/$package"
    fetch "$release_base/$version/$package.sha256" "$work/$package.sha256" \
        || fail "checksum download failed for $package"
    expected="$(awk 'NR == 1 { print $1 }' "$work/$package.sha256")"
    actual="$(sha256sum "$work/$package" | awk '{ print $1 }')"
    [ -n "$expected" ] && [ "$expected" = "$actual" ] \
        || fail "checksum mismatch for $package"
    printf 'Checksum verified.\n'

    if [ -d "$plasmoid_dir/$plugin_id" ]; then
        printf 'Updating the installed widget…\n'
        kpackagetool6 -t Plasma/Applet -u "$work/$package" >/dev/null
        widget_updated=true
    else
        printf 'Installing the widget…\n'
        kpackagetool6 -t Plasma/Applet -i "$work/$package" >/dev/null
        widget_updated=false
    fi
    printf 'CodexBar widget %s installed.\n' "$plain_version"
fi

if [ "$install_cli" = true ]; then
    cli_installer="$plasmoid_dir/$plugin_id/contents/scripts/install-cli.sh"
    if [ -f "$cli_installer" ]; then
        sh "$cli_installer"
    else
        # --cli-only without an installed widget: fetch the CLI installer
        # from the same project so there is one implementation to maintain.
        work_cli="$(mktemp -d "${TMPDIR:-/tmp}/codexbar-cli-installer.XXXXXX")"
        fetch "https://raw.githubusercontent.com/$repo/main/contents/scripts/install-cli.sh" \
            "$work_cli/install-cli.sh" || { rm -rf "$work_cli"; fail "could not download the CLI installer"; }
        sh "$work_cli/install-cli.sh"
        rm -rf "$work_cli"
    fi
fi

if [ "$install_widget" = true ]; then
    printf '\nNext: right-click your panel → Add Widgets… → search for "CodexBar".\n'
    if [ "${widget_updated:-false}" = true ]; then
        printf 'The updated widget takes effect after Plasma reloads it (log out and in, or run: systemctl --user restart plasma-plasmashell.service).\n'
    fi
fi
