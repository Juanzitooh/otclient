#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
android_ndk=${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to the local Android NDK}
vcpkg_root=${VCPKG_ROOT:?Set VCPKG_ROOT to the local vcpkg checkout}
channel=${ELEMENTAL_ANDROID_CHANNEL:-beta}
requested_abis=${OTCLIENT_ANDROID_ABIS:-arm64-v8a}

case "$channel" in
    test) : "${ELEMENTAL_TEST_LOGIN_URL:?Set ELEMENTAL_TEST_LOGIN_URL to an HTTPS /beta/v1/login endpoint}" ;;
    beta) : "${ELEMENTAL_BETA_LOGIN_URL:?Set ELEMENTAL_BETA_LOGIN_URL to an isolated HTTPS /beta/v1/login endpoint}" ;;
    release) ;;
    *) echo "ELEMENTAL_ANDROID_CHANNEL must be test, beta, or release." >&2; exit 2 ;;
esac

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

case "$channel" in
    test|beta)
        if [[ "$channel" == "test" ]]; then
            login_url=${ELEMENTAL_TEST_LOGIN_URL:?Set ELEMENTAL_TEST_LOGIN_URL to an HTTPS /beta/v1/login endpoint}
            if [[ "${ELEMENTAL_INCLUDE_LOCAL_DEVELOPMENT_1525_ASSETS:-0}" == 1 ]]; then
                echo "Community 15.25 assets are limited to the beta development bundle." >&2
                exit 2
            fi
        else
            login_url=${ELEMENTAL_BETA_LOGIN_URL:?Set ELEMENTAL_BETA_LOGIN_URL to an isolated HTTPS /beta/v1/login endpoint}
        fi
        bundle_args=(
            --login-url "$login_url"
            --channel "$channel"
            --android-manifest-url "${ELEMENTAL_ANDROID_MANIFEST_URL:-}"
            --client-assets-manifest-url "${ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL:-}"
            --test-auth-url "${ELEMENTAL_TEST_AUTH_URL:-}"
        )
        if [[ "$channel" == "beta" && "${ELEMENTAL_INCLUDE_LOCAL_DEVELOPMENT_1525_ASSETS:-0}" == 1 ]]; then
            bundle_args+=(--include-local-development-1525-assets)
        fi
        python3 "$project_root/android/build_elemental_bundle.py" "${bundle_args[@]}"
        ;;
    release)
        if [[ "${ELEMENTAL_INCLUDE_LOCAL_DEVELOPMENT_1525_ASSETS:-0}" == 1 ]]; then
            echo "Community 15.25 assets are limited to the beta development bundle." >&2
            exit 2
        fi
        python3 "$project_root/scripts/package_android_data.py" \
            --channel "$channel" \
            --android-manifest-url "${ELEMENTAL_ANDROID_MANIFEST_URL:-}" \
            --client-assets-manifest-url "${ELEMENTAL_CLIENT_ASSETS_MANIFEST_URL:-}" \
            --test-auth-url "${ELEMENTAL_TEST_AUTH_URL:-}"
        ;;
    *)
        echo "ELEMENTAL_ANDROID_CHANNEL must be test, beta, or release." >&2
        exit 2
        ;;
esac
