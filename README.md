# CodexBar for KDE Plasma

A KDE Plasma 6 panel widget that keeps AI coding-provider limits visible —
a faithful re-creation of [CodexBar](https://github.com/steipete/CodexBar)
(Peter Steinberger's macOS menu bar app), driven by the official CodexBar CLI.

![CodexBar in a Plasma panel](docs/screenshots/codexbar-plasma.png)

## Features

- **Panel icon in the original look:** two meter capsules (session on top,
  weekly below), fill = remaining quota, dimmed when data is stale. Default is
  one merged icon showing the worst case across all enabled providers;
  optionally one icon per provider, with the original "critter" faces for
  Codex (eyes) and Claude (asterisk). Optional percentage label.
- **Popup like the original menu:** provider switcher tabs with brand-colored
  quota bars, an overview page, and per provider: session / weekly / extra
  rate windows ("Codex Spark", model-scoped weekly caps, …) with progress
  bars, reset countdowns and a pace line, Codex reset credits, cost
  (today / last 30 days from local token logs via `codexbar cost`),
  provider status and account info, plus the CLI's generic detail rows
  (balances, monthly spend, credit pools, …) for the providers that report
  them. Cost scanning is disabled by default because large local histories
  can be resource-intensive.
- **Actions:** Refresh, explicit cost-history refresh, Usage Dashboard, Status
  Page, Settings, About.
- **Optional Claude multi-account view:** stacked 5-hour and 7-day cards,
  active-account state, and explicit account switching through a compatible
  schema-v1 `claude-swap` adapter.
- **Settings:** refresh interval, any of the 69 providers the CLI supports,
  panel percentage (session/weekly/lowest, remaining/used), plain bars,
  cost/status toggles, custom CLI path, Claude account adapter.

## Requirements

- KDE Plasma 6 (`kpackagetool6`)
- The external [CodexBar CLI](https://github.com/steipete/CodexBar/blob/main/docs/cli.md)
  version 0.43.0 or newer. The widget can download it for you (see below);
  the latest release is recommended because newer providers need it.

The Plasma widget and the CodexBar CLI are installed separately. The CLI is
not bundled in the `.plasmoid` file, but the widget bundles an installer for
it.

## Quick install

One command installs (or updates) both the widget and the CLI for the current
user. No root required:

```bash
curl -fsSL https://raw.githubusercontent.com/psimaker/codexbar-plasmoid/main/scripts/install.sh | sh
```

Then right-click the panel, choose **Add Widgets…**, and search for
**CodexBar**.

The script downloads the current `.plasmoid` from
[GitHub Releases](https://github.com/psimaker/codexbar-plasmoid/releases),
verifies its SHA-256 checksum, and installs it with `kpackagetool6`. It then
downloads the matching official CodexBar CLI archive for your CPU
(`x86_64` or `aarch64`), verifies that checksum too, keeps the CLI under
`~/.local/share/codexbar-cli/<version>/`, and links it as
`~/.local/bin/codexbar`. Use `--widget-only` or `--cli-only` to install one
part, and `--version v0.4.0` to pin a widget release. Re-run the command to
update. An updated widget takes effect after Plasma reloads it (log out and in,
or `systemctl --user restart plasma-plasmashell.service`).

Prefer to read before you run? The script is
[`scripts/install.sh`](scripts/install.sh); the CLI part is
[`contents/scripts/install-cli.sh`](contents/scripts/install-cli.sh).

## Install the Plasma widget manually

### From a `.plasmoid` file

1. Download the current `.plasmoid` file from
   [GitHub Releases](https://github.com/psimaker/codexbar-plasmoid/releases).
2. Right-click the Plasma panel or desktop and select **Add Widgets…**.
3. Select **Get New Widgets** → **Install Widget From Local File…** and pick
   the downloaded file.
4. Search for **CodexBar** and add it to the panel.

From a terminal instead:

```bash
kpackagetool6 -t Plasma/Applet -i com.github.psimaker.codexbar-<version>.plasmoid   # install
kpackagetool6 -t Plasma/Applet -u com.github.psimaker.codexbar-<version>.plasmoid   # update
kpackagetool6 -t Plasma/Applet -r com.github.psimaker.codexbar                     # remove
```

Each release also provides a `.sha256` file. Download it into the same
directory as the `.plasmoid` file and verify the package before installing it:

```bash
sha256sum -c com.github.psimaker.codexbar-<version>.plasmoid.sha256
```

### KDE Store

A KDE Store publication is planned, but the widget is not currently documented
as available there. Until a listing is published and verified, use the
`.plasmoid` package from GitHub Releases.

### From source (development)

```bash
git clone https://github.com/psimaker/codexbar-plasmoid.git
cd codexbar-plasmoid
kpackagetool6 -t Plasma/Applet -i .     # later: -u . to update
```

To build the same minimal package used for releases, run
`scripts/build-plasmoid.sh`. The script packages the current committed `HEAD`
and writes the `.plasmoid` file and SHA-256 checksum under `dist/`. Pass a Git
ref to package an exact commit or tag, for example
`scripts/build-plasmoid.sh v0.3.1`. Existing output is preserved unless
`--force` is supplied. The archive contains only `metadata.json`, `contents/`,
and `LICENSE` from the selected commit.

## Install the CodexBar CLI

Pick one of these. The widget finds `codexbar` on `PATH` (including
`~/.local/bin`); alternatively right-click the widget, select **Configure
CodexBar…**, and set a custom CLI path.

- **From the widget.** When the CLI is missing or too old, the popup shows a
  setup card with an **Install CodexBar CLI** button. The **About CodexBar**
  page offers **Update CodexBar CLI to the latest release** at any time. Both
  run the bundled `install-cli.sh` described above: official release archive,
  checksum verified, user-local, no root.
- **Package manager.** Homebrew/Linuxbrew: `brew install steipete/tap/codexbar`.
  Arch Linux (AUR): `yay -S codexbar-cli`.
- **Manual download.** Get `CodexBarCLI-v<tag>-linux-<arch>.tar.gz` from the
  [CodexBar releases](https://github.com/steipete/CodexBar/releases) (there is
  also a static `linux-musl` build for systems with an older glibc). Extract
  the whole archive and keep the `CodexBarCLI` executable, its `VERSION` file,
  and the `CodexBar_CodexBarCore.bundle` directory together:

  ```bash
  mkdir -p ~/.local/share/codexbar-cli/<tag> ~/.local/bin
  tar -xzf CodexBarCLI-v<tag>-linux-<arch>.tar.gz -C ~/.local/share/codexbar-cli/<tag>
  ln -sfn ~/.local/share/codexbar-cli/<tag>/CodexBarCLI ~/.local/bin/codexbar
  ~/.local/bin/codexbar --version
  ```

Before using the widget, install and sign in to the provider tools or configure
the provider credentials that CodexBar uses (Claude Code, Codex CLI, and so
on). The widget does not perform provider logins.

## Cost refresh behavior

Quota refreshes never start local-history cost scans. When the optional cost
section is enabled, automatic cost scans are serialized and run no more than
once per provider per hour. Use **Refresh cost history** on a Codex or Claude
provider page when an immediate scan is required.

## Optional Claude multi-account adapter

Enable **Show all accounts from a schema-v1 adapter** and set the adapter
executable path. Compatible adapters must implement only these CodexBar
operations:

```text
--list --json
--switch-to <positive-slot> --json
```

The widget validates schema version 1 and retains only account slot, optional
`alias`/`organizationName`/email display identity, active state, the optional
`disabled` rotation flag, usage status, the 5-hour/7-day usage windows,
optional model-scoped weekly windows, and optional pay-as-you-go `spend`
(`used`/`limit`/`pct`/`currency`), which only the adapter can report per
account. When present, identity is displayed as `alias`, then
`organizationName`, then email. The optional `isOrganization` boolean (set from
whether the account has an organization, without exposing its uuid) only adds
a `Personal`/`Organization` tag when `organizationName` is empty — an org
account with an unresolved name is still told apart from a personal one.
Each account row may optionally report `usageFetchedAt` (ISO 8601 timestamp) or
`usageAgeSeconds` (non-negative seconds); when present, the card timestamp and
staleness reflect measurement time rather than poll time, so cached usage is
shown as stale instead of fresh. When a live fetch fails, a row may instead
carry `lastGoodUsage` with `lastGoodFetchedAt`/`lastGoodAgeSeconds`; those
windows go through the same strict projection, are timestamped from the
last-good measurement, and are labelled `last known` instead of being shown as
current. It does not read credentials or profile IDs.

Weekly windows (`sevenDay` and model-scoped entries) may additively report the
adapter's own pace verdict as `expectedPct`/`aheadOfPace`; when present it is
preferred over the pace line the widget otherwise reconstructs locally. The
`projectedExhaustionAt`/`willLastToReset` projections are deliberately not
read — claude-swap keeps that linear extrapolation out of its human surfaces.

Account switches are serialized and only run after an explicit click. The
switch action is offered for the `ok`, `api_key`, `unavailable`,
`token_expired`, and `foreign_credential` statuses — the last two because an
explicit switch is what refreshes an expired token or replaces a credential
belonging to another account. `keychain_unavailable`, `no_credentials`, and
`relogin_required` instead report what has to be fixed outside the widget. A
`disabled` slot is only held out of the adapter's automatic rotation and stays
a valid explicit target, so the card labels it `Not in rotation` without
withdrawing the switch action. Any `warnings` the switch result carries are
shown afterwards, including on a successful switch: in `--json` mode adapters
report them in the payload rather than on stderr, so this is the only place
they can reach you.

Examples:

- Install [`claude-swap`](https://github.com/realiti4/claude-swap) and leave
  the path empty to use `cswap` from `PATH`.
- For another compatible adapter, set its absolute path or a path beginning
  with `~/`.

The CodexBar CLI remains required: normal Claude usage continues to power the
panel icon, overview, cost, provider status, and fallback card.

## Not ported (macOS-only upstream features)

Menu bar animations (blink/wiggle), WidgetKit widgets, notifications,
cost-history and detail-section charts, and the "Add Account" flow — logins
are handled by the provider CLIs themselves.

## Credits & license

MIT — see [LICENSE](LICENSE). This is an independent community port; all
credit for the concept, the design and the CLI goes to
[Peter Steinberger's CodexBar](https://github.com/steipete/CodexBar).
The provider icon SVGs are taken from the upstream repository (MIT).
