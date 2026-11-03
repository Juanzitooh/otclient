/*
 * Copyright (c) 2010-2014 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#ifdef ANDROID

#include "androidmanager.h"
#include <framework/global.h>
#include <framework/core/unzipper.h>
#include <framework/core/resourcemanager.h>
#include <framework/platform/platform.h>
#include <framework/sound/soundmanager.h>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
#include <set>
#include <vector>

AndroidManager g_androidManager;

namespace {
    bool isSafeBootstrapRelativePath(const std::filesystem::path& path) {
        if (path.empty() || path.is_absolute() || path.has_root_path())
            return false;

        for (const auto& part : path) {
            if (part == "." || part == "..")
                return false;
        }
        return true;
    }

    bool isRuntimeManagedAssetPath(const std::filesystem::path& path) {
        auto part = path.begin();
        if (part == path.end() || *part != "data")
            return false;

        ++part;
        return part != path.end() && (*part == "things" || *part == "sounds");
    }

    bool reconcileBootstrapFiles(
            const std::filesystem::path& destinationPath,
            const std::set<std::string>& previousFiles,
            const std::set<std::string>& currentFiles,
            const bool hasPreviousInventory,
            std::string& errorMessage) {
        const auto removeStaleFile = [&](const std::filesystem::path& relativePath) {
            if (!isSafeBootstrapRelativePath(relativePath)) {
                errorMessage = "Invalid path in Android bootstrap inventory: " + relativePath.string();
                return false;
            }
            if (isRuntimeManagedAssetPath(relativePath))
                return true;

            std::error_code filesystemError;
            if (!std::filesystem::remove(destinationPath / relativePath, filesystemError) && filesystemError) {
                errorMessage = "Unable to remove stale Android bootstrap file " + relativePath.string() +
                        ": " + filesystemError.message();
                return false;
            }
            return true;
        };

        if (hasPreviousInventory) {
            for (const auto& previousFile : previousFiles) {
                if (currentFiles.find(previousFile) == currentFiles.end() &&
                        !removeStaleFile(previousFile))
                    return false;
            }
            return true;
        }

        for (const auto* directoryName : { "modules", "mods" }) {
            const auto directory = destinationPath / directoryName;
            std::error_code filesystemError;
            if (!std::filesystem::exists(directory, filesystemError)) {
                if (filesystemError) {
                    errorMessage = std::string("Unable to inspect Android bootstrap directory ") + directoryName +
                            ": " + filesystemError.message();
                    return false;
                }
                continue;
            }

            std::filesystem::recursive_directory_iterator iterator(directory, filesystemError);
            const std::filesystem::recursive_directory_iterator end;
            while (!filesystemError && iterator != end) {
                const auto entry = *iterator;
                if (entry.is_regular_file(filesystemError) && entry.path().extension() == ".otmod") {
                    const auto relativePath = entry.path().lexically_relative(destinationPath);
                    const auto relativeName = relativePath.generic_string();
                    if (currentFiles.find(relativeName) == currentFiles.end() &&
                            !removeStaleFile(relativePath))
                        return false;
                }
                iterator.increment(filesystemError);
            }
            if (filesystemError) {
                errorMessage = std::string("Unable to inspect Android bootstrap directory ") + directoryName +
                        ": " + filesystemError.message();
                return false;
            }
        }
        return true;
    }

    bool writeBootstrapInventory(
            const std::filesystem::path& inventoryPath,
            const std::set<std::string>& files,
            std::string& errorMessage) {
        const auto temporaryPath = inventoryPath.string() + ".tmp";
        {
            std::ofstream inventoryFile(temporaryPath, std::ios::binary | std::ios::trunc);
            for (const auto& file : files)
                inventoryFile << file << '\n';
            if (!inventoryFile) {
                errorMessage = "Unable to write Android bootstrap inventory.";
                return false;
            }
        }

        std::error_code filesystemError;
        std::filesystem::rename(temporaryPath, inventoryPath, filesystemError);
        if (filesystemError) {
            errorMessage = "Unable to activate Android bootstrap inventory: " + filesystemError.message();
            return false;
        }
        return true;
    }
}

AndroidManager::~AndroidManager() {
    if (m_app && m_app->activity && m_app->activity->vm && m_androidManagerJObject) {
        JNIEnv* env = nullptr;
        if (m_app->activity->vm->AttachCurrentThread(&env, nullptr) == 0 && env) {
            env->DeleteGlobalRef(m_androidManagerJObject);
            m_androidManagerJObject = nullptr;
        }
    }
}

void AndroidManager::setAndroidApp(android_app* app) {
    m_app = app;
}

void AndroidManager::setAndroidManager(JNIEnv* env, jobject androidManager) {
    JNIEnv* jniEnv = getJNIEnv();
    jclass androidManagerJClass = jniEnv->GetObjectClass(androidManager);
    m_androidManagerJObject = jniEnv->NewGlobalRef(androidManager);
    m_midShowSoftKeyboard = jniEnv->GetMethodID(androidManagerJClass, "showSoftKeyboard", "()V");
    m_midHideSoftKeyboard = jniEnv->GetMethodID(androidManagerJClass, "hideSoftKeyboard", "()V");
    m_midHideStartupSplash = jniEnv->GetMethodID(androidManagerJClass, "hideStartupSplash", "()V");
    m_midGetDisplayDensity = jniEnv->GetMethodID(androidManagerJClass, "getDisplayDensity", "()F");
    m_midShowInputPreview = jniEnv->GetMethodID(androidManagerJClass, "showInputPreview", "(Ljava/lang/String;IIII)V");
    m_midUpdateInputPreview = jniEnv->GetMethodID(androidManagerJClass, "updateInputPreview", "(Ljava/lang/String;)V");
    m_midHideInputPreview = jniEnv->GetMethodID(androidManagerJClass, "hideInputPreview", "()V");
    m_midGetClipboardText = jniEnv->GetMethodID(androidManagerJClass, "getClipboardText", "()Ljava/lang/String;");
    m_midSetClipboardText = jniEnv->GetMethodID(androidManagerJClass, "setClipboardText", "(Ljava/lang/String;)V");
    m_midGetPackageName = jniEnv->GetMethodID(androidManagerJClass, "getPackageName", "()Ljava/lang/String;");
    m_midGetVersionCode = jniEnv->GetMethodID(androidManagerJClass, "getVersionCode", "()I");
    m_midUpdateAssetDownloadNotification = jniEnv->GetMethodID(androidManagerJClass, "updateAssetDownloadNotification", "(Ljava/lang/String;ILjava/lang/String;)V");
    m_midFinishAssetDownloadNotification = jniEnv->GetMethodID(androidManagerJClass, "finishAssetDownloadNotification", "()V");
    m_midGetFileSize = jniEnv->GetMethodID(androidManagerJClass, "getFileSize", "(Ljava/lang/String;)J");
    m_midSha256File = jniEnv->GetMethodID(androidManagerJClass, "sha256File", "(Ljava/lang/String;)Ljava/lang/String;");
    m_midInstallApk = jniEnv->GetMethodID(androidManagerJClass, "installApk", "(Ljava/lang/String;)I");
    jniEnv->DeleteLocalRef(androidManagerJClass);
}

void AndroidManager::showKeyboardSoft() {
    JNIEnv* env = getJNIEnv();
    env->CallVoidMethod(m_androidManagerJObject, m_midShowSoftKeyboard);
}

void AndroidManager::hideKeyboard() {
    JNIEnv* env = getJNIEnv();
    env->CallVoidMethod(m_androidManagerJObject, m_midHideSoftKeyboard);
}

void AndroidManager::hideStartupSplash() {
    JNIEnv* env = getJNIEnv();
    env->CallVoidMethod(m_androidManagerJObject, m_midHideStartupSplash);
}

namespace {
    jstring latin1ToJString(JNIEnv* env, const std::string& text) {
        std::u16string utf16;
        utf16.reserve(text.size());
        for (unsigned char c : text) {
            utf16.push_back(static_cast<char16_t>(c));
        }
        return env->NewString(reinterpret_cast<const jchar*>(utf16.data()), static_cast<jsize>(utf16.size()));
    }
}

void AndroidManager::showInputPreview(const std::string& text, int widgetX, int widgetY, int widgetW, int widgetH) {
    JNIEnv* env = getJNIEnv();
    jstring jText = latin1ToJString(env, text);
    env->CallVoidMethod(m_androidManagerJObject, m_midShowInputPreview, jText, (jint)widgetX, (jint)widgetY, (jint)widgetW, (jint)widgetH);
    env->DeleteLocalRef(jText);
}

void AndroidManager::updateInputPreview(const std::string& text) {
    JNIEnv* env = getJNIEnv();
    jstring jText = latin1ToJString(env, text);
    env->CallVoidMethod(m_androidManagerJObject, m_midUpdateInputPreview, jText);
    env->DeleteLocalRef(jText);
}

void AndroidManager::hideInputPreview() {
    JNIEnv* env = getJNIEnv();
    env->CallVoidMethod(m_androidManagerJObject, m_midHideInputPreview);
}

void AndroidManager::updateAssetDownloadNotification(const std::string& status, int progress, const std::string& detail) {
    JNIEnv* env = getJNIEnv();
    jstring jStatus = latin1ToJString(env, status);
    jstring jDetail = latin1ToJString(env, detail);
    env->CallVoidMethod(m_androidManagerJObject, m_midUpdateAssetDownloadNotification, jStatus, static_cast<jint>(progress), jDetail);
    env->DeleteLocalRef(jStatus);
    env->DeleteLocalRef(jDetail);
}

void AndroidManager::finishAssetDownloadNotification() {
    JNIEnv* env = getJNIEnv();
    env->CallVoidMethod(m_androidManagerJObject, m_midFinishAssetDownloadNotification);
}

std::string AndroidManager::getClipboardText() {
    JNIEnv* env = getJNIEnv();
    auto jText = (jstring) env->CallObjectMethod(m_androidManagerJObject, m_midGetClipboardText);
    if (!jText) return "";
    std::string result = getStringFromJString(jText);
    env->DeleteLocalRef(jText);
    return result;
}

void AndroidManager::setClipboardText(const std::string& text) {
    JNIEnv* env = getJNIEnv();
    jstring jText = latin1ToJString(env, text);
    env->CallVoidMethod(m_androidManagerJObject, m_midSetClipboardText, jText);
    env->DeleteLocalRef(jText);
}

std::string AndroidManager::getPackageName() {
    JNIEnv* env = getJNIEnv();
    auto packageName = static_cast<jstring>(env->CallObjectMethod(m_androidManagerJObject, m_midGetPackageName));
    if (!packageName)
        return {};
    std::string result = getStringFromJString(packageName);
    env->DeleteLocalRef(packageName);
    return result;
}

int AndroidManager::getVersionCode() {
    JNIEnv* env = getJNIEnv();
    return env->CallIntMethod(m_androidManagerJObject, m_midGetVersionCode);
}

std::int64_t AndroidManager::getFileSize(const std::string& path) {
    JNIEnv* env = getJNIEnv();
    jstring jPath = latin1ToJString(env, path);
    const auto fileSize = env->CallLongMethod(m_androidManagerJObject, m_midGetFileSize, jPath);
    env->DeleteLocalRef(jPath);
    return fileSize;
}

std::string AndroidManager::sha256File(const std::string& path) {
    JNIEnv* env = getJNIEnv();
    jstring jPath = latin1ToJString(env, path);
    auto hash = static_cast<jstring>(env->CallObjectMethod(m_androidManagerJObject, m_midSha256File, jPath));
    env->DeleteLocalRef(jPath);
    if (!hash)
        return {};
    std::string result = getStringFromJString(hash);
    env->DeleteLocalRef(hash);
    return result;
}

int AndroidManager::installApk(const std::string& path) {
    JNIEnv* env = getJNIEnv();
    jstring jPath = latin1ToJString(env, path);
    const int result = env->CallIntMethod(m_androidManagerJObject, m_midInstallApk, jPath);
    env->DeleteLocalRef(jPath);
    return result;
}

void AndroidManager::unZipAssetData() {
    std::string destFolder = getAppBaseDir() + "/game_data/";
    const std::filesystem::path destinationPath { destFolder };
    const std::filesystem::path initLua = destinationPath / "init.lua";
    const std::filesystem::path versionMarker = destinationPath / ".elemental-bootstrap-version";
    const std::filesystem::path inventoryPath = destinationPath / ".elemental-bootstrap-files";
    const std::string version = std::to_string(getVersionCode());
    std::string extractedVersion;
    {
        std::ifstream markerFile(versionMarker, std::ios::binary);
        std::getline(markerFile, extractedVersion);
    }

    const auto updateDistributionConfig = [&]() {
        AAsset* configAsset = AAssetManager_open(
                m_app->activity->assetManager,
                "elemental-distribution.lua",
                AASSET_MODE_BUFFER);
        if (!configAsset)
            return;

        const auto configLength = AAsset_getLength(configAsset);
        if (configLength <= 0 || configLength > 16 * 1024) {
            g_logger.error("Invalid Android distribution config size: {}", configLength);
            AAsset_close(configAsset);
            return;
        }

        std::string configContent(static_cast<size_t>(configLength), '\0');
        size_t bytesRead = 0;
        while (bytesRead < configContent.size()) {
            const auto count = AAsset_read(
                    configAsset,
                    configContent.data() + bytesRead,
                    configContent.size() - bytesRead);
            if (count <= 0) {
                g_logger.error("Unable to read Android distribution config asset.");
                AAsset_close(configAsset);
                return;
            }
            bytesRead += static_cast<size_t>(count);
        }
        AAsset_close(configAsset);

        std::ofstream configFile(destFolder + "elemental-distribution.lua", std::ios::binary | std::ios::trunc);
        if (!configFile || !configFile.write(
                    configContent.data(),
                    static_cast<std::streamsize>(configContent.size())))
            g_logger.error("Unable to write Android distribution config.");
    };

    if (std::filesystem::exists(initLua) && extractedVersion == version) {
        updateDistributionConfig();
        return;
    }

    AAsset* dataAsset = AAssetManager_open(
            m_app->activity->assetManager,
            "data.zip",
            AASSET_MODE_BUFFER);

    if (!dataAsset) {
        g_logger.fatal("Failed to open data.zip from APK assets. Run setup_android_deps.sh to generate it.");
        return;
    }

    const auto dataFileLength = AAsset_getLength(dataAsset);
    if (dataFileLength <= 0 ||
            static_cast<uint64_t>(dataFileLength) >
                    static_cast<uint64_t>(std::numeric_limits<uint>::max())) {
        g_logger.fatal("Invalid data.zip size in APK assets.");
        AAsset_close(dataAsset);
        return;
    }
    std::vector<char> dataContent(static_cast<size_t>(dataFileLength));
    size_t bytesRead = 0;
    while (bytesRead < dataContent.size()) {
        const auto count = AAsset_read(
                dataAsset,
                dataContent.data() + bytesRead,
                dataContent.size() - bytesRead);
        if (count <= 0) {
            g_logger.fatal("Unable to read data.zip from APK assets.");
            AAsset_close(dataAsset);
            return;
        }
        bytesRead += static_cast<size_t>(count);
    }
    AAsset_close(dataAsset);

    const std::filesystem::path stagingPath { getAppBaseDir() + "/game_data_staging/" };
    std::error_code filesystemError;
    std::filesystem::remove_all(stagingPath, filesystemError);
    filesystemError.clear();
    std::filesystem::create_directories(stagingPath, filesystemError);
    if (filesystemError) {
        g_logger.fatal("Unable to prepare Android data staging directory: {}", filesystemError.message());
        return;
    }

    std::string stagingFolder = stagingPath.string();
    unzipper::extract(
            dataContent.data(),
            static_cast<uint>(dataContent.size()),
            stagingFolder);
    if (!std::filesystem::exists(stagingPath / "init.lua")) {
        g_logger.fatal("Android data.zip did not extract a valid init.lua.");
        std::filesystem::remove_all(stagingPath, filesystemError);
        return;
    }

    std::filesystem::create_directories(destinationPath, filesystemError);
    if (filesystemError) {
        g_logger.fatal("Unable to prepare Android game data directory: {}", filesystemError.message());
        std::filesystem::remove_all(stagingPath, filesystemError);
        return;
    }
    const bool hasPreviousInventory = std::filesystem::exists(inventoryPath, filesystemError);
    if (filesystemError) {
        g_logger.fatal("Unable to inspect Android bootstrap inventory: {}", filesystemError.message());
        std::filesystem::remove_all(stagingPath, filesystemError);
        return;
    }
    std::set<std::string> previousFiles;
    if (hasPreviousInventory) {
        std::ifstream inventoryFile(inventoryPath, std::ios::binary);
        if (!inventoryFile) {
            g_logger.fatal("Unable to open Android bootstrap inventory.");
            std::filesystem::remove_all(stagingPath, filesystemError);
            return;
        }
        std::string relativeFile;
        while (std::getline(inventoryFile, relativeFile)) {
            if (relativeFile.empty())
                continue;
            if (!isSafeBootstrapRelativePath(relativeFile)) {
                g_logger.fatal("Invalid path in Android bootstrap inventory: {}", relativeFile);
                std::filesystem::remove_all(stagingPath, filesystemError);
                return;
            }
            previousFiles.insert(relativeFile);
        }
        if (inventoryFile.bad()) {
            g_logger.fatal("Unable to read Android bootstrap inventory.");
            std::filesystem::remove_all(stagingPath, filesystemError);
            return;
        }
    }

    std::set<std::string> currentFiles;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(stagingPath)) {
        const auto relativePath = entry.path().lexically_relative(stagingPath);
        const auto destination = destinationPath / relativePath;
        if (entry.is_directory()) {
            std::filesystem::create_directories(destination, filesystemError);
        } else if (entry.is_regular_file()) {
            if (!isSafeBootstrapRelativePath(relativePath)) {
                g_logger.fatal("Invalid Android bootstrap path: {}", relativePath.string());
                std::filesystem::remove_all(stagingPath, filesystemError);
                return;
            }
            currentFiles.insert(relativePath.generic_string());
            std::filesystem::create_directories(destination.parent_path(), filesystemError);
            if (!filesystemError) {
                std::filesystem::copy_file(
                        entry.path(),
                        destination,
                        std::filesystem::copy_options::overwrite_existing,
                        filesystemError);
            }
        }
        if (filesystemError) {
            g_logger.fatal("Unable to install Android bootstrap file {}: {}", relativePath.string(), filesystemError.message());
            std::filesystem::remove_all(stagingPath, filesystemError);
            return;
        }
    }

    std::string reconcileError;
    if (!reconcileBootstrapFiles(
                destinationPath,
                previousFiles,
                currentFiles,
                hasPreviousInventory,
                reconcileError)) {
        g_logger.fatal("Unable to reconcile Android bootstrap files: {}", reconcileError);
        std::filesystem::remove_all(stagingPath, filesystemError);
        return;
    }
    if (!writeBootstrapInventory(inventoryPath, currentFiles, reconcileError)) {
        g_logger.fatal("Unable to activate Android bootstrap inventory: {}", reconcileError);
        std::filesystem::remove_all(stagingPath, filesystemError);
        return;
    }

    const auto temporaryMarker = versionMarker.string() + ".tmp";
    {
        std::ofstream markerFile(temporaryMarker, std::ios::binary | std::ios::trunc);
        markerFile << version << '\n';
        if (!markerFile) {
            g_logger.fatal("Unable to write Android bootstrap version marker.");
            std::filesystem::remove_all(stagingPath, filesystemError);
            return;
        }
    }
    std::filesystem::rename(temporaryMarker, versionMarker, filesystemError);
    if (filesystemError) {
        g_logger.fatal("Unable to activate Android bootstrap version: {}", filesystemError.message());
        std::filesystem::remove_all(stagingPath, filesystemError);
        return;
    }
    std::filesystem::remove_all(stagingPath, filesystemError);
    updateDistributionConfig();
}

std::string AndroidManager::getAppBaseDir() {
    return { m_app->activity->internalDataPath };
}

std::string AndroidManager::getStringFromJString(jstring text) {
    JNIEnv* env = getJNIEnv();

    const jchar* chars = env->GetStringChars(text, nullptr);
    const jsize length = env->GetStringLength(text);

    std::string result;
    result.reserve(length);

    for (jsize i = 0; i < length; ++i) {
        const jchar codePoint = chars[i];
        if (codePoint <= 0xFF) {
            result.push_back(static_cast<char>(codePoint));
        } else {
            // fallback for characters outside ISO-8859-1 range
            result.push_back('?');
        }
    }

    env->ReleaseStringChars(text, chars);

    return result;
}

float AndroidManager::getScreenDensity() {
    JNIEnv* jni = getJNIEnv();

    return jni->CallFloatMethod(m_androidManagerJObject, m_midGetDisplayDensity);
}

void AndroidManager::attachToAppMainThread() {
    getJNIEnv();
}

JNIEnv* AndroidManager::getJNIEnv() {
    JNIEnv *env;

    if (m_app->activity->vm->AttachCurrentThread(&env, nullptr) < 0) {
        g_logger.fatal("Failed to attach current thread");
        return nullptr;
    }

    return env;
}

/*
 * Java JNI functions
*/
extern "C" {

void Java_com_otclient_AndroidManager_nativeInit(JNIEnv* env, jobject androidManager) {
    g_androidManager.setAndroidManager(env, androidManager);
}

void Java_com_otclient_AndroidManager_nativeSetAudioEnabled(JNIEnv*, jobject, jboolean enabled) {
    g_sounds.setAudioEnabled(enabled);
}

void Java_com_otclient_AndroidManager_nativeOnImeVisibilityChanged(JNIEnv*, jobject, jboolean visible, jint imeHeight) {
    g_platform.setSoftKeyboardHeight(visible ? imeHeight : 0);
}

}

#endif
