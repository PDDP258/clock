/// 使用数据来源抽象：把 usage_stats 包隔离在接口后面，
/// 未来换实现（或上报云端的 AnalyticsSink）时上层零改动。
library;

import 'package:usage_stats/usage_stats.dart';

/// 单个应用一段时间内的使用数据。
class AppUsageInfo {
  const AppUsageInfo({
    required this.packageName,
    required this.foregroundMillis,
  });

  /// 应用包名
  final String packageName;

  /// 前台使用总毫秒
  final int foregroundMillis;
}

/// 使用数据来源抽象接口。
///
/// 命名对齐架构决策中的 UsageStatsSource / AnalyticsSink：
/// 读取侧 = UsageStatsSource；若未来需要上报云端，可在同一抽象下
/// 增加写入侧实现。
abstract interface class UsageStatsSource {
  /// 是否已授予「使用情况访问」权限。
  Future<bool> hasPermission();

  /// 跳转系统设置页请求授权。
  Future<void> requestPermission();

  /// 查询 [start, end) 区间内各应用的前台使用时长。
  Future<List<AppUsageInfo>> queryUsage(DateTime start, DateTime end);
}

/// 基于 usage_stats 包（Android UsageStatsManager）的实现。
class UsageStatsSourceImpl implements UsageStatsSource {
  @override
  Future<bool> hasPermission() async =>
      (await UsageStats.checkUsagePermission()) ?? false;

  @override
  Future<void> requestPermission() => UsageStats.grantUsagePermission();

  @override
  Future<List<AppUsageInfo>> queryUsage(DateTime start, DateTime end) async {
    if (!await hasPermission()) return const [];
    final raw = await UsageStats.queryUsageStats(start, end);
    return [
      for (final info in raw)
        AppUsageInfo(
          packageName: info.packageName ?? 'unknown',
          // usage_stats 的 totalTimeInForeground 为字符串毫秒
          foregroundMillis:
              int.tryParse(info.totalTimeInForeground ?? '') ?? 0,
        ),
    ];
  }
}

/// 测试 / 预览用假数据源。
class FakeUsageStatsSource implements UsageStatsSource {
  FakeUsageStatsSource({List<AppUsageInfo>? canned})
      : _canned = canned ??
            const [
              AppUsageInfo(packageName: 'com.example.music', foregroundMillis: 3600000),
              AppUsageInfo(packageName: 'com.example.reader', foregroundMillis: 1800000),
            ];

  final List<AppUsageInfo> _canned;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> requestPermission() async {}

  @override
  Future<List<AppUsageInfo>> queryUsage(DateTime start, DateTime end) async =>
      _canned;
}
