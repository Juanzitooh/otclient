import unittest
from pathlib import Path

import sys


ANDROID_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ANDROID_DIR))

import build_elemental_bundle


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

        duplicated = self.init_lua + self.init_lua[self.init_lua.index("[\"http://127.0.0.1:8080/elemental/login\"]"):]
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


if __name__ == "__main__":
    unittest.main()
