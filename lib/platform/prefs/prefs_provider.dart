/// SharedPreferences 实例 Provider（platform 层，供各层共享）。
///
/// 实例在 main.dart 启动时创建并 override 注入；配置类读写
/// （番茄配置、反馈设置、按键映射、引擎状态）均经此入口。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 实例（main.dart 中 override 注入）
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('需在 main.dart 的 ProviderScope 中 override'),
);
