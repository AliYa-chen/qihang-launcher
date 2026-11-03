plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val godotAssetsDirectory = layout.buildDirectory.dir("generated/godotAssets")
val syncGodotAssets by tasks.registering(Sync::class) {
    from("../godot") {
        exclude(".godot/**", ".qa/**", "export_presets.cfg")
    }
    from("../android-runtime")
    into(godotAssetsDirectory)
}

android {
    namespace = "dev.qihang.launcher"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.qihang.launcher"
        minSdk = 30
        targetSdk = 35
        versionCode = 4
        versionName = "0.1.3"
        ndk { abiFilters += setOf("arm64-v8a", "x86_64") }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    androidResources {
        ignoreAssetsPattern = "!.svn:!.git:!.gitignore:!.ds_store:!*.scc:<dir>_*:!CVS:!thumbs.db:!picasa.ini:!*~"
        noCompress += listOf("pck")
    }
    packaging {
        jniLibs { useLegacyPackaging = false }
        resources.excludes += setOf("META-INF/DEPENDENCIES", "META-INF/LICENSE*", "META-INF/NOTICE*")
    }
    sourceSets {
        getByName("main").assets.srcDir(godotAssetsDirectory)
    }
}

tasks.named("preBuild").configure { dependsOn(syncGodotAssets) }

dependencies {
    implementation("org.godotengine:godot:4.5.1.stable")
    implementation("androidx.fragment:fragment-ktx:1.8.6")
}
