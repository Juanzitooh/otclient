#!/usr/bin/env bash
set -Eeuo pipefail

# Do not let an inherited `bash -x` print the local signing secret while sourcing it.
set +x

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_DIR="${ELEMENTAL_TEST_SIGNING_DIR:-${HOME}/.local/share/elemental-test/signing}"
SIGNING_ENV="${ELEMENTAL_TEST_SIGNING_ENV:-${SIGNING_DIR}/passwords.env}"
KEYSTORE="${ELEMENTAL_TEST_KEYSTORE:-${SIGNING_DIR}/elemental-test.jks}"
BASELINE_APK="${ELEMENTAL_TEST_BASELINE_APK:-/srv/elemental-feed/current/test/downloads/elemental.apk}"
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${HOME}/Android/Sdk}}"
UI_FILE="modules/client_distribution_auth/test_feed_access.otui"
APK="${ROOT}/android/app/build/outputs/apk/release/app-release.apk"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$SDK_ROOT}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${SDK_ROOT}/ndk/29.0.13599879}"

if [[ ! -f "$SIGNING_ENV" || -L "$SIGNING_ENV" ]]; then
    printf 'Signing password file is missing or is a symlink: %s\n' "$SIGNING_ENV" >&2
    exit 2
fi
if [[ "$(stat -c '%u' "$SIGNING_ENV")" != "$(id -u)" ]]; then
    echo "Signing password file must be owned by the current user." >&2
    exit 2
fi
SIGNING_MODE="$(stat -c '%a' "$SIGNING_ENV")"
if (( (8#${SIGNING_MODE} & 077) != 0 )); then
    echo "Signing password file must not be readable by group or others (use chmod 600)." >&2
    exit 2
fi
if [[ ! -f "$KEYSTORE" || -L "$KEYSTORE" ]]; then
    printf 'Elemental test keystore is missing or is a symlink: %s\n' "$KEYSTORE" >&2
    exit 2
fi
if [[ "$(stat -c '%u' "$KEYSTORE")" != "$(id -u)" ]]; then
    echo "Elemental test keystore must be owned by the current user." >&2
    exit 2
fi
KEYSTORE_MODE="$(stat -c '%a' "$KEYSTORE")"
if (( (8#${KEYSTORE_MODE} & 077) != 0 )); then
    echo "Elemental test keystore must not be readable by group or others (use chmod 600)." >&2
    exit 2
fi

# This local file contains only signing material and is never copied into the APK.
set -a
source "$SIGNING_ENV"
set +a
if [[ -z "${ELEMENTAL_TEST_KEYSTORE_PASSWORD:-}" ]]; then
    echo "Signing password file must define ELEMENTAL_TEST_KEYSTORE_PASSWORD." >&2
    exit 2
fi

export RELEASE_KEYSTORE="$KEYSTORE"
export RELEASE_KEYSTORE_PASSWORD="$ELEMENTAL_TEST_KEYSTORE_PASSWORD"
export RELEASE_KEY_ALIAS="elemental-test"
export RELEASE_KEY_PASSWORD="${ELEMENTAL_TEST_KEY_PASSWORD:-$ELEMENTAL_TEST_KEYSTORE_PASSWORD}"

release_version="${ELEMENTAL_TEST_RELEASE_VERSION:-${ELEMENTAL_ANDROID_VERSION_NAME:-}}"
if [[ ! "$release_version" =~ ^20[0-9]{2}\.[0-9]{2}\.[0-9]{2}-test\.[1-9][0-9]*$ ]]; then
    echo "Set ELEMENTAL_TEST_RELEASE_VERSION to a new immutable version, for example 2026.10.28-test.1." >&2
    exit 2
fi

export ELEMENTAL_ANDROID_CHANNEL="test"
export ELEMENTAL_ANDROID_VERSION_NAME="$release_version"
export ELEMENTAL_TEST_LOGIN_URL="${ELEMENTAL_TEST_LOGIN_URL:-https://test-game.elementalmmo.com.br/beta/v1/login}"
export ELEMENTAL_ANDROID_MANIFEST_URL="${ELEMENTAL_ANDROID_MANIFEST_URL:-https://test-feed.elementalmmo.com.br/updates/test/android-manifest.json}"
export ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL="${ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL:-https://test-feed.elementalmmo.com.br/updates/test/client-assets-manifest.json}"
export ELEMENTAL_TEST_AUTH_URL="${ELEMENTAL_TEST_AUTH_URL:-https://test-feed.elementalmmo.com.br/distribution/v1/enroll}"
export OTCLIENT_ANDROID_ABIS="${OTCLIENT_ANDROID_ABIS:-arm64-v8a}"
VERSION_STATE_FILE="${ELEMENTAL_TEST_VERSION_STATE_FILE:-$ROOT/../.local-artifacts/elemental-test/version-sequence.json}"

if [[ ! -f "$BASELINE_APK" ]]; then
    printf 'Cannot compare the update signature; baseline test APK is missing: %s\n' "$BASELINE_APK" >&2
    exit 2
fi

APKSIGNER="$(find "$SDK_ROOT/build-tools" -mindepth 2 -maxdepth 2 -type f -name apksigner -print 2>/dev/null | sort -V | tail -n 1)"
AAPT="$(find "$SDK_ROOT/build-tools" -mindepth 2 -maxdepth 2 -type f -name aapt -print 2>/dev/null | sort -V | tail -n 1)"
if [[ -z "$APKSIGNER" || -z "$AAPT" ]]; then
    echo "Android SDK apksigner and aapt are required for release verification." >&2
    exit 2
fi

baseline_certificate="$("$APKSIGNER" verify --print-certs "$BASELINE_APK" 2>/dev/null | awk -F': ' '/certificate SHA-256 digest:/ {print tolower($2); exit}')"
if [[ -z "$baseline_certificate" ]]; then
    echo "Could not read the baseline APK signing certificate." >&2
    exit 2
fi
baseline_metadata="$("$AAPT" dump badging "$BASELINE_APK" | sed -n '1p')"
baseline_package="$(sed -n "s/.*package: name='\([^']*\)'.*/\1/p" <<< "$baseline_metadata")"
baseline_code="$(sed -n "s/.*versionCode='\([0-9][0-9]*\)'.*/\1/p" <<< "$baseline_metadata")"
if [[ "$baseline_package" != "br.com.elementalmmo.client.test" ]]; then
    printf 'Unexpected baseline APK package id: %s\n' "$baseline_package" >&2
    exit 2
fi
if [[ -z "$baseline_code" ]]; then
    echo "Could not read the baseline APK versionCode." >&2
    exit 2
fi

state_code="$(python3 - "$VERSION_STATE_FILE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    print(0)
    raise SystemExit(0)
try:
    state = json.loads(path.read_text(encoding="utf-8"))
    value = state.get("lastAndroidVersionCode", 0)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError
except (OSError, ValueError, json.JSONDecodeError):
    raise SystemExit("Android version state is invalid; preserve it and resolve manually.")
print(value)
PY
)"
highest_code="$baseline_code"
if (( state_code > highest_code )); then highest_code="$state_code"; fi
if [[ -n "${ELEMENTAL_ANDROID_VERSION_CODE:-}" ]]; then
    release_code_requested="$ELEMENTAL_ANDROID_VERSION_CODE"
    if [[ ! "$release_code_requested" =~ ^[1-9][0-9]*$ ]] || (( release_code_requested <= highest_code )); then
        printf 'APK versionCode must exceed both the feed and local build history (highest=%s, requested=%s).\n' \
            "$highest_code" "$release_code_requested" >&2
        exit 2
    fi
else
    ELEMENTAL_ANDROID_VERSION_CODE="$((highest_code + 1))"
fi
export ELEMENTAL_ANDROID_VERSION_CODE

cd "$ROOT"
intent_to_add=0
if ! git ls-files --error-unmatch -- "$UI_FILE" >/dev/null 2>&1 \
    && [[ "$(git status --short -- "$UI_FILE")" == "?? ${UI_FILE}" ]]; then
    git add -N -- "$UI_FILE"
    intent_to_add=1
fi
cleanup() {
    if (( intent_to_add )); then
        git reset -q -- "$UI_FILE"
    fi
}
trap cleanup EXIT

python3 android/build_elemental_bundle.py \
    --channel test \
    --login-url "$ELEMENTAL_TEST_LOGIN_URL" \
    --android-manifest-url "$ELEMENTAL_ANDROID_MANIFEST_URL" \
    --client-assets-manifest-url "$ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL" \
    --test-auth-url "$ELEMENTAL_TEST_AUTH_URL"

python3 - "$ROOT/android/app/src/main/assets/data.zip" "$UI_FILE" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as bundle:
    if sys.argv[2] not in bundle.namelist():
        raise SystemExit("The branded Android feed gate is missing from data.zip")
PY

rm -f "$APK"
cd "$ROOT/android"
bash ./gradlew --offline --no-daemon --max-workers=2 assembleRelease

if [[ ! -f "$APK" ]]; then
    echo "Gradle completed without producing the release APK." >&2
    exit 2
fi

release_certificate="$("$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | awk -F': ' '/certificate SHA-256 digest:/ {print tolower($2); exit}')"
if [[ "$release_certificate" != "$baseline_certificate" ]]; then
    echo "Release APK signature does not match the currently served test APK; refusing to approve it as an update." >&2
    exit 2
fi

release_metadata="$("$AAPT" dump badging "$APK" | sed -n '1p')"
release_code="$(sed -n "s/.*versionCode='\([0-9][0-9]*\)'.*/\1/p" <<< "$release_metadata")"
release_package="$(sed -n "s/.*package: name='\([^']*\)'.*/\1/p" <<< "$release_metadata")"
if [[ "$release_package" != "br.com.elementalmmo.client.test" ]]; then
    printf 'Unexpected APK package id: %s\n' "$release_package" >&2
    exit 2
fi
if [[ -z "$baseline_code" || -z "$release_code" || "$release_code" -le "$baseline_code" ]]; then
    printf 'APK versionCode must increase beyond the baseline (baseline=%s, release=%s).\n' \
        "${baseline_code:-unknown}" "${release_code:-unknown}" >&2
    exit 2
fi

if ! "$APKSIGNER" verify "$APK" >/dev/null 2>&1; then
    echo "APK signature verification failed." >&2
    exit 2
fi
python3 - "$VERSION_STATE_FILE" "$release_version" "$release_code" <<'PY'
import json
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
version_code = int(sys.argv[3])
state = {}
if path.exists():
    state = json.loads(path.read_text(encoding="utf-8"))
previous_code = state.get("lastAndroidVersionCode", 0)
if isinstance(previous_code, bool) or not isinstance(previous_code, int):
    raise SystemExit("Android version state is invalid; refusing to overwrite it.")
if version_code <= previous_code:
    raise SystemExit("The generated APK versionCode did not advance the local sequence.")
state.update({"lastReleaseVersion": version, "lastAndroidVersionCode": version_code})
path.parent.mkdir(parents=True, exist_ok=True)
fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as target:
        json.dump(state, target, sort_keys=True)
        target.write("\n")
        target.flush()
        os.fsync(target.fileno())
    os.chmod(temporary_name, 0o600)
    os.replace(temporary_name, path)
finally:
    if os.path.exists(temporary_name):
        os.unlink(temporary_name)
PY
printf 'Verified test APK: %s\n' "$APK"
printf 'Version: %s (code %s), package: %s\n' "$ELEMENTAL_ANDROID_VERSION_NAME" "$release_code" "$release_package"
printf 'Signer SHA-256: %s\n' "$release_certificate"
sha256sum "$APK"
echo "This script builds and verifies locally; it does not install or publish the APK."
