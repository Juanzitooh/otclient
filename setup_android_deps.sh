#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
android_ndk=${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to the local Android NDK}
vcpkg_root=${VCPKG_ROOT:?Set VCPKG_ROOT to the local vcpkg checkout}
login_url=${ELEMENTAL_BETA_LOGIN_URL:?Set ELEMENTAL_BETA_LOGIN_URL to an isolated HTTPS /beta/v1/login endpoint}
requested_abis=${OTCLIENT_ANDROID_ABIS:-arm64-v8a}

ANDROID_NDK_HOME="$android_ndk" OTCLIENT_ANDROID_ABIS="$requested_abis" \
    bash "$project_root/build_luajit_android.sh"

IFS=',' read -r -a abi_list <<< "$requested_abis"
for abi in "${abi_list[@]}"; do
    case "$abi" in
        arm64-v8a) triplet=arm64-android ;;
        armeabi-v7a) triplet=arm-neon-android ;;
        x86_64) triplet=x64-android ;;
        x86) triplet=x86-android ;;
        *) echo "Unsupported Android ABI: $abi" >&2; exit 2 ;;
    esac
    (cd "$project_root" && "$vcpkg_root/vcpkg" install \
        --triplet "$triplet" --x-manifest-root=. --allow-unsupported)
done

bundle_args=(--login-url "$login_url")
if [[ "${ELEMENTAL_INCLUDE_LOCAL_DEVELOPMENT_1525_ASSETS:-0}" == 1 ]]; then
    bundle_args+=(--include-local-development-1525-assets)
fi
python3 "$project_root/android/build_elemental_bundle.py" "${bundle_args[@]}"
