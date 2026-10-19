# Client Assets Auto-Install

This document describes the automatic client assets installation flow introduced in OTClient.

## Goal

For modern Tibia client versions (>= 1281), OTClient must be able to:

1. Detect missing assets for the selected version.
2. Prompt the user to download required assets.
3. Download and install assets automatically.
4. Keep final installed files in the same paths already used by OTC runtime.

## Final Install Paths (Source of Truth)

Installed assets must end up in:

- `data/things/<version>/`
- `data/sounds/<version>/`
- runtime extras (when provided by upstream package), such as `bin/*`, in client runtime paths.

Do not introduce an alternative permanent assets root for runtime loading.

## Main Module

- Lua module: `modules/client_assets/client_assets.lua`
- Enter-game integration: `modules/client_entergame/entergame.lua`
- Modern things/sounds loading: `modules/game_things/things.lua`

## Download / Install Strategy

The flow supports:

- archive installation from the release/tag source ZIP as the default path
- manifest-driven installation as a fallback path when the archive cannot be installed
- manifest hash identifier installation into `data/things/<version>/assets.json.sha256`
- packaged files list (including large binaries distributed as `.zip`/`.rar`)
- extraction of `.zip` and `.rar`
- optional `.lzma` decompression

## Integrity and Security Defaults

Defaults are hardened:

- `strictManifestSha256 = true`
- `allowRawFallbackHashMismatch = false`
- `allowMissingPackedRawFallback = true`

`allowMissingPackedRawFallback` is a narrow compatibility fallback for repository releases that reference official `.lzma`/archive package files not stored in the assets repository. It is only used after the packed file is missing and the client falls back to the raw file from the same manifest/release source. It does not enable arbitrary hash mismatches for normal raw downloads.

Release cache is scoped per source (`releasesUrl` / repository key), avoiding stale cross-source reuse.

## Runtime/Platform Notes

- Desktop targets use `libarchive` for archive extraction when it is available.
- Builds without `libarchive` still extract `.zip` archives through the vendored minizip fallback. This keeps the GitHub source ZIP flow functional on clean desktop builds.
- `.rar` extraction requires `libarchive`. If a packaged `.rar` is optional and the build cannot extract it, installation should fail clearly or skip it according to the package configuration.
- The default flow is archive-first because the release source ZIP is the canonical package for this repository. The manifest path remains a compatibility fallback, not the primary installation path.
- Emscripten login fallback was aligned with native `httpLogin` semantics.

## Channel Updates for Sprites and Audio

Missing assets continue to use the existing confirmation and install flow. To
check for newer Elemental assets even when the selected client version is
already installed, enable `Services.clientAssets.updateCheckEnabled` and set
`Services.clientAssets.manifestUrl` to the matching channel's
`client-assets-manifest.json`. The updater uses the channel in
`Services.elementalUpdater.channel`; the manifest must have the same channel.
Keep the check disabled until that channel's HTTPS feed is available.

The channel manifest maps OTClient versions to an immutable `assetRevision`, a
SHA-256-protected file manifest, and a base HTTPS URL. A new release revision
causes the client to compare each installed file with its expected SHA-256 and
download only missing or changed files. The generated manifest contains raw
files under `assets/` and `sounds/`, so Android does not need `libarchive` for
this update path. Download progress is weighted by the manifest's exact file
sizes. Files install before login into the normal
`data/things/<version>/` and `data/sounds/<version>/` paths. The completion
marker advances only after every file and the manifest hash identifier have
been written successfully; an interrupted update is retried before a later
login. After installation, the selected version's appearances, static data,
and sound catalog are reloaded in memory before login continues.

When an asset channel check is enabled, a missing feed, mismatched channel,
invalid revision, missing SHA-256, or unsupported archive entry stops that
login and reports an error. This is intentional: the game must not log in with
a partially applied asset revision. A new asset set must use a new immutable
release version; do not replace the contents behind a revision already used
by collaborators.

Android APK updates remain a separate flow. The APK is still downloaded whole
and installed through Android's package installer; sprites and audio can be
updated separately without reinstalling the APK.

## UX Behavior

- Missing-assets dialog prompts before download.
- Download window supports cancellation.
- Progress supports indeterminate mode when remote does not provide reliable content length.
- Console logs show major phases and final install paths.

## Troubleshooting

### 1) Assets appear downloaded but game still cannot load

Check:

- `data/things/<version>/catalog-content.json`
- `data/things/<version>/assets.json.sha256`
- `data/sounds/<version>/catalog-sound.json` (when sounds are enabled)

### 2) Missing `.lzma` package file

If the console shows a 404 for `*.lzma`, the client is using the manifest fallback instead of the release source ZIP. First check why archive installation failed. The manifest fallback can install raw files through `allowMissingPackedRawFallback`, but this path is slower and should not be the normal flow for clean installs.

### 3) SHA-256 mismatch

By default, mismatches fail installation. Verify upstream files and hashes first before changing integrity flags.

### 4) Slow progress / “stuck”

If Content-Length is missing, UI may run in indeterminate mode during download and extraction. Use console logs to confirm active phase.

## Configuration (init.lua)

`Services.clientAssets` supports runtime behavior controls (repository, archive preference, sounds, packaged files, hash strictness, etc.). Keep secure defaults unless there is a specific compatibility reason to relax.

Desktop builds receive `ELEMENTAL_CHANNEL` and
`ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL` from the launcher. Android builds use
`scripts/package_android_data.py` to embed a channel-specific
`elemental-distribution.lua` with both APK and client-assets manifest URLs.
The standalone config asset is refreshed on each APK start, including upgrades
that already have `game_data/init.lua` extracted. Leave both URLs empty until a
controlled feed is available; the corresponding updater stays disabled.

When either distribution package is configured with its incremental client
assets feed, modern versioned content (1281+) is omitted from that package.
The desktop feed generator and Android `data.zip` keep shared runtime files,
while sprites and audio are fetched before login into the standard paths above.
Android packages built without feed URLs retain those files as an offline
fallback. `game_things` defers its missing-assets dialog and version reset only
when the modern asset updater is enabled; the login flow then downloads,
verifies, and reloads the assets before connecting.

## Maintenance Checklist

When changing this system, validate:

1. Missing assets prompt appears for modern version.
2. Install completes into `data/things/<version>` and `data/sounds/<version>`.
3. Runtime loads modern assets from those paths.
4. Hash verification behavior matches configuration.
5. Windows/Linux CI remains green; Android does not attempt to resolve unsupported libarchive linkage.
