plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.dropletmesh.droplet_drop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.dropletmesh.droplet_drop"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // Android 7 : la version annoncée sur drop.dropletmesh.app
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // LA SIGNATURE DES VERSIONS PUBLIÉES — toujours la même clé.
    //
    // Android n'installe une mise à jour que si elle est signée par la même
    // clé que l'app installée, et ne laisse un lien https ouvrir l'app
    // directement (sans passer par le navigateur, donc sans Internet) que si
    // le site déclare cette clé (drop.dropletmesh.app/.well-known/
    // assetlinks.json). La clé vit dans les secrets du dépôt
    // (DROP_ANDROID_CLE, DROP_ANDROID_MDP), jamais dans le code ; sans eux
    // (une compilation locale), on signe avec la clé de débogage.
    val cle = System.getenv("DROP_KEYSTORE")?.takeIf { file(it).exists() }
    signingConfigs {
        if (cle != null) {
            create("publication") {
                storeFile = file(cle)
                storeType = "pkcs12"
                storePassword = System.getenv("DROP_KEYSTORE_MDP")
                keyAlias = "droplet-drop"
                keyPassword = System.getenv("DROP_KEYSTORE_MDP")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (cle != null) "publication" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider : ouvrir un fichier reçu dans une autre app.
    implementation("androidx.core:core-ktx:1.13.1")
}
