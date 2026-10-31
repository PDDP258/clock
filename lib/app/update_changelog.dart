/// 更新内容浮窗（2026-10-04 用户要求）：升级安装后首次打开显示一次，
/// 显示即销毁——不常驻、不再打扰。
///
/// 机制：
/// - 用 SharedPreferences 的 `update_changelog_seen_code` 记录「上次已展示
///   的 build 号」；低于 [kAppBuildNumber] 就在首页首帧后弹一次对话框；
/// - 弹出时立即写入当前 build 号（即使进程被杀也不再重复弹，「显示后
///   销毁」的口径）；
/// - 真正的全新安装（引导页还没走完）不弹更新内容，只静默写入 build 号，
///   避免新用户第一次就被「更新了什么」糊脸。
///
/// 注意：发版时 [kAppBuildNumber] 与 [kUpdateChangelogs] 要和 pubspec 的
/// version 同步递增——这里不引入 package_info 依赖（技术选型：省一个
/// 插件，pubspec version 本来就要人工改）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/onboarding/presentation/onboarding_page.dart'
    show kOnboardingDoneKey;
import '../platform/prefs/prefs_provider.dart';

/// 当前应用 build 号（= pubspec version 的 + 号后段）。发版时同步递增。
const int kAppBuildNumber = 10;

/// 当前应用版本名（= pubspec version 的点号前段，统一 1.2.3 三段书写）。
const String kAppVersionName = '0.2.0';

/// 各 build 的更新内容（键 = build 号）。展示时取 ≤ 当前号的最新一条。
const Map<int, List<String>> kUpdateChangelogs = {
  10: [
    '竖屏「余光」布局：手机竖持即可用——竖排辉光管（简体/繁体/阿拉伯数字可选）、'
        '右缘歌词列、底部+右缘一体进度条',
    '歌词自动匹配：本地歌词文件 + 网易云 / LRCLIB 在线搜索，随播放逐行滚动；'
        '字体、颜色、大小可调，颜色可一键同步辉光管阶段色',
    '右下角新增「下一阶段」方块按钮，与左下「终止」对称；'
        '六个触屏按键统一冷白半透明样式',
    '辉光亮度上限提升至 150%；纯色背景减蓝；打开 App 不再先闪一帧横屏',
    '竖屏相关设置收进设置页一个分组，关闭竖屏即整组隐藏',
  ],
  8: [
    '背景图库扩充至 51 张（新增 25 张），三页概率与池构成不变',
    '显示配色：13 种预设色 + 自定义拾色器；三套主题方案各自独立记忆',
    '番茄/短休/长休时长可滑杆任意微调，新增「长休间隔」设置项',
    '每日及格线上限提升至 10 小时',
  ],
};

/// 首页更新内容 Gate：包住 home 路由，首帧后按需弹一次浮窗。
class UpdateChangelogGate extends ConsumerStatefulWidget {
  const UpdateChangelogGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateChangelogGate> createState() =>
      _UpdateChangelogGateState();
}

class _UpdateChangelogGateState extends ConsumerState<UpdateChangelogGate> {
  static const _kSeenKey = 'update_changelog_seen_code';

  @override
  void initState() {
    super.initState();
    // 首帧后再弹：让首页先完整渲染，浮窗不抢首帧
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (!mounted) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final seen = prefs.getInt(_kSeenKey);
    final onboardingDone = prefs.getBool(kOnboardingDoneKey) ?? false;

    if (!onboardingDone) {
      // 全新安装：不弹，静默记号
      if (seen == null) await prefs.setInt(_kSeenKey, kAppBuildNumber);
      return;
    }
    if (seen != null && seen >= kAppBuildNumber) return; // 已展示过

    // 立即记号（显示后销毁：哪怕进程立刻被杀也不再弹）
    await prefs.setInt(_kSeenKey, kAppBuildNumber);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _UpdateChangelogDialog(),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateChangelogDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = kUpdateChangelogs[kAppBuildNumber] ?? const <String>[];
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '更新内容 · v$kAppVersionName',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('· ', style: TextStyle(height: 1.35)),
                    ),
                    Expanded(
                      child: Text(item, style: const TextStyle(height: 1.35)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
