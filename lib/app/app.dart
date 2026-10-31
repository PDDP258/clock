/// 应用壳：MaterialApp、主题与路由表。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/prefs/prefs_provider.dart';
import '../features/ai/application/ai_controller.dart';
import '../features/ai/application/ai_memory.dart';
import '../features/ai/application/daily_comment.dart';
import '../features/focus/application/focus_controller.dart';
import '../features/focus/presentation/focus_page.dart';
import '../features/onboarding/presentation/onboarding_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/stats/presentation/stats_detail_page.dart';
import '../features/stats/presentation/stats_page.dart';
import 'theme.dart';
import 'theme_provider.dart';
import 'update_changelog.dart';

/// 根 Widget。仅做装配，业务逻辑在各 feature 内。
class AiClockApp extends ConsumerWidget {
  const AiClockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 首次启动进入 ≤3 屏极简引导（US-G01）；完成后不再出现
    final onboardingDone = ref
            .watch(sharedPreferencesProvider)
            .getBool(kOnboardingDoneKey) ??
        false;
    // 主题方案（初音联名三形态），设置页切换即时生效
    final scheme = ref.watch(appThemeSchemeProvider);

    // AI 主动解读（2026-09-10 用户反馈「推荐任务完成时触发」）：
    // 每完成一轮专注触发一次到期检查——是否真发请求由
    // autoInterpretIfDue/autoDailyIfDue 内部裁决（未开启/无 Key/
    // 本周（日）已有缓存全静默短路）。监听挂在 app 壳而非 ai feature 内，
    // 避免 features 间横向依赖。
    ref.listen(
      focusControllerProvider.select((s) => s.completedRounds),
      (prev, next) {
        if (next > (prev ?? 0)) {
          // 记忆日志自动落盘（看板 #54）：结算即写当天数字，
          // 随后点评/解读成功再把文本合并进同一条（同日只保留一条）。
          // 未开启 AI 时 saveToday 内部直接返回，零副作用。
          ref.read(aiMemoryLogServiceProvider).saveToday();
          ref.read(aiInsightControllerProvider.notifier).autoInterpretIfDue();
          ref.read(aiDailyCommentProvider.notifier).autoDailyIfDue();
        }
      },
    );

    return MaterialApp(
      title: 'MikuFocus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(scheme),
      darkTheme: AppTheme.dark(scheme),
      // M500 屏幕常亮场景多为室内，默认深色护眼省电
      themeMode: ThemeMode.dark,
      initialRoute: onboardingDone ? '/' : '/onboarding',
      routes: <String, WidgetBuilder>{
        // 首页套更新内容 Gate：升级安装后首启弹一次「更新内容」浮窗（随即销毁）
        '/': (_) => const UpdateChangelogGate(child: FocusPage()),
        '/onboarding': (_) => const OnboardingPage(),
        '/stats': (_) => const StatsPage(),
        '/stats/detail': (_) => const StatsDetailPage(),
        '/settings': (_) => const SettingsPage(),
      },
    );
  }
}
