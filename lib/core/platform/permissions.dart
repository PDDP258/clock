/// 平台权限封装：通知权限、使用情况访问、电池优化白名单等。
///
/// 「跳转系统设置页」类能力经 `aiclock/permissions` MethodChannel
/// 由原生 MainActivity 实现；未实现处一律抛 UnimplementedError
/// 并标注 TODO，不留空函数体。
library;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:usage_stats/usage_stats.dart';

/// 权限与系统设置的统一入口。
class AppPermissions {
  AppPermissions._();

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// 与原生 MainActivity 约定的方法通道（电池优化白名单等）。
  static const MethodChannel _channel = MethodChannel('aiclock/permissions');

  /// Android 13+ 请求通知运行时权限。返回是否已授予。
  static Future<bool> ensureNotificationPermission() async {
    final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  /// 是否已授予「使用情况访问」权限（UsageStatsManager）。
  static Future<bool> hasUsageAccess() async {
    // usage_stats 1.3.x 返回 Future<bool?>，空值按未授权处理
    return (await UsageStats.checkUsagePermission()) ?? false;
  }

  /// 跳转系统「使用情况访问」设置页，引导用户手动开启。
  static Future<void> openUsageAccessSettings() async {
    return UsageStats.grantUsagePermission();
  }

  /// 跳转系统「忽略电池优化」名单页，引导用户把本 App 加入白名单（US-H01）。
  /// 由原生 MainActivity 经 `aiclock/permissions` 通道实现（R3 接入）。
  static Future<void> openBatteryOptimizationSettings() async {
    await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
  }

  /// 本 App 是否已在电池优化白名单中。
  static Future<bool> isIgnoringBatteryOptimizations() async {
    return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
        false;
  }

  /// 跳转厂商「自启动管理」页面。
  ///
  /// TODO(V0.2): 各厂商页面 Intent 不同（参考 dontkillmyapp.com 清单），
  /// M500 为定制系统，需与系统方确认具体组件名后经 MethodChannel 跳转。
  static Future<void> openAutoStartSettings() async {
    throw UnimplementedError('V0.2 预留：自启动设置跳转需 MethodChannel 实现');
  }

  /// 与原生 MainActivity 约定的「音乐下一首」转发通道（看板 #38）。
  static const MethodChannel _mediaForwardChannel =
      MethodChannel('aiclock/media_forward');

  /// 是否已授予「通知读取权限」（媒体会话直控硬路径的前置；
  /// 本 App 不读通知内容，仅用于 getActiveSessions 调用资格）。
  static Future<bool> hasMusicControlAccess() async {
    try {
      return await _mediaForwardChannel
              .invokeMethod<bool>('isMusicControlGranted') ??
          false;
    } on MissingPluginException {
      return false; // 测试/非 Android 环境
    }
  }

  /// 跳转系统「通知读取权限」设置页，引导用户手动开启（US-H01 逐项说明）。
  static Future<void> openMusicControlSettings() async {
    await _mediaForwardChannel.invokeMethod<void>('openMusicControlSettings');
  }
}
