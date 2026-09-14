"""Keep the provider catalog aligned with the CodexBar CLI and the icon set."""

import pathlib
import re
import unittest


REPOSITORY = pathlib.Path(__file__).resolve().parents[1]
CATALOG = REPOSITORY / "contents" / "ui" / "code" / "catalog.js"
CLI_STATUS = REPOSITORY / "contents" / "ui" / "code" / "cliStatus.js"
ICON_DIR = REPOSITORY / "contents" / "icons"
CLI_IDS = REPOSITORY / "tests" / "data" / "cli-provider-ids.txt"


def catalog_entries():
    source = CATALOG.read_text(encoding="utf-8")
    block = source[source.index("var PROVIDERS = {"):source.index("var COST_PROVIDERS")]
    entries = {}
    for match in re.finditer(r'^\s+"([^"]+)":\s+\{(.*)\},?\s*$', block, re.M):
        fields = dict(re.findall(r'(\w+):\s+"([^"]*)"', match.group(2)))
        entries[match.group(1)] = fields
    return entries


def version_tuple(text):
    return tuple(int(part) for part in text.split("."))


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.entries = catalog_entries()
        self.cli_ids = [
            line.strip()
            for line in CLI_IDS.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.startswith("#")
        ]

    def test_catalog_matches_cli_provider_list_and_order(self):
        self.assertEqual(list(self.entries), self.cli_ids)

    def test_every_entry_has_required_fields(self):
        for provider, fields in self.entries.items():
            with self.subTest(provider=provider):
                self.assertTrue(fields.get("name"))
                self.assertRegex(fields.get("color", ""), r"^#[0-9A-Fa-f]{6}$")
                self.assertIn("dashboard", fields)
                self.assertIn("status", fields)
                self.assertTrue(fields.get("icon", "").endswith(".svg"))
                for url_key in ("dashboard", "status"):
                    if fields[url_key]:
                        self.assertTrue(fields[url_key].startswith("https://"), url_key)

    def test_icons_exist_and_have_no_orphans(self):
        referenced = {fields["icon"] for fields in self.entries.values()}
        present = {path.name for path in ICON_DIR.glob("ProviderIcon-*.svg")}
        self.assertEqual(referenced - present, set(), "missing icon files")
        self.assertEqual(present - referenced, set(), "orphaned icon files")

    def test_min_cli_versions_are_above_the_supported_minimum(self):
        minimum = re.search(
            r'MINIMUM_VERSION = "(\d+\.\d+\.\d+)"', CLI_STATUS.read_text(encoding="utf-8")
        ).group(1)
        for provider, fields in self.entries.items():
            if "minCli" not in fields:
                continue
            with self.subTest(provider=provider):
                self.assertRegex(fields["minCli"], r"^\d+\.\d+\.\d+$")
                self.assertGreater(version_tuple(fields["minCli"]), version_tuple(minimum))

    def test_logo_color_matches_brand_color_for_colored_marks(self):
        # A colored logo whose intrinsic color equals the chip color would
        # vanish on that chip; the catalog marks those so the chip stays clear.
        for provider, fields in self.entries.items():
            if "logoColor" in fields:
                with self.subTest(provider=provider):
                    self.assertEqual(fields["logoColor"].lower(), fields["color"].lower())


if __name__ == "__main__":
    unittest.main()
