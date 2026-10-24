#!/usr/bin/env python3
"""Bundle OTClient data and per-channel updater endpoints into Android data.zip."""

from __future__ import annotations

import argparse
import os
import tempfile
import zipfile
from ipaddress import ip_address
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
CHANNELS = {"test", "beta", "release"}
DATA_ITEMS = ("data", "mods", "modules", "init.lua", "otclientrc.lua")


def is_incrementally_managed_client_asset(relative_path: str) -> bool:
    path_parts = relative_path.split("/")
    return (
        len(path_parts) >= 3
        and path_parts[0] == "data"
        and path_parts[1] in {"things", "sounds"}
        and path_parts[2].isdigit()
        and int(path_parts[2]) >= 1281
    )


def is_local_community_asset(relative_path: str) -> bool:
    return relative_path.startswith(
        ("data/things/1525/", "data/sounds/1525/")
    )


def lua_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    escaped = escaped.replace("\r", "\\r").replace("\n", "\\n")
    return f'"{escaped}"'


def validate_url(value: str, name: str) -> str:
    if not value:
        return ""

    parts = urlsplit(value)
    host = parts.hostname or ""
    is_loopback = host == "localhost"
    if host:
        try:
            is_loopback = is_loopback or ip_address(host).is_loopback
        except ValueError:
            pass

    if (
        not host
        or parts.username
        or parts.password
        or parts.fragment
        or (parts.scheme != "https" and not (parts.scheme == "http" and is_loopback))
    ):
        raise ValueError(f"{name} precisa usar HTTPS; HTTP só é aceito em loopback local")
    return value


def same_origin(left: str, right: str) -> bool:
    left_parts = urlsplit(left)
    right_parts = urlsplit(right)
    left_port = left_parts.port or (443 if left_parts.scheme == "https" else 80)
    right_port = right_parts.port or (443 if right_parts.scheme == "https" else 80)
    return (
        left_parts.scheme == right_parts.scheme
        and (left_parts.hostname or "").lower() == (right_parts.hostname or "").lower()
        and left_port == right_port
    )


def distribution_config(
    channel: str,
    android_url: str,
    assets_url: str,
    auth_url: str,
    release_version: str,
) -> bytes:
    return (
        "return {\n"
        f"  channel = {lua_string(channel)},\n"
        f"  releaseVersion = {lua_string(release_version)},\n"
        f"  androidManifestUrl = {lua_string(android_url)},\n"
        f"  clientAssetsManifestUrl = {lua_string(assets_url)},\n"
        f"  authUrl = {lua_string(auth_url)},\n"
        '  feedPlatform = "android-arm64",\n'
        "}\n"
    ).encode("utf-8")


def validated_distribution_config(
    channel: str,
    android_url: str,
    assets_url: str,
    auth_url: str,
    release_version: str | None = None,
) -> bytes:
    if channel not in CHANNELS:
        raise ValueError(f"Canal Android inválido: {channel}")
    if bool(android_url) != bool(assets_url):
        raise ValueError("Configure os manifestos Android e de assets juntos")

    android_url = validate_url(android_url, "Manifesto Android")
    assets_url = validate_url(assets_url, "Manifesto de assets")
    auth_url = validate_url(auth_url, "Endpoint de cadastro do canal test")

    if auth_url and channel != "test":
        raise ValueError("A autenticação do feed interno só pode ser configurada no canal test")
    remote_test_feed = channel == "test" and any(
        url and urlsplit(url).scheme == "https" for url in (android_url, assets_url)
    )
    if remote_test_feed and not auth_url:
        raise ValueError("Feed test remoto exige --test-auth-url")
    if auth_url and any(
        url and not same_origin(auth_url, url) for url in (android_url, assets_url)
    ):
        raise ValueError("Manifestos e autenticação do feed test precisam usar a mesma origem")

    release_version = (
        release_version
        or os.environ.get("ELEMENTAL_ANDROID_VERSION_NAME")
        or ("0.5.0-beta.1" if channel == "beta" else "1.0")
    )
    return distribution_config(
        channel, android_url, assets_url, auth_url, release_version
    )


def package(
    output: Path, channel: str, android_url: str, assets_url: str, auth_url: str
) -> None:
    missing = [name for name in DATA_ITEMS if not (ROOT / name).exists()]
    if missing:
        raise FileNotFoundError(f"Conteúdo do OTClient ausente: {', '.join(missing)}")

    output.parent.mkdir(parents=True, exist_ok=True)
    config_content = validated_distribution_config(
        channel, android_url, assets_url, auth_url
    )
    config_asset = output.parent / "elemental-distribution.lua"
    config_descriptor, config_temporary_name = tempfile.mkstemp(
        prefix=f".{config_asset.name}.", suffix=".tmp", dir=config_asset.parent
    )
    os.close(config_descriptor)
    config_temporary = Path(config_temporary_name)
    config_temporary.write_bytes(config_content)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.", suffix=".tmp", dir=output.parent
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as bundle:
            for item in DATA_ITEMS:
                source = ROOT / item
                if source.is_symlink():
                    raise ValueError(f"Android bundle não aceita symlinks: {source}")
                if source.is_file():
                    bundle.write(source, item)
                    continue

                for candidate in sorted(source.rglob("*")):
                    if candidate.is_symlink():
                        raise ValueError(f"Android bundle não aceita symlinks: {candidate}")
                    if candidate.is_file():
                        relative_path = candidate.relative_to(ROOT).as_posix()
                        if is_local_community_asset(relative_path):
                            continue
                        if assets_url and is_incrementally_managed_client_asset(relative_path):
                            continue
                        bundle.write(candidate, relative_path)

            bundle.writestr(
                "elemental-distribution.lua",
                config_content,
            )
        config_temporary.replace(config_asset)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
        config_temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--channel", choices=sorted(CHANNELS), required=True)
    parser.add_argument("--android-manifest-url", default="")
    parser.add_argument("--client-assets-manifest-url", default="")
    parser.add_argument("--test-auth-url", default="")
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "android/app/src/main/assets/data.zip",
    )
    args = parser.parse_args()

    package(
        args.output,
        args.channel,
        args.android_manifest_url,
        args.client_assets_manifest_url,
        args.test_auth_url,
    )
    print(f"Bundle Android preparado em {args.output} para o canal {args.channel}.")
    if not args.android_manifest_url:
        print("Updaters Android e de assets permanecem desativados até configurar os manifestos.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
