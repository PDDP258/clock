# 本机 Flutter 开发环境使用说明

> 供其他项目接入本机 Flutter 环境参考。信息采集于 2026-07-17，已在「小记日记」项目实测通过（Release APK 构建成功）。

## 一、环境清单（已验证可用）

| 组件 | 版本 | 路径 / 说明 |
|------|------|------------|
| 操作系统 | Windows 11 25H2 64-bit | — |
| Flutter SDK | 3.41.0 stable | `C:\flutter\flutter`（PATH 已含 `C:\flutter\flutter\bin`），SDK 源为 gitee 镜像 |
| Dart | 3.11.0 | 随 Flutter 自带，无需单独安装 |
| Android SDK | 36.1.0 | `C:\Users\PDXX\AppData\Local\Android\Sdk`（已通过 `flutter config --android-sdk` 登记） |
| JDK | Android Studio JBR 21（OpenJDK 21.0.9） | `E:\IDL\b\jbr`，flutter 自动探测 |
| Gradle | 8.14 | 各项目 wrapper 管理，分发包走腾讯云镜像 |
| AGP / Kotlin | 8.11.1 / 2.2.20 | 已验证兼容组合（见「版本锚点」） |
| Visual Studio | Community 2026 18.7.2 | Windows 桌面端构建可用 |
| 浏览器调试 | Edge 150 | **未装 Chrome**，Web 调试用 `flutter run -d edge` |

## 二、国内镜像（新项目接入的关键）

以下**用户级环境变量已全局生效**，新项目无需再配：

```
PUB_HOSTED_URL=https://pub.flutter-io.cn
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

以下镜像在**项目级**配置，新项目需要自行复制：

```kotlin
// android/settings.gradle.kts → pluginManagement.repositories
// android/build.gradle.kts → allprojects.repositories
maven { url = uri("https://maven.aliyun.com/repository/google") }
maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
maven { url = uri("https://maven.aliyun.com/repository/public") }
google()
mavenCentral()
gradlePluginPortal()
```

```properties
# android/gradle/wrapper/gradle-wrapper.properties
distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-8.14-all.zip
```

> 注意：本机 `~/.gradle` 下**没有**全局 `gradle.properties` / `init.d`，所有镜像都在项目里，拷项目模板时别漏。

## 三、新项目接入步骤

1. `flutter doctor` 确认环境（除 Chrome 外应全绿）。
2. `flutter create my_app`，或复制本项目 `android/` 作为模板。
3. 按上一节补齐项目级镜像（阿里云 maven + 腾讯云 gradle wrapper）。
4. `flutter pub get` → `flutter run` 验证。
5. `android/local.properties` 由 flutter 工具自动生成，**不要提交 git**。

## 四、常见坑（本项目实测踩过）

1. **系统 PATH 上的 `java` 是 1.8**，而 AGP 8.x 需要 JDK 17+。不要手动把 JAVA_HOME 指向 1.8；让 flutter 使用自动探测的 JBR（`E:\IDL\b\jbr`）。如探测失败：`flutter config --jdk-dir="E:\IDL\b\jbr"`。
2. **Kotlin 2.x + Glance 桌面小组件 / Compose**：必须在 `settings.gradle.kts` 与 `app/build.gradle.kts` 应用 `org.jetbrains.kotlin.plugin.compose`（**版本号 = Kotlin 版本**）。缺失时构建成功但运行时组合失败，小组件显示「无法显示内容」。
3. **Flutter release 构建默认启用 R8 混淆**（`flutter_tools/gradle/FlutterPlugin.kt` 中 `isMinifyEnabled = true`，无需项目配置即生效）。Manifest 未直接引用的类（如 GlanceAppWidget 子类）会被删除/改名。对策：新建 `android/app/proguard-rules.pro` 写 keep 规则，Flutter 引擎检测到该文件会自动纳入。
4. **版本号来源唯一**：`pubspec.yaml` 的 `version: x.y.z+build`，Gradle 通过 `flutter.versionCode/versionName` 自动同步，不要在 Gradle 里手写。
5. **Release 签名**：未配置 `android/key.properties` 时回退 debug 签名。正式发布前需自备 keystore。
6. **文件编码**：Windows PowerShell 默认 GBK，读写项目文件务必加 `-Encoding UTF8`；Git Bash 里用 Unix 语法（`/dev/null`、正斜杠）。
7. **Web 调试**：无 Chrome，用 `-d edge`；或安装 Chrome / 设 `CHROME_EXECUTABLE`。
8. **pub 缓存全局共享**（`%LOCALAPPDATA%\Pub\Cache`），多项目依赖版本冲突时优先 `flutter pub upgrade`，必要时 `dependency_overrides`。
9. **`flutter test` 报 "WebSocketException: Invalid WebSocket upgrade request"（2026-09-25 实测）**：`flutter test` 会起 `flutter_tester` 进程并通过 **localhost WebSocket** 与测试宿主通信，而本机（IDE/代理环境下）设了 `http_proxy` / `https_proxy` = `http://127.0.0.1:5987x`，**代理把 localhost 的连接也劫持了**，于是所有测试文件在 "loading" 阶段就失败（`Failed to load "...": Unable to connect to flutter_tester process`）。沙箱开关与本问题无关，别往那个方向排查。解法：
   ```bash
   unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
   export no_proxy="127.0.0.1,localhost" NO_PROXY="127.0.0.1,localhost"
   flutter test
   ```
10. **在 Git Bash 里跑 flutter 需要显式补 PATH**：本机 shell 的 PATH 可能被裁剪到只剩 `/usr/bin`，导致 `flutter` 找不到 `git`（报 `Error: Unable to find git in your PATH`）与 `pwsh.exe/PowerShell.exe`（报 `Error: PowerShell executable not found`）。一条可用前缀：
    ```bash
    export PATH="/usr/bin:/bin:/c/Windows/System32:/c/Windows:/c/Windows/System32/WindowsPowerShell/v1.0:/c/flutter/flutter/bin:/c/Users/PDXX/.workbuddy/binaries/PortableGit/versions/1.2.0/cmd:/c/Users/PDXX/.workbuddy/binaries/PortableGit/versions/1.2.0/bin"
    ```
11. **`flutter --version` 可能报 `fatal: ambiguous argument '@{upstream}'`**：Flutter SDK 的 git 仓库没有上游跟踪分支时，取版本号会失败并打印一行 `Command exited with code 128`。**这是噪音，不影响 `flutter test` / `flutter build`**，不必处理。

## 五、版本锚点（已验证组合）

```
Flutter 3.41.0 / Dart 3.11.0
AGP 8.11.1 + Kotlin 2.2.20 + Gradle 8.14
compileSdk/targetSdk 跟随 flutter（当前 SDK 36）
minSdk 跟随 flutter；JDK 21（JBR）
```

升级任一组件前先对照 Flutter 官方版本兼容表，梯度升级并跑一次 `flutter build apk --release` 验证。

## 六、已接入项目记录

### AI_clock（E:\main\work\AI_clock，2026-07-19 接入）

- `android/settings.gradle.kts` 与 `android/build.gradle.kts` 已按本文第二节加阿里云镜像；`gradle-wrapper.properties` 已切腾讯云分发。
- 验证结果：`flutter pub get` ✅、`dart run build_runner build` ✅、`flutter test` 34 用例全绿 ✅、`flutter analyze` 0 error/0 warning ✅。
- 项目特有坑（补充本文第四节）：
  1. drift 的 DAO 注解必须用 `@DriftAccessor`——旧别名 `@DriftDao` 在 analyzer 10 下报 "Could not resolve annotation"。
  2. `audio_service` 的 `AudioServiceConfig` 不允许 `androidNotificationOngoing: true` 与 `androidStopForegroundOnPause: false` 同开（编译期断言）。
  3. Git Bash 里调用 flutter 需先把 `C:\flutter\flutter\bin` 与 PowerShell 目录加入 PATH，并用 `env 'PROGRAMFILES(X86)=...'` 注入带括号的环境变量（cmd/PowerShell 终端无此问题）。
