"""Exercise the user-facing installers against local fake releases."""

import hashlib
import io
import os
import pathlib
import shutil
import stat
import subprocess
import tarfile
import tempfile
import unittest


REPOSITORY = pathlib.Path(__file__).resolve().parents[1]
CLI_INSTALLER = REPOSITORY / "contents" / "scripts" / "install-cli.sh"
WIDGET_INSTALLER = REPOSITORY / "scripts" / "install.sh"
PLUGIN_ID = "com.github.psimaker.codexbar"
ARCH = {"x86_64": "x86_64", "amd64": "x86_64", "aarch64": "aarch64", "arm64": "aarch64"}.get(
    os.uname().machine
)


def write_sha256(path):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    (path.parent / f"{path.name}.sha256").write_text(f"{digest}  {path.name}\n")
    return digest


def make_cli_archive(directory, tag, platform, version_output):
    archive = directory / f"CodexBarCLI-{tag}-{platform}-{ARCH}.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        executable = f"#!/bin/sh\nprintf 'CodexBar {version_output}\\n'\n".encode()
        info = tarfile.TarInfo("CodexBarCLI")
        info.size = len(executable)
        info.mode = 0o755
        tar.addfile(info, io.BytesIO(executable))
        version = f"{tag[1:]}\n".encode()
        info = tarfile.TarInfo("VERSION")
        info.size = len(version)
        tar.addfile(info, io.BytesIO(version))
        info = tarfile.TarInfo("CodexBar_CodexBarCore.bundle")
        info.type = tarfile.DIRTYPE
        info.mode = 0o755
        tar.addfile(info)
        link = tarfile.TarInfo("codexbar")
        link.type = tarfile.SYMTYPE
        link.linkname = "CodexBarCLI"
        tar.addfile(link)
    write_sha256(archive)
    return archive


class InstallerTestCase(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp_dir.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.home),
            "TMPDIR": str(self.root),
        }

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_script(self, script, *args, env=None, check=True):
        merged = dict(self.env)
        merged.update(env or {})
        return subprocess.run(
            ["sh", str(script), *args],
            env=merged,
            check=check,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )


class ShellSyntaxTests(InstallerTestCase):
    def test_scripts_parse(self):
        for script in (CLI_INSTALLER, WIDGET_INSTALLER):
            with self.subTest(script=script.name):
                subprocess.run(["sh", "-n", str(script)], check=True)
                self.assertTrue(script.stat().st_mode & stat.S_IXUSR, "must be executable")
                self.assertTrue(script.read_text().startswith("#!/bin/sh\n"))

    def test_help_text(self):
        for script in (CLI_INSTALLER, WIDGET_INSTALLER):
            with self.subTest(script=script.name):
                result = self.run_script(script, "--help")
                self.assertIn("Usage:", result.stdout)


@unittest.skipUnless(ARCH and shutil.which("curl"), "needs curl and a supported architecture")
class CliInstallerTests(InstallerTestCase):
    def setUp(self):
        super().setUp()
        self.releases = self.root / "releases"
        self.release_dir = self.releases / "v9.9.9"
        self.release_dir.mkdir(parents=True)
        make_cli_archive(self.release_dir, "v9.9.9", "linux", "9.9.9")
        self.env["CODEXBAR_CLI_RELEASE_BASE"] = self.releases.as_uri()

    def cli_home(self):
        return self.home / ".local" / "share" / "codexbar-cli"

    def cli_link(self):
        return self.home / ".local" / "bin" / "codexbar"

    def test_installs_explicit_version_and_links_binary(self):
        result = self.run_script(CLI_INSTALLER, "--version", "v9.9.9")
        self.assertIn("Checksum verified.", result.stdout)
        self.assertIn("Installed CodexBar CLI 9.9.9 (glibc)", result.stdout)
        self.assertTrue(self.cli_link().is_symlink())
        self.assertEqual(
            self.cli_link().resolve(), (self.cli_home() / "9.9.9" / "CodexBarCLI").resolve()
        )
        self.assertTrue((self.cli_home() / "9.9.9" / "VERSION").is_file())
        self.assertTrue((self.cli_home() / "9.9.9" / "CodexBar_CodexBarCore.bundle").is_dir())
        output = subprocess.run(
            [str(self.cli_link()), "--version"], check=True, text=True, stdout=subprocess.PIPE
        ).stdout
        self.assertEqual(output.strip(), "CodexBar 9.9.9")

    def test_resolves_latest_release_from_redirect_target(self):
        latest = self.root / "latest" / "v9.9.9"
        latest.parent.mkdir()
        latest.write_text("")
        result = self.run_script(
            CLI_INSTALLER, env={"CODEXBAR_CLI_LATEST_URL": latest.as_uri()}
        )
        self.assertIn("Installed CodexBar CLI 9.9.9", result.stdout)

    def test_update_replaces_previous_versions(self):
        stale = self.cli_home() / "1.2.3"
        stale.mkdir(parents=True)
        (stale / "CodexBarCLI").write_text("old")
        self.cli_link().parent.mkdir(parents=True)
        self.cli_link().symlink_to(stale / "CodexBarCLI")
        self.run_script(CLI_INSTALLER, "--version", "9.9.9")
        self.assertFalse(stale.exists())
        self.assertEqual(sorted(p.name for p in self.cli_home().iterdir()), ["9.9.9"])
        self.assertEqual(self.cli_link().resolve(), (self.cli_home() / "9.9.9" / "CodexBarCLI").resolve())

    def test_checksum_mismatch_installs_nothing(self):
        archive = next(self.release_dir.glob("*.tar.gz"))
        (self.release_dir / f"{archive.name}.sha256").write_text("0" * 64 + f"  {archive.name}\n")
        result = self.run_script(CLI_INSTALLER, "--version", "v9.9.9", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("checksum mismatch", result.stdout)
        self.assertFalse(self.cli_home().exists())
        self.assertFalse(self.cli_link().exists())

    def test_falls_back_to_musl_when_glibc_build_does_not_run(self):
        # Replace the glibc archive with one whose executable fails to start.
        for stale in self.release_dir.iterdir():
            stale.unlink()
        make_cli_archive(self.release_dir, "v9.9.9", "linux", "9.9.9")
        broken = next(self.release_dir.glob("*linux-x86_64.tar.gz")) if ARCH == "x86_64" \
            else next(self.release_dir.glob("*linux-aarch64.tar.gz"))
        with tarfile.open(broken, "w:gz") as tar:
            payload = b"#!/bin/sh\nexit 127\n"
            info = tarfile.TarInfo("CodexBarCLI")
            info.size = len(payload)
            info.mode = 0o755
            tar.addfile(info, io.BytesIO(payload))
        write_sha256(broken)
        make_cli_archive(self.release_dir, "v9.9.9", "linux-musl", "9.9.9-musl")
        result = self.run_script(CLI_INSTALLER, "--version", "v9.9.9")
        self.assertIn("trying the static musl build", result.stdout)
        self.assertIn("Installed CodexBar CLI 9.9.9 (musl)", result.stdout)

    def test_rejects_unknown_option(self):
        result = self.run_script(CLI_INSTALLER, "--bogus", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("unknown option", result.stdout)


@unittest.skipUnless(shutil.which("curl"), "needs curl")
class WidgetInstallerTests(InstallerTestCase):
    def setUp(self):
        super().setUp()
        self.releases = self.root / "widget-releases"
        release_dir = self.releases / "v0.9.0"
        release_dir.mkdir(parents=True)
        self.package = release_dir / f"{PLUGIN_ID}-0.9.0.plasmoid"
        self.package.write_bytes(b"PK\x05\x06" + b"\0" * 18)
        write_sha256(self.package)
        self.plasmoids = self.root / "plasmoids"
        self.plasmoids.mkdir()
        # Fake kpackagetool6 that records its arguments and "installs" the
        # package by creating the plugin directory.
        self.fake_bin = self.root / "fakebin"
        self.fake_bin.mkdir()
        self.log = self.root / "kpackagetool6.log"
        tool = self.fake_bin / "kpackagetool6"
        tool.write_text(
            "#!/bin/sh\n"
            f"printf '%s\\n' \"$*\" >> '{self.log}'\n"
            f"mkdir -p '{self.plasmoids}/{PLUGIN_ID}/contents/scripts'\n"
        )
        tool.chmod(0o755)
        self.env.update({
            "PATH": f"{self.fake_bin}:{os.environ['PATH']}",
            "CODEXBAR_WIDGET_RELEASE_BASE": self.releases.as_uri(),
            "CODEXBAR_PLASMOID_DIR": str(self.plasmoids),
        })

    def test_fresh_install_uses_install_flag(self):
        result = self.run_script(WIDGET_INSTALLER, "--widget-only", "--version", "v0.9.0")
        self.assertIn("Checksum verified.", result.stdout)
        self.assertIn("CodexBar widget 0.9.0 installed.", result.stdout)
        self.assertIn("Add Widgets", result.stdout)
        calls = self.log.read_text().splitlines()
        self.assertEqual(len(calls), 1)
        self.assertTrue(calls[0].startswith("-t Plasma/Applet -i "), calls[0])
        self.assertTrue(calls[0].endswith(self.package.name))

    def test_existing_install_uses_update_flag(self):
        (self.plasmoids / PLUGIN_ID).mkdir()
        result = self.run_script(WIDGET_INSTALLER, "--widget-only", "--version", "0.9.0")
        calls = self.log.read_text().splitlines()
        self.assertTrue(calls[0].startswith("-t Plasma/Applet -u "), calls[0])
        self.assertIn("takes effect after Plasma reloads", result.stdout)

    def test_runs_bundled_cli_installer_after_widget_install(self):
        marker = self.root / "cli-installer-ran"
        bundled = self.plasmoids / PLUGIN_ID / "contents" / "scripts"
        bundled.mkdir(parents=True)
        (bundled / "install-cli.sh").write_text(f"#!/bin/sh\ntouch '{marker}'\n")
        result = self.run_script(WIDGET_INSTALLER, "--version", "v0.9.0")
        self.assertTrue(marker.exists())
        self.assertIn("CodexBar widget 0.9.0 installed.", result.stdout)

    def test_checksum_mismatch_does_not_install(self):
        (self.package.parent / f"{self.package.name}.sha256").write_text("f" * 64 + "\n")
        result = self.run_script(
            WIDGET_INSTALLER, "--widget-only", "--version", "v0.9.0", check=False
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("checksum mismatch", result.stdout)
        self.assertFalse(self.log.exists())

    def test_both_scope_flags_disable_everything_without_failing(self):
        result = self.run_script(WIDGET_INSTALLER, "--cli-only", "--widget-only", check=False)
        # Both scopes disabled: nothing to do, but the script must not fail.
        self.assertEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
