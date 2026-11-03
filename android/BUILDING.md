# Building OTClient for Android

## Prerequisites

- **Linux host** (Ubuntu 22.04+ or WSL2 recommended)
- **Java 17** (`sudo apt install openjdk-17-jdk`)
- **Android SDK** with NDK 29.0.13599879 and CMake 3.22.1
- **vcpkg** (cloned and bootstrapped)
- **gcc-multilib** for 32-bit LuaJIT cross-compilation (`sudo apt install gcc-multilib g++-multilib`)

### Environment variables

```bash
export ANDROID_HOME=/path/to/android-sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/29.0.13599879
export VCPKG_ROOT=/path/to/vcpkg
export JAVA_HOME=/usr  # or path to JDK 17
```

## Quick build (automated)

For a channel-specific APK, set `ELEMENTAL_ANDROID_CHANNEL` and both manifest
URLs before packaging. If the URLs are empty, the Android APK updater and
client-assets updater stay disabled. `test` uses
`br.com.elementalmmo.client.test`; `beta` and `release` use
`br.com.elementalmmo.client`, so beta can update in place to release. Keep one
increasing `versionCode` sequence across beta and release. Test has a separate
sequence and installs alongside them.

```bash
export ELEMENTAL_ANDROID_CHANNEL=test
export ELEMENTAL_TEST_LOGIN_URL="https://test-game.elementalmmo.com.br/beta/v1/login"
export ELEMENTAL_ANDROID_MANIFEST_URL="https://test-feed.elementalmmo.com.br/updates/test/android-manifest.json"
export ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL="https://test-feed.elementalmmo.com.br/updates/test/client-assets-manifest.json"
export ELEMENTAL_TEST_AUTH_URL="https://test-feed.elementalmmo.com.br/distribution/v1/enroll"
export ELEMENTAL_ANDROID_VERSION_CODE=20261032
export ELEMENTAL_ANDROID_VERSION_NAME=2026.10.23-test.1
export OTCLIENT_ANDROID_ABIS=arm64-v8a

# 1. Run the setup script (builds LuaJIT, installs vcpkg deps, generates data.zip)
bash setup_android_deps.sh

# 2. Build the APK
cd android
bash gradlew assembleRelease
```

The APK will be at `android/app/build/outputs/apk/release/app-release.apk`.

## Step-by-step build

### Step 1: Build LuaJIT for Android

LuaJIT must be cross-compiled separately because the vcpkg LuaJIT port cannot cross-compile for Android from an x64 host ([LuaJIT Issue #664](https://github.com/LuaJIT/LuaJIT/issues/664)).

```bash
# Clone LuaJIT source (pinned to vcpkg-compatible commit)
git clone https://github.com/LuaJIT/LuaJIT.git luajit-src
cd luajit-src && git checkout d0e88930ddde28ff662503f9f20facf34f7265aa && cd ..

# Cross-compile for all 4 ABIs
./build_luajit_android.sh
```

This produces static libraries in `android/app/libs/lib/{ABI}/libluajit-5.1.a` and headers in `android/app/libs/include/luajit/`.

#### How it works

LuaJIT's build is a two-stage process: host tools (`minilua`, `buildvm`) run on your machine to generate target-specific code, then the NDK cross-compiler compiles the library. Key flags:

| Flag | Why |
|------|-----|
| `HOST_CC="gcc -m32"` | Required for 32-bit targets (armeabi-v7a, x86) — ensures matching pointer sizes between host tools and target ([#664](https://github.com/LuaJIT/LuaJIT/issues/664)) |
| `-DLUAJIT_UNWIND_EXTERNAL` | Required for Android NDK — prevents conflict between LuaJIT's internal unwinder and C++ exception handling |
| `-fno-stack-protector` | Avoids linker issues with NDK's stack protector implementation |
| `-fPIC` | Required for x86 ABI — static lib linked into a shared `.so` |
| `amalg` | Single-file build for better optimization |
| `TARGET_SYS=Linux` | Never use `TARGET_SYS=Android` — causes crashes ([#440](https://github.com/LuaJIT/LuaJIT/issues/440)) |

### Step 2: Generate data.zip

`setup_android_deps.sh` uses the channel-aware packager for `test` and `beta`.
For `test`, set `ELEMENTAL_TEST_LOGIN_URL`; the builder rewrites the packaged
default server to that HTTPS endpoint and removes the local HTTP test override.
The `release` channel uses the generic packager.

```bash
# This generic packager is for release. Test and beta use build_elemental_bundle.py
# so the packaged OTClient login points at the selected HTTPS server.
python3 scripts/package_android_data.py \
  --channel release \
  --android-manifest-url "$ELEMENTAL_ANDROID_MANIFEST_URL" \
  --client-assets-manifest-url "$ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL" \
  --test-auth-url ""
```

The bundle embeds those values in `elemental-distribution.lua`. Keep URLs on
the same channel as the APK and use HTTPS on devices used by Desenvolvedores.
HTTP is accepted only for loopback development fixtures. The output contains the
`data`, `mods`, and `modules` trees; local community 15.25 directories are
excluded from generic channel packages. Do not reuse a stale `data.zip`
when changing channels. A remote `test` feed must also provide the shared-
password enrollment endpoint with `--test-auth-url`; it must have the same
HTTPS origin as the Android and assets manifests. The shared password is never
embedded in the APK. The first feed access enrolls this installation and stores
only its individual revocable token in the client settings.

### Step 3: Build with Gradle

Every `assembleRelease` requires all four signing variables below and fails
without them; release builds never fall back to Android's debug key. Keep each
keystore outside Git and use a protected backup. The `test` package uses the
stable `elemental-test` signing identity. Beta and release share an
`applicationId`, so they must keep the same stable signing identity with alias
`elemental-beta` and an increasing `versionCode` sequence.

```bash
export RELEASE_KEYSTORE=/private/path/elemental-test.jks
export RELEASE_KEYSTORE_PASSWORD=...
export RELEASE_KEY_ALIAS=elemental-test
export RELEASE_KEY_PASSWORD=...
```

```bash
cd android
bash gradlew assembleRelease    # or bash gradlew assembleDebug
```

### Step 4: Install on device

```bash
adb install android/app/build/outputs/apk/release/app-release.apk
```

When a newer APK is installed, the client detects the new `versionCode` and
refreshes the APK's Lua/OTUI bootstrap from `data.zip`. Sprite and sound files
can still update incrementally from their separate feed; those assets do not
require rebuilding the APK. Android always downloads a new APK in full and
requires the user to confirm installation.

## Docker build

```bash
docker build -f Dockerfile.android -t otclient-android .
docker create --name otc-build otclient-android
docker cp otc-build:/app-release.apk ./app-release.apk
docker rm otc-build
```

## Supported ABIs

| ABI | Device type | LuaJIT host flag |
|-----|------------|------------------|
| arm64-v8a | Modern phones/tablets (95%+ of market) | `gcc` |
| armeabi-v7a | Older 32-bit ARM devices | `gcc -m32` |
| x86_64 | Chromebooks, emulators | `gcc` |
| x86 | Older emulators | `gcc -m32` |

## Troubleshooting

### Black screen on launch
- Ensure `data.zip` is in `android/app/src/main/assets/`. Run `bash setup_android_deps.sh` or generate it manually.

### `assertion "hasIndex(-n)" failed` crash
- LuaJIT was compiled without `-DLUAJIT_UNWIND_EXTERNAL` or with wrong pointer size. Re-run `build_luajit_android.sh`.

### `Unsupported target architecture` in vcpkg
- This is expected — vcpkg cannot build LuaJIT for Android. That's why we build it separately. The `vcpkg.json` excludes LuaJIT from Android.

### 32-bit build fails with `gcc -m32`
- Install `gcc-multilib`: `sudo apt install gcc-multilib g++-multilib`

## Elemental test channel

Build the test client with its own package ID and a release signature. Use a
new immutable version name and an increasing test `versionCode` for every APK:

```bash
export ELEMENTAL_ANDROID_CHANNEL=test
export ELEMENTAL_TEST_LOGIN_URL="https://test-game.elementalmmo.com.br/beta/v1/login"
export ELEMENTAL_ANDROID_MANIFEST_URL="https://test-feed.elementalmmo.com.br/updates/test/android-manifest.json"
export ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL="https://test-feed.elementalmmo.com.br/updates/test/client-assets-manifest.json"
export ELEMENTAL_TEST_AUTH_URL="https://test-feed.elementalmmo.com.br/distribution/v1/enroll"
export ELEMENTAL_ANDROID_VERSION_CODE=20261032
export ELEMENTAL_ANDROID_VERSION_NAME=2026.10.23-test.1
export OTCLIENT_ANDROID_ABIS=arm64-v8a
bash setup_android_deps.sh
cd android && bash gradlew :app:assembleRelease
```

The result uses `br.com.elementalmmo.client.test`. It downloads the APK and
incremental client assets only after the tester enrolls this installation with
the protected feed; the shared enrollment password is never embedded in the
APK. Test sign-in credentials are typed in the client by each tester.

## Elemental closed beta

The beta build defaults to channel `beta`, package ID
`br.com.elementalmmo.client`, version `0.5.0-beta.1`, version code `1`, and
ABI `arm64-v8a`. The channel-aware bundle builder keeps `test` and `beta`
logins on an HTTPS `/beta/v1/login` endpoint and removes the optional HTTP test
override from the packaged `init.lua`. For test, the defaults use protected
manifests and enrollment from `test-feed.elementalmmo.com.br`, while the
selected game server remains `test-game.elementalmmo.com.br`. The enrollment
password is entered by the tester and never embedded in the APK.

```bash
export ELEMENTAL_ANDROID_CHANNEL=beta
export ELEMENTAL_ANDROID_VERSION_CODE=1
export ELEMENTAL_ANDROID_VERSION_NAME=0.5.0-beta.1
export OTCLIENT_ANDROID_ABIS=arm64-v8a
export ELEMENTAL_BETA_LOGIN_URL=https://localhost:18443/beta/v1/login
# Set only for the private technical candidate under D047:
export ELEMENTAL_INCLUDE_LOCAL_DEVELOPMENT_1525_ASSETS=1
bash setup_android_deps.sh
```

The beta packager accepts optional `ELEMENTAL_ANDROID_MANIFEST_URL` and
`ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL` values together. Remote URLs must use
HTTPS; HTTP is limited to loopback development. The test-feed enrollment URL
is rejected on beta/release channels.

For a local phone test through USB, configure the isolated endpoint and use
`adb reverse` for its ports; `localhost` on Android otherwise means the phone
itself. Install only on a secondary device or isolated emulator where the main
Elemental app is not installed. Do not replace the project owner's app/profile.

The community 15.25 pack is included only when
`ELEMENTAL_INCLUDE_LOCAL_DEVELOPMENT_1525_ASSETS=1` is explicitly set. D047
allows that pack only for Desenvolvedores invited during closed development; it
does not approve a public beta. D080 authorizes the closed test cohort only;
it does not approve open beta or release and does not mark T5.7/T5.19 complete.

Keep signing keystores outside Git and load passwords from protected local
storage. Use alias `elemental-test` for the test package and preserve its key
for all test updates; use alias `elemental-beta` for the shared beta/release
package identity. Do not add APKs to Git. Prepare and verify the local
source-bound manifest through T5.14 before treating an APK as a candidate. A
successful local build does not pass the device or gameplay checks in
T5.7.4/T5.18.
