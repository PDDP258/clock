allprojects {
    repositories {
        // 国内镜像（依据 docs/本机Flutter环境使用说明.md）
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
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

// release 资源校验说明（2026-08-01）：usage_stats 1.3.1 写死 compileSdkVersion 30，
// :verifyReleaseResources 缺 android:attr/lStar（API 31+）导致 release 构建失败。
// 外部 Gradle 钩子无解（plugins.withId 被模块脚本覆盖、afterEvaluate 对 AGP 读
// compileSdk 永远太晚、已评估项目 afterEvaluate 非法——三轮试错定案），
// 最终方案：third_party/usage_stats 内置插件源码打补丁 + pubspec
// dependency_overrides 指向本地（可复现、入版本控制）。

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
