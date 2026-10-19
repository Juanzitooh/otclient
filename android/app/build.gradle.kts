plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val ciAbiFilters = providers.gradleProperty("otclient.android.abis")
    .orElse(providers.environmentVariable("OTCLIENT_ANDROID_ABIS"))
    .orNull
    ?.split(",")
    ?.map { it.trim() }
    ?.filter { it.isNotEmpty() }
    ?: listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
val elementalVersionCode = providers.environmentVariable("ELEMENTAL_ANDROID_VERSION_CODE")
    .orElse("1")
    .get()
    .toInt()
val elementalVersionName = providers.environmentVariable("ELEMENTAL_ANDROID_VERSION_NAME")
    .orElse("1.0")
    .get()
val elementalChannel = providers.environmentVariable("ELEMENTAL_ANDROID_CHANNEL")
    .orElse("test")
    .get()
val elementalApplicationId = when (elementalChannel) {
    "test" -> "br.com.elementalmmo.client.test"
    "beta", "release" -> "br.com.elementalmmo.client"
    else -> throw GradleException("ELEMENTAL_ANDROID_CHANNEL must be test, beta, or release")
}
val releaseKeystore = System.getenv("RELEASE_KEYSTORE")
val releaseStorePassword = System.getenv("RELEASE_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("RELEASE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("RELEASE_KEY_PASSWORD")
val releaseSigningConfigured = listOf(
    releaseKeystore, releaseStorePassword, releaseKeyAlias, releaseKeyPassword
).all { !it.isNullOrBlank() }

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release") } && !releaseSigningConfigured) {
        throw GradleException(
            "Android release requires RELEASE_KEYSTORE, RELEASE_KEYSTORE_PASSWORD, " +
                "RELEASE_KEY_ALIAS and RELEASE_KEY_PASSWORD"
        )
    }
}

android {
    namespace = "com.github.otclient"
    compileSdk = 36

    defaultConfig {
        applicationId = elementalApplicationId
        minSdk = 21
        targetSdk = 36
        versionCode = elementalVersionCode
        versionName = elementalVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters += ciAbiFilters
        }

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++20")

                arguments += listOf(
                    "-DVCPKG_TARGET_ANDROID=ON",
                    "-DANDROID_STL=c++_shared",
                    "-DVCPKG_MANIFEST_INSTALL=ON",
                    "-DVCPKG_INSTALL_OPTIONS=--allow-unsupported"
                )
            }
        }
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(releaseKeystore!!)
                storePassword = releaseStorePassword!!
                keyAlias = releaseKeyAlias!!
                keyPassword = releaseKeyPassword!!
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                file("proguard-rules.pro")
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
        prefab = true
    }

    ndkVersion = "29.0.13599879"
}

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.games:games-activity:1.2.1")
    implementation("com.google.android.material:material:1.13.0")
}
