import unittest
from pathlib import Path
from unittest.mock import patch

import sys


ANDROID_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ANDROID_DIR))

import build_elemental_bundle
import package_android_data


class ConfigureServerInitTests(unittest.TestCase):
    def setUp(self):
        self.init_lua = (ANDROID_DIR.parent / "init.lua").read_text(encoding="utf-8")

    def test_configures_https_beta_url_port_and_disables_http_login(self):
        url = "https://localhost:18443/beta/v1/login"

        result = build_elemental_bundle.configure_server_init(self.init_lua, url, 18443)

        self.assertIn(f'["{url}"] = {{', result)
        self.assertIn("port = 18443,", result)
        self.assertIn("httpLogin = false,", result)
        self.assertNotIn(build_elemental_bundle.DEFAULT_LOCAL_LOGIN_URL, result)
        self.assertNotIn("ELEMENTAL_LOCAL_TEST", result)

    def test_https_url_without_explicit_port_uses_443(self):
        endpoint, port = build_elemental_bundle.parse_beta_login_url(
            "https://beta.example.invalid/beta/v1/login"
        )

        self.assertEqual(endpoint.hostname, "beta.example.invalid")
        self.assertEqual(port, 443)

    def test_rejects_missing_or_duplicate_local_default(self):
        without_default = self.init_lua.replace(
            build_elemental_bundle.DEFAULT_LOCAL_LOGIN_URL, "http://other.invalid/login"
        )
        with self.assertRaises(ValueError):
            build_elemental_bundle.configure_server_init(
                without_default, "https://localhost/beta/v1/login", 443
            )

        local_entry_match = build_elemental_bundle.SERVER_INIT_ENTRY.search(self.init_lua)
        self.assertIsNotNone(local_entry_match)
        duplicated = self.init_lua + local_entry_match.group()
        with self.assertRaises(ValueError):
            build_elemental_bundle.configure_server_init(
                duplicated, "https://localhost/beta/v1/login", 443
            )

    def test_rejects_non_beta_or_non_https_url(self):
        for url in (
            "http://localhost:18443/beta/v1/login",
            "https://localhost/beta/v1/other",
            "https://user@localhost/beta/v1/login",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                build_elemental_bundle.parse_beta_login_url(url)


class DistributionConfigTests(unittest.TestCase):
    def test_beta_config_disables_unconfigured_updaters(self):
        result = build_elemental_bundle.distribution_config_for_beta(
            "beta", "", "", ""
        ).decode("utf-8")

        self.assertIn('channel = "beta",', result)
        self.assertIn('releaseVersion = "0.5.0-beta.1",', result)
        self.assertIn('feedPlatform = "android-arm64",', result)
        self.assertIn('androidManifestUrl = "",', result)
        self.assertIn('clientAssetsManifestUrl = "",', result)
        self.assertIn('authUrl = "",', result)

    def test_beta_config_uses_explicit_build_version(self):
        result = build_elemental_bundle.distribution_config_for_beta(
            "beta", "", "", "", "0.5.0-beta.2"
        ).decode("utf-8")

        self.assertIn('releaseVersion = "0.5.0-beta.2",', result)

    def test_distribution_config_uses_selected_android_version_name(self):
        with patch.dict(
            "os.environ", {"ELEMENTAL_ANDROID_VERSION_NAME": "2026.10.21-test.1"}
        ):
            result = package_android_data.validated_distribution_config(
                "test", "", "", ""
            ).decode("utf-8")

        self.assertIn('releaseVersion = "2026.10.21-test.1",', result)

    def test_beta_config_rejects_partial_manifests_and_test_auth(self):
        with self.assertRaises(ValueError):
            build_elemental_bundle.distribution_config_for_beta(
                "beta", "https://feed.example/android.json", "", ""
            )

        with self.assertRaises(ValueError):
            build_elemental_bundle.distribution_config_for_beta(
                "beta", "", "", "https://feed.example/enroll"
            )

    def test_beta_config_rejects_remote_http_manifest(self):
        with self.assertRaises(ValueError):
            build_elemental_bundle.distribution_config_for_beta(
                "beta",
                "http://feed.example/android.json",
                "http://feed.example/assets.json",
                "",
            )


class GenericPackageAssetTests(unittest.TestCase):
    def test_local_community_pack_requires_beta_opt_in(self):
        self.assertTrue(
            package_android_data.is_local_community_asset(
                "data/things/1525/Tibia.dat"
            )
        )
        self.assertTrue(
            package_android_data.is_local_community_asset(
                "data/sounds/1525/sound.ogg"
            )
        )
        self.assertFalse(
            package_android_data.is_local_community_asset(
                "data/things/1524/Tibia.dat"
            )
        )


if __name__ == "__main__":
    unittest.main()
