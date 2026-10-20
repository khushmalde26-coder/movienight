plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.khush.movienight"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.khush.movienight"
        // Android 8: covers nearly every phone, tablet and Android TV / Google TV box in use.
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "0.1"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

// The logo, icon and startup animation are the Apple app's own files, copied in at build time so
// both apps always match and the repository holds one copy of each.
abstract class SharedArt : DefaultTask() {
    @get:InputDirectory abstract val appleResources: DirectoryProperty
    @get:OutputDirectory abstract val output: DirectoryProperty

    @TaskAction
    fun copy() {
        val out = output.get().asFile.apply { deleteRecursively() }
        fun put(from: String, folder: String, name: String) =
            appleResources.file(from).get().asFile.copyTo(File(out, "$folder/$name"), overwrite = true)
        put("Assets.xcassets/LogoHorizontal.imageset/lockup-horizontal-light@2x.png", "drawable-xhdpi", "logo_horizontal.png")
        put("Assets.xcassets/AppIcon.appiconset/icon-ios-1024.png", "drawable-nodpi", "ic_launcher_art.png")
        put("Startup.mp4", "raw", "startup.mp4")
    }
}

val sharedArt = tasks.register<SharedArt>("sharedArt") {
    appleResources.set(rootProject.layout.projectDirectory.dir("../MovieNight/Resources"))
}

androidComponents {
    onVariants { variant -> variant.sources.res?.addGeneratedSourceDirectory(sharedArt, SharedArt::output) }
}

dependencies {
    implementation(libs.androidx.core)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.documentfile)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.ui)
    implementation(libs.media3.ffmpeg)
    implementation(libs.media3.inspector)
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)
    implementation(libs.coil.compose)
    implementation(libs.coroutines.android)

    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
}
