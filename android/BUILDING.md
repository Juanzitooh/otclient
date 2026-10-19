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

For a channel-specific APK, set both manifest URLs before packaging. If they
are empty, the Android APK updater and client-assets updater stay disabled.
Android builds are tied to one channel; create separate test, beta, and release
APKs when those feeds are enabled.

```bash
export ELEMENTAL_ANDROID_CHANNEL=test
export ELEMENTAL_ANDROID_MANIFEST_URL="https://feed.example/test/android-manifest.json"
export ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL="https://feed.example/test/client-assets-manifest.json"
export ELEMENTAL_ANDROID_VERSION_CODE=42
export ELEMENTAL_ANDROID_VERSION_NAME=2026.10.19-test.1

# 1. Run the setup script (builds LuaJIT, installs vcpkg deps, generates data.zip)
./setup_android_deps.sh

# 2. Build the APK
cd android
chmod +x gradlew
./gradlew assembleRelease
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

```bash
# Rebuild data.zip when a channel or endpoint changes.
python3 scripts/package_android_data.py \
  --channel "$ELEMENTAL_ANDROID_CHANNEL" \
  --android-manifest-url "$ELEMENTAL_ANDROID_MANIFEST_URL" \
  --client-assets-manifest-url "$ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL"
```

The bundle embeds those values in `elemental-distribution.lua`. Keep URLs on
the same channel as the APK and use HTTPS for collaborator devices. HTTP is
accepted only for loopback development fixtures. The output contains the
complete `data`, `mods`, and `modules` trees; do not reuse a stale `data.zip`
when changing channels.

### Step 3: Build with Gradle

```bash
cd android
chmod +x gradlew
./gradlew assembleRelease    # or assembleDebug
```

### Step 4: Install on device

```bash
adb install android/app/build/outputs/apk/release/app-release.apk
```

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
- Ensure `data.zip` is in `android/app/src/main/assets/`. Run `setup_android_deps.sh` or generate it manually.

### `assertion "hasIndex(-n)" failed` crash
- LuaJIT was compiled without `-DLUAJIT_UNWIND_EXTERNAL` or with wrong pointer size. Re-run `build_luajit_android.sh`.

### `Unsupported target architecture` in vcpkg
- This is expected — vcpkg cannot build LuaJIT for Android. That's why we build it separately. The `vcpkg.json` excludes LuaJIT from Android.

### 32-bit build fails with `gcc -m32`
- Install `gcc-multilib`: `sudo apt install gcc-multilib g++-multilib`
