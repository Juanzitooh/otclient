#!/usr/bin/env python3
"""Build the Android bundle with community assets opt-in for local development."""

import argparse
import json
import re
import subprocess
import zipfile
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "android/app/src/main/assets/data.zip"
FORBIDDEN_SUFFIXES = {".env", ".jks", ".key", ".keystore", ".p12", ".pem"}
DEFAULT_LOCAL_LOGIN_URL = "http://127.0.0.1:8088/login"
SERVER_INIT_ENTRY = re.compile(
    r'(?P<indent>^[ \t]*)\["http://127\.0\.0\.1:8088/login"\][ \t]*=[ \t]*\{\n'
    r'(?P<fields>.*?)^[ \t]*\},',
    re.MULTILINE | re.DOTALL,
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--login-url", required=True)
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

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED) as bundle:
        for source, relative in files_to_bundle():
            if relative == "init.lua":
                init_lua = source.read_text(encoding="utf-8")
                configured_init = configure_server_init(init_lua, args.login_url, port)
                bundle.writestr(relative, configured_init)
            else:
                bundle.write(source, relative)
        if args.include_local_development_1525_assets:
            for source, relative in local_development_assets_to_bundle():
                bundle.write(source, relative)
        startup = (
            "-- Isolated Android beta endpoint; publication requires D033/T5.7.\n"
            "modules.client_entergame.EnterGame.setDefaultServer("
            f"{json.dumps(args.login_url)}, {port}, 1525)\n"
        )
        bundle.writestr("otclientrc.lua", startup)

    with zipfile.ZipFile(OUTPUT) as bundle:
        names = set(bundle.namelist())
    if "modules/game_wheel/LICENSE" not in names:
        raise ValueError("game_wheel license missing from Android bundle")
    with zipfile.ZipFile(OUTPUT) as bundle:
        configured_init = bundle.read("init.lua").decode("utf-8")
    if DEFAULT_LOCAL_LOGIN_URL in configured_init or args.login_url not in configured_init:
        raise ValueError("Android init.lua does not contain the configured HTTPS beta endpoint")
    print(f"Android bundle: {OUTPUT} ({len(names)} files, {OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
