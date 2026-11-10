plugins {
    id("com.android.application")
}

// 驱动版本号取自仓库根目录 VERSION 文件，与 KernelSU 模块保持同一来源，
// 避免插件和模块版本对不上。CI 里可用 -PdriverVersion=... 覆盖。
val driverVersion: String =
    (project.findProperty("driverVersion") as String?)
        ?: rootProject.file("../VERSION").takeIf { it.exists() }?.readText()?.trim()
        ?: "unknown"

// versionCode 与 KSU 模块口径一致：取版本号里的数字串。
// "27.0.0-devel" -> "2700" -> 2700
val driverVersionCode: Int =
    (project.findProperty("driverVersionCode") as String?)?.toIntOrNull()
        ?: driverVersion.filter { it.isDigit() }.toIntOrNull()
        ?: 1

// CI 现场生成 keystore 并通过环境变量传入；本地没提供则退回 debug 签名，
// 保证任何情况下 assembleRelease 都能产出可安装的 APK。
val ciKeystore: String? = System.getenv("FCL_KEYSTORE_FILE")

android {
    namespace = "com.oopnv70.fcl.turnip"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.oopnv70.fcl.turnip"
        minSdk = 26
        targetSdk = 34
        versionCode = driverVersionCode
        versionName = driverVersion
    }

    signingConfigs {
        if (ciKeystore != null) {
            create("ci") {
                storeFile = file(ciKeystore)
                storePassword = System.getenv("FCL_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("FCL_KEY_ALIAS")
                keyPassword = System.getenv("FCL_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = if (ciKeystore != null) {
                signingConfigs.getByName("ci")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    // 插件元数据必须对所有 buildType 生效，放这里而不是 release 块内，
    // 否则 debug 包不带 metaData，FCL 认不出来。
    buildTypes.configureEach {
        // 应用名：出现在系统应用列表里
        resValue("string", "app_name", "Turnip Enhanced Driver")
        // 包名后缀：每个驱动插件必须唯一，否则多个插件无法共存
        applicationIdSuffix = ".enhanced"

        // 驱动在 FCL「版本设置 → 驱动」列表里的显示名
        manifestPlaceholders["driver"] = "Turnip Enhanced $driverVersion"
        // 驱动库文件名，必须存在于 src/main/jniLibs/<abi>/ 下。
        // FCL 的 DriverPlugin.DEFAULT_DRIVER_LIB 就是这个值，linkerhook 按此名加载。
        manifestPlaceholders["driverLib"] = "libvulkan_freedreno.so"
        // GPU 家族门控：本驱动只适用于高通 Adreno，不匹配时 FCL 会回落系统驱动
        manifestPlaceholders["driverGpu"] = "adreno"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    // FCL 从插件的 nativeLibraryDir 取 .so，库必须解压出来而不是留在 APK 内，
    // 所以这里强制 legacy packaging（对应 manifest 的 extractNativeLibs=true）。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

dependencies {
}