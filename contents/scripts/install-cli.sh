#!/bin/sh
# Install or update the CodexBar CLI for the current user.
#
# Downloads the official CodexBar CLI release archive for this machine from
# GitHub, verifies its SHA-256 checksum, keeps the executable together with its
# VERSION file and provider-plugin bundle under ~/.local/share/codexbar-cli, and
# links it as ~/.local/bin/codexbar. It never needs root and never touches
# provider credentials. Re-running it updates an existing installation.
#
# Usage: install-cli.sh [--version vX.Y.Z] [--musl] [--quiet]
#
# Environment overrides (mainly for tests):
#   CODEXBAR_CLI_RELEASE_BASE  base URL of the release assets
#   CODEXBAR_CLI_LATEST_URL    URL whose redirect names the latest release tag
#   CODEXBAR_CLI_HOME          installation directory (default ~/.local/share/codexbar-cli)
#   CODEXBAR_CLI_BIN_DIR       symlink directory (default ~/.local/bin)
set -eu

repo="steipete/CodexBar"
release_base="${CODEXBAR_CLI_RELEASE_BASE:-https://github.com/$repo/releases/download}"
latest_url="${CODEXBAR_CLI_LATEST_URL:-https://github.com/$repo/releases/latest}"
install_home="${CODEXBAR_CLI_HOME:-$HOME/.local/share/codexbar-cli}"
bin_dir="${CODEXBAR_CLI_BIN_DIR:-$HOME/.local/bin}"
requested_version=""
flavor="glibc"
quiet=false

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

log() {
    if [ "$quiet" = false ]; then
        printf '%s\n' "$*"
    fi
}

fail() {
    printf 'install-cli: %s\n' "$*" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            [ $# -ge 2 ] || fail "--version needs a value such as v0.60.2"
            requested_version="$2"
            shift
            ;;
        --version=*)
            requested_version="${1#--version=}"
            ;;
        --musl)
            flavor="musl"
            ;;
        --quiet|-q)
            quiet=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1 (see --help)"
            ;;
    esac
    shift
done

case "$(uname -s)" in
    Linux) ;;
    *) fail "this installer only supports Linux; see https://github.com/$repo/blob/main/docs/cli.md" ;;
esac

arch="$(uname -m)"
case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) fail "unsupported architecture: $arch (CodexBar CLI ships x86_64 and aarch64 builds)" ;;
esac

for tool in tar sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
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

# musl builds are static and run on any Linux; glibc builds need glibc 2.39+.
# Prefer glibc (Homebrew does the same) and fall back to musl automatically.
if [ "$flavor" = "glibc" ] && command -v ldd >/dev/null 2>&1; then
    if ldd --version 2>&1 | head -n 1 | grep -qi musl; then
        flavor="musl"
    fi
fi

version="$requested_version"
if [ -z "$version" ]; then
    log "Looking up the latest CodexBar release…"
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

work="$(mktemp -d "${TMPDIR:-/tmp}/codexbar-cli.XXXXXX")"
trap 'rm -rf "$work"' EXIT INT TERM HUP

download_and_verify() {
    # $1 = flavor; sets $archive on success
    platform="linux"
    [ "$1" = "musl" ] && platform="linux-musl"
    archive="CodexBarCLI-$version-$platform-$arch.tar.gz"
    log "Downloading $archive…"
    fetch "$release_base/$version/$archive" "$work/$archive" \
        || fail "download failed: $release_base/$version/$archive"
    fetch "$release_base/$version/$archive.sha256" "$work/$archive.sha256" \
        || fail "checksum download failed for $archive"
    # The sidecar names the asset; older releases embedded runner paths, so
    # verify by digest rather than trusting the recorded file name.
    expected="$(awk 'NR == 1 { print $1 }' "$work/$archive.sha256")"
    actual="$(sha256sum "$work/$archive" | awk '{ print $1 }')"
    [ -n "$expected" ] && [ "$expected" = "$actual" ] \
        || fail "checksum mismatch for $archive (expected $expected, got $actual)"
    log "Checksum verified."
}

extract() {
    # $1 = archive; extracts into $work/extract
    rm -rf "$work/extract"
    mkdir -p "$work/extract"
    tar -xzf "$work/$1" -C "$work/extract"
    [ -x "$work/extract/CodexBarCLI" ] || fail "archive does not contain the CodexBarCLI executable"
}

download_and_verify "$flavor"
extract "$archive"

if ! "$work/extract/CodexBarCLI" --version >/dev/null 2>&1; then
    if [ "$flavor" = "glibc" ]; then
        log "The glibc build does not run on this system; trying the static musl build…"
        flavor="musl"
        download_and_verify "$flavor"
        extract "$archive"
        "$work/extract/CodexBarCLI" --version >/dev/null 2>&1 \
            || fail "the downloaded CLI does not run on this system"
    else
        fail "the downloaded CLI does not run on this system"
    fi
fi

target="$install_home/$plain_version"
mkdir -p "$install_home" "$bin_dir"
rm -rf "$target.partial"
mv "$work/extract" "$target.partial"
rm -rf "$target"
mv "$target.partial" "$target"
# Symlink to the versioned executable so the CLI finds VERSION and its
# provider-plugin bundle beside itself; ln -sfn replaces an old link atomically.
ln -sfn "$target/CodexBarCLI" "$bin_dir/codexbar"

# Drop previous versions once the new one is linked.
for dir in "$install_home"/*/; do
    dir="${dir%/}"
    [ -d "$dir" ] || continue
    [ "$dir" = "$target" ] && continue
    case "$(basename "$dir")" in
        [0-9]*) rm -rf "$dir" ;;
    esac
done

installed="$("$bin_dir/codexbar" --version 2>/dev/null | head -n 1 || true)"
log "Installed CodexBar CLI $plain_version ($flavor) as $bin_dir/codexbar${installed:+ — $installed}"
case ":${PATH:-}:" in
    *":$bin_dir:"*) ;;
    *) log "Note: $bin_dir is not on your PATH. The Plasma widget finds it anyway; add it to PATH for terminal use." ;;
esac
