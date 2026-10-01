allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 部分旧插件（如 file_picker 8.x）在自己的 build.gradle 里把 compileSdk 固定为 34，
// 与要求编译到 36 的 flutter_plugin_android_lifecycle 冲突，导致 assembleDebug 失败。
// 这里在库子工程评估完成后，把低于 36 的 compileSdk 统一抬到 36（只升不降，
// 避免把已适配更高版本的插件又拉回来）。:app 用 flutter.compileSdkVersion，跳过；
// 且上面的 evaluationDependsOn(":app") 已让 :app 提前评估，对它注册 afterEvaluate 会报错。
subprojects {
    if (name == "app") return@subprojects
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        val getter = androidExt.javaClass.methods.firstOrNull {
            it.name == "getCompileSdk" && it.parameterCount == 0
        }
        val current = getter?.invoke(androidExt) as? Int ?: 0
        if (current < 36) {
            val setter = androidExt.javaClass.methods.firstOrNull { method ->
                method.name == "setCompileSdk" &&
                    method.parameterCount == 1 &&
                    method.parameterTypes[0] == Integer::class.javaObjectType
            }
            setter?.invoke(androidExt, 36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
