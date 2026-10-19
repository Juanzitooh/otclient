#!/bin/bash
set -euo pipefail

ANDROID_HOME=/home/dev/android-sdk
VCPKG_ROOT=/home/dev/vcpkg
PROJECT_DIR=/home/dev/kizu-otc

mkdir -p "$ANDROID_HOME"

# Install commandline-tools if missing
if [ ! -f "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    echo "Downloading Android commandline-tools..."
    cd /tmp
    curl -sL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o cmdtools.zip
    unzip -qo cmdtools.zip -d "$ANDROID_HOME/cmdline-tools-tmp"
    mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
    mv "$ANDROID_HOME/cmdline-tools-tmp/cmdline-tools/"* "$ANDROID_HOME/cmdline-tools/latest/"
    rm -rf "$ANDROID_HOME/cmdline-tools-tmp" cmdtools.zip
    echo "commandline-tools installed."
else
    echo "cmdline-tools already present."
fi

# Install NDK, platform, build-tools
echo "Installing SDK components..."
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" \
    "ndk;29.0.13599879" \
    "platforms;android-36" \
    "build-tools;35.0.0" \
    2>&1 | tail -5

echo "NDK:" && ls "$ANDROID_HOME/ndk/"

# Set environment
export ANDROID_HOME="$ANDROID_HOME"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/29.0.13599879"
export VCPKG_ROOT="$VCPKG_ROOT"

# Build
echo "=== Starting Gradle build ==="
cd "$PROJECT_DIR/android"

# Package channel-specific updater URLs every time so the APK cannot retain a
# stale channel configuration from an older data.zip.
python3 "$PROJECT_DIR/scripts/package_android_data.py" \
    --channel "${ELEMENTAL_ANDROID_CHANNEL:-test}" \
    --android-manifest-url "${ELEMENTAL_ANDROID_MANIFEST_URL:-}" \
    --client-assets-manifest-url "${ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL:-}"

cd "$PROJECT_DIR/android"
chmod +x gradlew
./gradlew assembleRelease 2>&1

echo "=== BUILD COMPLETE ==="
ls -lh "$PROJECT_DIR/android/app/build/outputs/apk/release/"
