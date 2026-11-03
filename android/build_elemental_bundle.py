#!/usr/bin/env python3
"""Build the Android bundle with community assets opt-in for local development."""

import argparse
import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "android/app/src/main/assets/data.zip"
FORBIDDEN_SUFFIXES = {".env", ".jks", ".key", ".keystore", ".p12", ".pem"}
sys.path.insert(0, str(ROOT / "scripts"))
from package_android_data import CHANNELS, validated_distribution_config


DEFAULT_LOCAL_LOGIN_URL = "http://127.0.0.1:8088/login"
LOCAL_TEST_ACCOUNT_CREATE_URL = "http://127.0.0.1:8080/elemental/createaccount"
SERVER_INIT_ENTRY = re.compile(
    r'(?P<indent>^[ \t]*)\["http://127\.0\.0\.1:8088/login"\][ \t]*=[ \t]*\{\n'
    r'(?P<fields>.*?)^[ \t]*\},',
    re.MULTILINE | re.DOTALL,
)
LOCAL_TEST_ACCOUNT_CREATE_ENTRY = re.compile(
    r'(?m)^[ \t]*createAccount[ \t]*=[ \t]*"'
    r'http://127\.0\.0\.1:8080/elemental/createaccount",'
    r'[ \t]*-- local development account creation[ \t]*$'
)
LOCAL_TEST_OVERRIDE = re.compile(
    r'(?ms)^if os\.getenv\("ELEMENTAL_LOCAL_TEST"\) == "1" then\n.*?^end[ \t]*\n'
)


def parse_beta_login_url(login_url):
    try:
        endpoint = urlsplit(login_url)
        port = endpoint.port or 443
    except ValueError as error:
        raise ValueError("login URL has an invalid port") from error

    if (endpoint.scheme != "https" or not endpoint.hostname
            or endpoint.username or endpoint.password or endpoint.query
            or endpoint.fragment or endpoint.path != "/beta/v1/login"):
        raise ValueError("login URL must be HTTPS /beta/v1/login without credentials, query or fragment")
    return endpoint, port


def configure_server_init(init_lua, login_url, port):
    local_test_overrides = list(LOCAL_TEST_OVERRIDE.finditer(init_lua))
    if len(local_test_overrides) != 1:
        raise ValueError("init.lua must contain exactly one local HTTP test override")
    init_lua = LOCAL_TEST_OVERRIDE.sub("", init_lua, count=1)

    entries = list(SERVER_INIT_ENTRY.finditer(init_lua))
    if len(entries) != 1:
        raise ValueError("init.lua must contain exactly one default local beta login entry")

    match = entries[0]
    block = match.group()
    port_pattern = re.compile(r"(?m)^(?P<prefix>[ \t]*port[ \t]*=[ \t]*)\d+(?P<suffix>[ \t]*,?)$")
    http_pattern = re.compile(r"(?m)^(?P<prefix>[ \t]*httpLogin[ \t]*=[ \t]*)true(?P<suffix>[ \t]*,?)$")
    if len(list(port_pattern.finditer(block))) != 1 or len(list(http_pattern.finditer(block))) != 1:
        raise ValueError("default local beta login entry has an unexpected shape")

    block = port_pattern.sub(lambda item: f"{item.group('prefix')}{port}{item.group('suffix')}", block, count=1)
    block = http_pattern.sub(lambda item: f"{item.group('prefix')}false{item.group('suffix')}", block, count=1)
    block = block.replace(DEFAULT_LOCAL_LOGIN_URL, login_url, 1)
    return init_lua[:match.start()] + block + init_lua[match.end():]


def disable_local_account_creation(init_lua):
    entries = list(LOCAL_TEST_ACCOUNT_CREATE_ENTRY.finditer(init_lua))
    if len(entries) != 1:
        raise ValueError("init.lua must contain exactly one local account-creation endpoint")
    return LOCAL_TEST_ACCOUNT_CREATE_ENTRY.sub("", init_lua, count=1)


def files_to_bundle():
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z", "--", "data", "mods", "modules", "init.lua", "LICENSE", "cacert.pem"],
        cwd=ROOT,
    )
    for name in sorted(tracked.decode().split("\0")):
        if not name:
            continue
        relative = Path(name)
        path = ROOT / relative
        if path.is_symlink():
            raise ValueError(f"Symlink in Android bundle: {relative}")
        if any(part.startswith(".") for part in relative.parts):
            continue
        if path.suffix.lower() in FORBIDDEN_SUFFIXES and name != "cacert.pem":
            raise ValueError(f"Private file in Android bundle: {relative}")
        yield path, relative.as_posix()


def local_development_assets_to_bundle():
    for directory in ("data/things/1525", "data/sounds/1525"):
        asset_root = ROOT / directory
        if not asset_root.is_dir():
            raise ValueError(
                f"Missing local development asset directory: {directory}"
            )
        for path in sorted(asset_root.rglob("*")):
            if path.is_symlink():
                raise ValueError(f"Symlink in local development assets: {path}")
            if path.is_file():
                relative = path.relative_to(ROOT)
                if path.suffix.lower() in FORBIDDEN_SUFFIXES:
                    raise ValueError(f"Private file in local development assets: {relative}")
                yield path, relative.as_posix()


def distribution_config_for_channel(
    channel, android_url, assets_url, auth_url, release_version=None
):
    return validated_distribution_config(
        channel, android_url, assets_url, auth_url, release_version
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--login-url", required=True)
    parser.add_argument(
        "--channel",
        choices=sorted(CHANNELS),
        default=os.getenv("ELEMENTAL_ANDROID_CHANNEL", "beta"),
    )
    parser.add_argument(
        "--android-manifest-url", default=os.getenv("ELEMENTAL_ANDROID_MANIFEST_URL", "")
    )
    parser.add_argument(
        "--client-assets-manifest-url",
        default=os.getenv("ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL", ""),
    )
    parser.add_argument("--test-auth-url", default=os.getenv("ELEMENTAL_TEST_AUTH_URL", ""))
    parser.add_argument(
        "--include-local-development-1525-assets",
        action="store_true",
        help="include the community asset pack in a private local development build only",
    )
    args = parser.parse_args()
    try:
        endpoint, port = parse_beta_login_url(args.login_url)
    except ValueError as error:
        parser.error(str(error))
    try:
        distribution_config = distribution_config_for_channel(
            args.channel,
            args.android_manifest_url,
            args.client_assets_manifest_url,
            args.test_auth_url,
            os.getenv("ELEMENTAL_ANDROID_VERSION_NAME"),
        )
    except ValueError as error:
        parser.error(str(error))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED) as bundle:
        for source, relative in files_to_bundle():
            if relative == "init.lua":
                init_lua = source.read_text(encoding="utf-8")
                configured_init = configure_server_init(init_lua, args.login_url, port)
                if args.channel == "test":
                    configured_init = disable_local_account_creation(configured_init)
                bundle.writestr(relative, configured_init)
            else:
                bundle.write(source, relative)
        if args.include_local_development_1525_assets:
            for source, relative in local_development_assets_to_bundle():
                bundle.write(source, relative)
        startup = (
            f"-- Isolated Android {args.channel} endpoint.\n"
            "modules.client_entergame.EnterGame.setDefaultServer("
            f"{json.dumps(args.login_url)}, {port}, 1525)\n"
        )
        bundle.writestr("otclientrc.lua", startup)
        bundle.writestr("elemental-distribution.lua", distribution_config)

    with zipfile.ZipFile(OUTPUT) as bundle:
        names = set(bundle.namelist())
    if "modules/game_wheel/LICENSE" not in names:
        raise ValueError("game_wheel license missing from Android bundle")
    with zipfile.ZipFile(OUTPUT) as bundle:
        configured_init = bundle.read("init.lua").decode("utf-8")
    if DEFAULT_LOCAL_LOGIN_URL in configured_init or args.login_url not in configured_init:
        raise ValueError("Android init.lua does not contain the configured HTTPS beta endpoint")
    if args.channel == "test" and LOCAL_TEST_ACCOUNT_CREATE_URL in configured_init:
        raise ValueError("Closed test Android bundle must not expose local account creation")
    print(f"Android bundle: {OUTPUT} ({len(names)} files, {OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
