/// 主题方案选择 Provider：三方案切换 + SharedPreferences 持久化。
///
/// 读写姿势与 keysTakeoverProvider/timerModeNotifier 一致；
/// app.dart watch 本 provider 即时换肤，无需重启。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/prefs/prefs_provider.dart';
import 'theme.dart';

/// 当前主题方案（默认经典葱色），持久化。
final appThemeSchemeProvider =
    StateNotifierProvider<AppThemeSchemeNotifier, AppThemeScheme>(
        (ref) => AppThemeSchemeNotifier(ref.watch(sharedPreferencesProvider)));

/// 主题方案的读写与持久化。
class AppThemeSchemeNotifier extends StateNotifier<AppThemeScheme> {
  AppThemeSchemeNotifier(this._prefs)
      : super(AppThemeScheme.fromStorageKey(_prefs.getString(_kThemeScheme)));

  static const _kThemeScheme = 'app_theme_scheme';
  final SharedPreferences _prefs;

  Future<void> setScheme(AppThemeScheme scheme) async {
    state = scheme;
    await _prefs.setString(_kThemeScheme, scheme.storageKey);
  }
}
