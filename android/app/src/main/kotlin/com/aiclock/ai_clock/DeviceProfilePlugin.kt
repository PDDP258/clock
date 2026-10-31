package com.aiclock.ai_clock

import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 机型画像通道（`aiclock/device`）：给 Dart 侧上报 `Build` 机型标识，
 * 用于「这台设备是不是 M500」的判定（看板 #56）。
 *
 * 只读四个静态字段，无权限、无 IO、一次调用即返回；
 * 通道不可用时 Dart 侧降级为按比例判定（见 device_profile.dart）。
 *
 * ⚠ 教训（AGENT.md §6-55）：`MethodCall` 是顶层类
 * （`io.flutter.plugin.common.MethodCall`），不是 `MethodChannel` 的嵌套类；
 * 改 Kotlin 后必须 `flutter build apk` 验证，`flutter analyze` 查不到。
 */
object DeviceProfilePlugin {
    private const val CHANNEL = "aiclock/device"

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "info" -> result.success(
                        mapOf(
                            "model" to Build.MODEL,
                            "device" to Build.DEVICE,
                            "product" to Build.PRODUCT,
                            "manufacturer" to Build.MANUFACTURER,
                        )
                    )

                    else -> result.notImplemented()
                }
            }
    }
}
