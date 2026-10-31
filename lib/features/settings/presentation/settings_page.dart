/// 设置页：番茄时长配置、按键接管开关、按键映射入口、权限引导清单，
/// 以及 M500 硬件相关的预留项（FN 快捷键、音量旋钮）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/glance_colors_provider.dart';
import '../../../app/theme.dart';
import '../../../app/theme_provider.dart';
import '../../../core/ai/ai_prompt.dart';
import '../../../core/ai/deepseek_provider.dart';
import '../../../core/ai/llm_provider.dart';
import '../../../core/ai/memory_log.dart';
import '../../../core/commands/app_command.dart';
import '../../../core/media/media_key_event.dart';
import '../../../core/platform/permissions.dart';
import '../../../core/timer/numeral.dart';
import '../../../core/timer/timer_engine.dart';
import '../../../platform/db/app_database.dart';
import '../../../platform/feedback/key_feedback_service.dart';
import '../../ai/application/ai_controller.dart';
import '../../ai/application/ai_memory.dart';
import '../../backgrounds/presentation/background_settings_section.dart';
import '../../focus/application/display_settings.dart';
import '../../focus/application/focus_controller.dart';
import '../../focus/application/transition_settings.dart';
import '../../lyrics/application/lyrics_service.dart';
import '../../stats/application/stats_controller.dart';
import '../application/data_backup.dart';
import 'key_selfcheck_page.dart';
import 'tone_settings_page.dart';

/// 音乐控制（通知读取）授权状态（看板 #38：双按「音乐下一首」硬路径前置）。
final _musicControlGrantedProvider = FutureProvider<bool>(
    (ref) => AppPermissions.hasMusicControlAccess());

/// 歌词颜色候选（含白/灰阶/初音青/粉与暖色，ARGB）。
const _lyricColorChoices = <int>[
  0xE6FFFFFF, // 白 90%（默认）
  0xFFFFFFFF, // 纯白
  0xB3FFFFFF, // 白 70%
  0xFF39C5BB, // 初音青
  0xFFF26D9A, // 初音粉
  0xFFFFFFB3, // 鹅黄
  0xFFB3E5FC, // 冰蓝
  0xFFC8E6C9, // 嫩绿
  0xFFFFCDD2, // 浅绯
  0xFFD7CCC8, // 米灰
];

/// 设置页。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(pomodoroConfigProvider);
    final takeover = ref.watch(keysTakeoverProvider);
    final keyMap = ref.watch(keyMapConfigProvider);
    final feedback = ref.watch(keyFeedbackSettingsProvider);
    final pauseThreshold = ref.watch(pauseReleaseThresholdProvider);
    final musicControl = ref.watch(_musicControlGrantedProvider);
    final portraitOn = ref.watch(portraitLayoutEnabledProvider);
    final themeScheme = ref.watch(appThemeSchemeProvider);
    final glanceColors = ref.watch(glanceColorsProvider);
    final glowIntensity = ref.watch(glowIntensityProvider);
    final dailyGoal = ref.watch(dailyGoalMinutesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ------------------------------------------------ 主题（初音联名三形态）
          const _SectionTitle('主题'),
          RadioGroup<AppThemeScheme>(
            groupValue: themeScheme,
            onChanged: (v) {
              if (v != null) {
                ref.read(appThemeSchemeProvider.notifier).setScheme(v);
              }
            },
            child: Column(
              children: [
                for (final scheme in AppThemeScheme.values)
                  RadioListTile<AppThemeScheme>(
                    title: Text(scheme.label),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _ThemeColorDots(skin: scheme.skin),
                    ),
                    value: scheme,
                  ),
              ],
            ),
          ),
          const Divider(height: 32),

          // ------------------------------------------------ 显示配色（余光页四元素）
          // 2026-10-03（看板 #58）：配色按主题方案独立存储——
          // 这里改的是**当前方案**的配色，切到别的方案是它自己的一套。
          _SectionTitle('显示配色 · ${themeScheme.label}'),
          _ColorPickTile(
            title: '专注时钟',
            selected: glanceColors.focusClockColor,
            onPick: (c) => ref
                .read(glanceColorsProvider.notifier)
                .update(focusClock: c.toARGB32()),
          ),
          _ColorPickTile(
            title: '专注进度条',
            selected: glanceColors.focusBarColor,
            onPick: (c) => ref
                .read(glanceColorsProvider.notifier)
                .update(focusBar: c.toARGB32()),
          ),
          _ColorPickTile(
            title: '休息时钟',
            selected: glanceColors.breakClockColor,
            onPick: (c) => ref
                .read(glanceColorsProvider.notifier)
                .update(breakClock: c.toARGB32()),
          ),
          _ColorPickTile(
            title: '休息进度条',
            selected: glanceColors.breakBarColor,
            onPick: (c) => ref
                .read(glanceColorsProvider.notifier)
                .update(breakBar: c.toARGB32()),
          ),
          // 辉光亮度（看板 #37）：0 = 关闭辉光，余光/省电场景可调低；
          // 上限 150%（PD 2026-10-06：上限扩大，超 100% 为过量辉光档）
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('时钟辉光亮度'),
            subtitle: Slider(
              value: glowIntensity.toDouble(),
              min: 0,
              max: 150,
              divisions: 30,
              label: '$glowIntensity%',
              onChanged: (v) =>
                  ref.read(glowIntensityProvider.notifier).set(v.round()),
            ),
            trailing: Text('$glowIntensity%'),
          ),
          const Divider(height: 32),

          // ---------------------------------------- 轮次转场动画（2026-10-06）
          // 阶段/轮次/模式变化时中央内容区的过渡编排（看板 #62）：
          // 「完整」= 三段式时间轴（退场→换场→落定，1200ms）；
          // 「精简」= 只留轮次豆依次点亮；「关闭」= 瞬切（转场前的历史行为）。
          ListTile(
            leading: const Icon(Icons.auto_awesome_motion_outlined),
            title: const Text('轮次转场动画'),
            subtitle: Text(ref.watch(transitionIntensityProvider).hint),
            trailing: Text(ref.watch(transitionIntensityProvider).label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            onTap: () async {
              final picked = await showModalBottomSheet<TransitionIntensity>(
                context: context,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final n in TransitionIntensity.values)
                        ListTile(
                          title: Text(n.label),
                          subtitle: Text(n.hint,
                              style: const TextStyle(fontSize: 12)),
                          trailing:
                              ref.watch(transitionIntensityProvider) == n
                                  ? const Icon(Icons.check)
                                  : null,
                          onTap: () => Navigator.of(context).pop(n),
                        ),
                    ],
                  ),
                ),
              );
              if (picked != null) {
                await ref
                    .read(transitionIntensityProvider.notifier)
                    .set(picked);
              }
            },
          ),
          const Divider(height: 32),
          // 一个组收纳全部竖屏相关功能：开关常显；组内各项仅在开启时显示
          // （PD 2026-10-06：关闭竖屏时不显示）。
          const Divider(height: 32),

          // ------------------------------------------------ 竖屏布局（2026-10-05）
          // 一个组收纳全部竖屏相关功能：开关常显；组内各项仅在开启时显示
          // （PD 2026-10-06：关闭竖屏时不显示）。
          const _SectionTitle('竖屏「余光」布局'),
          SwitchListTile(
            secondary: const Icon(Icons.stay_current_portrait_outlined),
            title: const Text('竖屏「余光」布局'),
            subtitle: const Text(
                '开启后允许竖屏姿态：竖排时钟、歌词列与双进度条；关闭则锁定横屏'),
            value: ref.watch(portraitLayoutEnabledProvider),
            onChanged: (v) => ref
                .read(portraitLayoutEnabledProvider.notifier)
                .setEnabled(v),
          ),
          if (portraitOn) ...[
            ListTile(
              leading: const Icon(Icons.format_list_numbered),
              title: const Text('时钟数字'),
              subtitle: const Text(
                  '竖屏布局生效；中文模式下冒号变为句读 ○，暂停时变 ● 并缩小'),
              trailing: Text(ref.watch(clockNumeralProvider).label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              onTap: () async {
                final picked = await showModalBottomSheet<ClockNumeral>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final n in ClockNumeral.values)
                          ListTile(
                            title: Text(n.label),
                            trailing:
                                ref.read(clockNumeralProvider) == n
                                    ? const Icon(Icons.check)
                                    : null,
                            onTap: () => Navigator.of(context).pop(n),
                          ),
                      ],
                    ),
                  ),
                );
                if (picked != null) {
                  await ref
                      .read(clockNumeralProvider.notifier)
                      .set(picked);
                }
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_download_outlined),
              title: const Text('在线获取歌词'),
              subtitle: const Text(
                  '优先网易云音乐、回退 LRCLIB 公开歌词库，按歌名/歌手自动下载逐行歌词，无需自备 .lrc'),
              value: ref.watch(lyricOnlineEnabledProvider),
              onChanged: (v) =>
                  ref.read(lyricOnlineEnabledProvider.notifier).setEnabled(v),
            ),
            ListTile(
              leading: const Icon(Icons.lyrics_outlined),
              title: const Text('桌面歌词（竖屏布局）'),
              subtitle: Text(musicControl.when(
                data: (granted) => granted
                    ? '已授权音乐读取；把「歌名-歌手.lrc」放入下方歌词目录即显示逐行歌词'
                    : '需「通知读取」授权后显示正在播放的歌曲；点按跳转开启',
                loading: () => '查询授权状态…',
                error: (_, __) => '授权状态查询失败，点击跳转设置',
              )),
              onTap: () async {
                await AppPermissions.openMusicControlSettings();
                ref.invalidate(_musicControlGrantedProvider);
              },
            ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('歌词目录'),
            subtitle: Text(
              ref.watch(lyricDirStatusProvider).when(
                data: (st) => '${st.appDir}'
                    '${st.safTree != null ? '\nSAF 目录：${st.safTree}' : '\n未授权 SAF 目录：点按选择存放 .lrc 的文件夹（推荐，任意位置均可）'}',
                loading: () => '定位目录…',
                error: (_, __) => '目录不可用',
              ),
            ),
            trailing: const Icon(Icons.folder_copy_outlined),
            onTap: () async {
              final picked = await pickLyricDir();
              refreshLyricIndex();
              ref.invalidate(lyricDirStatusProvider);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(picked == null
                    ? '未选择目录：歌词仍可放入应用专属目录（见上方路径）'
                    : '已授权歌词目录（${picked.split('%2F').lastOrNull ?? picked}），将自动匹配播放中的歌曲'),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.font_download_outlined),
            title: const Text('歌词字体'),
            subtitle: Text(ref.watch(lyricFontProvider).when(
              data: (name) => name == null
                  ? '默认字体；把 .ttf/.otf 字体文件放入 files/lyrics/fonts/ 目录即可选择'
                  : '自定义：$name',
              loading: () => '扫描字体目录…',
              error: (_, __) => '字体目录不可用，使用默认字体',
            )),
            onTap: () async {
              final fonts = await listLyricFonts();
              if (!context.mounted) return;
              final selected = await showModalBottomSheet<String>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: const Text('默认字体'),
                        trailing: ref.read(lyricFontChoiceProvider).isEmpty
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.of(ctx).pop(''),
                      ),
                      for (final name in fonts)
                        ListTile(
                          title: Text(name),
                          trailing: ref.read(lyricFontChoiceProvider) == name
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.of(ctx).pop(name),
                        ),
                    ],
                  ),
                ),
              );
              if (selected != null) {
                await ref
                    .read(lyricFontChoiceProvider.notifier)
                    .set(selected);
                ref.invalidate(lyricFontProvider);
              }
            },
          ),
          // 歌词颜色（单一入口，2026-10-06 整理）：自定义色 与 同步辉光管
          // **互斥**——一个对话框里选色板 = 自定义色（同步自动关），选
          // 「同步辉光管」= 跟随阶段色（色板留存，随时切回）。
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('歌词颜色'),
            subtitle: ref.watch(lyricFollowClockProvider)
                ? const Text('同步辉光管 · 跟随计时阶段色')
                : Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Color(ref.watch(lyricColorProvider)),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('#${ref.watch(lyricColorProvider).toRadixString(16)
                              .padLeft(8, '0').toUpperCase()}'),
                    ],
                  ),
            onTap: () async {
              final picked = await showDialog<Object>(
                context: context,
                builder: (ctx) {
                  final following = ref.read(lyricFollowClockProvider);
                  return SimpleDialog(
                    title: const Text('歌词颜色'),
                    children: [
                      // 同步辉光管（与色板互斥，勾选态标示）
                      CheckboxListTile(
                        value: following,
                        onChanged: (v) =>
                            Navigator.of(ctx).pop(v ?? false),
                        title: const Text('同步辉光管'),
                        subtitle: const Text('跟随计时阶段色，变阶段即变色'),
                        secondary: const Icon(Icons.sync_alt),
                      ),
                      const Divider(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final argb in _lyricColorChoices)
                              InkWell(
                                onTap: () => Navigator.of(ctx).pop(argb),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Color(argb),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          Theme.of(ctx).colorScheme.outline,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
              if (picked is int) {
                // 选色板 = 自定义色：落色并解除同步（互斥，PD 2026-10-06）
                await ref.read(lyricColorProvider.notifier).set(picked);
                await ref.read(lyricFollowClockProvider.notifier).set(false);
              } else if (picked is bool && picked) {
                await ref.read(lyricFollowClockProvider.notifier).set(true);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('歌词大小'),
            subtitle: Slider(
              value: ref.watch(lyricFontSizeProvider),
              min: 10,
              max: 28,
              divisions: 18,
              label: ref.watch(lyricFontSizeProvider).round().toString(),
              onChanged: (v) =>
                  ref.read(lyricFontSizeProvider.notifier).set(v),
            ),
          ),
          ],
          const Divider(height: 32),

          // ------------------------------------------------ 背景（看板 #55）
          const _SectionTitle('背景'),
          const BackgroundSettingsSection(),
          const Divider(height: 32),

          // ------------------------------------------------ 统计
          const _SectionTitle('统计'),
          // 每日及格线（看板 #37）：热力图 ratio 模型基准——达到为满色，
          // 不足按差距二次方变浅，超标二次方向白变亮
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('每日及格线（热力图）'),
            subtitle: Slider(
              value: dailyGoal.toDouble(),
              min: 15,
              max: 600, // 10h（2026-10-03 用户要求）
              divisions: 39, // 15 分钟步进
              label: _formatGoal(dailyGoal),
              onChanged: (v) =>
                  ref.read(dailyGoalMinutesProvider.notifier).set(v.round()),
            ),
            trailing: Text(_formatGoal(dailyGoal)),
          ),
          const Divider(height: 32),

          // ------------------------------------------------ 番茄时长配置
          const _SectionTitle('番茄钟'),
          // 节奏预设（US-B03）：一键切换整套节奏，附推荐理由
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('节奏预设'),
            subtitle: Text(
                '当前 ${config.focusDuration.inMinutes}/${config.shortBreakDuration.inMinutes} 分钟'
                '${_presetLabel(config) == null ? '（自定义）' : ''}'),
            trailing: Text(
              _presetLabel(config) ?? '自定义',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            onTap: () async {
              final picked = await showModalBottomSheet<(int, int)>(
                context: context,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: const Text('经典番茄 25/5'),
                        subtitle: const Text('默认节奏，适合大多数任务'),
                        onTap: () => Navigator.of(context).pop((25, 5)),
                      ),
                      ListTile(
                        title: const Text('深度工作 50/10'),
                        subtitle:
                            const Text('高认知负荷工作的更优间隔：编程、写作等需要长进入状态的任务'),
                        onTap: () => Navigator.of(context).pop((50, 10)),
                      ),
                    ],
                  ),
                ),
              );
              if (picked != null) {
                await ref.read(pomodoroConfigProvider.notifier).update(
                      config.copyWith(
                        focusDuration: Duration(minutes: picked.$1),
                        shortBreakDuration: Duration(minutes: picked.$2),
                      ),
                    );
              }
            },
          ),
          _DurationTile(
            title: '专注时长',
            value: config.focusDuration,
            minutes: const [10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90, 120, 150, 180],
            onChanged: (d) => ref
                .read(pomodoroConfigProvider.notifier)
                .update(config.copyWith(focusDuration: d)),
          ),
          _DurationTile(
            title: '短休息',
            value: config.shortBreakDuration,
            minutes: const [1, 2, 3, 5, 8, 10, 12, 15, 20],
            onChanged: (d) => ref
                .read(pomodoroConfigProvider.notifier)
                .update(config.copyWith(shortBreakDuration: d)),
          ),
          _DurationTile(
            title: '长休息',
            value: config.longBreakDuration,
            minutes: const [10, 15, 20, 25, 30, 40, 45, 60],
            onChanged: (d) => ref
                .read(pomodoroConfigProvider.notifier)
                .update(config.copyWith(longBreakDuration: d)),
          ),
          // 长休间隔（2026-10-03 用户要求暴露到设置页；配置字段本就存在）
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('长休间隔'),
            subtitle: Text('每完成 ${config.roundsBeforeLongBreak} 轮专注进入一次长休息'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showModalBottomSheet<int>(
                context: context,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final r in const [2, 3, 4, 5, 6, 8])
                        ListTile(
                          title: Text('每 $r 轮'),
                          onTap: () => Navigator.of(context).pop(r),
                        ),
                    ],
                  ),
                ),
              );
              if (picked != null) {
                await ref.read(pomodoroConfigProvider.notifier).update(
                      config.copyWith(roundsBeforeLongBreak: picked),
                    );
              }
            },
          ),
          SwitchListTile(
            title: const Text('每轮结束后自动继续'),
            subtitle: const Text(
                '关闭时一轮（专注+休息）结束暂停等按键，专注结束自动进休息（默认）；开启后全部阶段自动续上'),
            value: config.autoContinue,
            onChanged: (v) => ref
                .read(pomodoroConfigProvider.notifier)
                .update(config.copyWith(autoContinue: v)),
          ),
          const Divider(height: 32),

          // ------------------------------------------------ 实体按键
          const _SectionTitle('实体按键'),
          SwitchListTile(
            title: const Text('计时期间接管实体按键'),
            subtitle: const Text('开启后专注时实体键归本 App；关闭则始终归系统音乐 App'),
            value: takeover,
            onChanged: (v) =>
                ref.read(keysTakeoverProvider.notifier).setEnabled(v),
          ),
          ListTile(
            leading: const Icon(Icons.timer_off_outlined),
            title: const Text('暂停超时归还按键'),
            subtitle: Text(
                '暂停超过 ${pauseThreshold.inMinutes} 分钟，按键自动归还音乐 App（记录不作废）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showModalBottomSheet<int>(
                context: context,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final m in const [5, 10, 15, 30])
                        ListTile(
                          title: Text('$m 分钟'),
                          onTap: () => Navigator.of(context).pop(m),
                        ),
                    ],
                  ),
                ),
              );
              if (picked != null) {
                await ref
                    .read(pauseReleaseThresholdProvider.notifier)
                    .setThreshold(Duration(minutes: picked));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.keyboard_alt_outlined),
            title: const Text('按键映射'),
            subtitle: Text(_describeMapping(keyMap)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showMappingSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('按键自检'),
            subtitle: const Text('实时显示收到的按键键码与语义，用于首启自检与系统更新后重新校准'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const KeySelfCheckPage()),
            ),
          ),
          // TODO(V0.2): FN 快捷键自定义 —— M500 主板预留 FN 键，
          // 需定制系统侧提供键码表与注入方式，确认后接入 CommandBus。
          const ListTile(
            enabled: false,
            leading: Icon(Icons.functions),
            title: Text('FN 快捷键自定义（预留）'),
            subtitle: Text('等待 M500 系统侧开放 FN 键码'),
          ),
          // TODO(V0.2): 音量旋钮调节倒计时 —— 旋钮事件目前走音量键通道，
          // 需在原生侧拦截并映射为「±1 分钟」，经 MethodChannel 上报。
          const ListTile(
            enabled: false,
            leading: Icon(Icons.tune),
            title: Text('音量旋钮调节倒计时（预留）'),
            subtitle: Text('旋钮微调剩余时间，待原生事件接入'),
          ),
          const Divider(height: 32),

          // ------------------------------------------------ 声音反馈（US-G03 分别开关）
          const _SectionTitle('声音反馈'),
          SwitchListTile(
            title: const Text('按键提示音'),
            subtitle: const Text('每次按键生效播放确认音（开始/暂停/结束/跳过音型可区分）'),
            value: feedback.keySoundOn,
            onChanged: (v) => ref
                .read(keyFeedbackSettingsProvider.notifier)
                .update(feedback.copyWith(keySoundOn: v)),
          ),
          SwitchListTile(
            title: const Text('阶段提醒音'),
            subtitle: const Text('专注/休息切换时发声提醒（熄屏也生效），可独立于按键音关闭'),
            value: feedback.phaseAlertOn,
            onChanged: (v) => ref
                .read(keyFeedbackSettingsProvider.notifier)
                .update(feedback.copyWith(phaseAlertOn: v)),
          ),
          // 自定义提示音（2026-10-05）：7 个音槽分别绑定用户音频片段
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('自定义提示音'),
            subtitle: const Text('换成自己的音乐/录音片段（最长 5 秒），各提示音单独设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(
                    builder: (_) => const ToneSettingsPage())),
          ),
          const Divider(height: 32),

          // ------------------------------------------------ 数据与隐私（US-E02）
          const _SectionTitle('数据与隐私'),
          const ListTile(
            leading: Icon(Icons.inventory_2_outlined),
            title: Text('我们收集了哪些数据'),
            subtitle: Text('专注记录（起止时间、时长、轮数）仅存本机数据库；'
                '应用使用时长由系统接口实时查询，本 App 不留存、不上传'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('删除全部专注数据'),
            subtitle: const Text('清空本机所有专注记录，不可恢复'),
            onTap: () => _confirmDeleteAll(context, ref),
          ),
          // 导出/导入备份（看板 #45）：应用专属外存固定路径，免权限
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('导出备份'),
            subtitle: const Text('全部专注记录 → JSON 文件（文件管理器可取走）'),
            onTap: () => _exportBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('导入恢复'),
            subtitle: const Text('从备份文件全量替换（导入前自动留存当前数据）'),
            onTap: () => _confirmImportBackup(context, ref),
          ),
          const ListTile(
            leading: Icon(Icons.query_stats),
            title: Text('关闭应用使用统计'),
            subtitle: Text('跳转系统设置，撤销「使用情况访问」权限'),
            onTap: AppPermissions.openUsageAccessSettings,
          ),
          const Divider(height: 32),

          // ------------------------------------------------ AI 功能（V0.5）
          const _SectionTitle('AI 功能'),
          const _AiSection(),
          const Divider(height: 32),

          // ------------------------------------------------ 权限引导清单
          const _SectionTitle('权限与保活'),
          const ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('通知权限'),
            subtitle: Text('专注 ongoing 通知与锁屏计时'),
            onTap: AppPermissions.ensureNotificationPermission,
          ),
          const ListTile(
            leading: Icon(Icons.query_stats),
            title: Text('使用情况访问'),
            subtitle: Text('统计各应用使用时长'),
            onTap: AppPermissions.openUsageAccessSettings,
          ),
          // 音乐控制授权（看板 #38）：双按「音乐下一首」硬路径前置——
          // 不读通知内容，仅为直控外部媒体会话的调用资格
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('音乐控制（双按下一首）'),
            subtitle: Text(musicControl.when(
              data: (granted) =>
                  granted ? '已授权：双按播放键 = 音乐下一首' : '需授权「通知读取」权限（不读通知内容）',
              loading: () => '查询授权状态…',
              error: (_, __) => '授权状态查询失败，点击跳转设置',
            )),
            onTap: () async {
              await AppPermissions.openMusicControlSettings();
              ref.invalidate(_musicControlGrantedProvider);
            },
          ),
          // dontkillmyapp 风格清单：逐项引导用户到系统/厂商设置页
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('忽略电池优化'),
            subtitle: const Text('防止计时被系统休眠打断'),
            onTap: () => _guardUnimplemented(
                context, AppPermissions.openBatteryOptimizationSettings),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('允许自启动'),
            subtitle: const Text('开机/重启后恢复计时服务'),
            onTap: () =>
                _guardUnimplemented(context, AppPermissions.openAutoStartSettings),
          ),
          const Divider(height: 32),

          // ------------------------------------------------ 帮助
          const _SectionTitle('帮助'),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('使用指南'),
            subtitle: const Text('按键教学、余光设计、权限与隐私说明，随时重看'),
            onTap: () => Navigator.of(context).pushNamed('/onboarding'),
          ),
        ],
      ),
    );
  }

  /// 当前配置命中的预设名；不匹配返回 null（自定义，US-B03）。
  String? _presetLabel(PomodoroConfig config) {
    final f = config.focusDuration.inMinutes;
    final b = config.shortBreakDuration.inMinutes;
    if (f == 25 && b == 5) return '经典番茄';
    if (f == 50 && b == 10) return '深度工作';
    return null;
  }

  /// 未实现的平台能力：给出提示而非静默失败。
  Future<void> _guardUnimplemented(
      BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on UnimplementedError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${e.message}')));
      }
    }
  }

  /// 删除全部专注数据（US-E02）：二次确认后清空 focus_session 并刷新统计。
  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除全部专注数据？'),
        content: const Text('将清空本机所有专注记录，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted =
        await ref.read(appDatabaseProvider).focusSessionDao.deleteAllSessions();
    // 刷新统计页全部派生数据（含详细时间统计子页的 family）
    ref
      ..invalidate(todayFocusProvider)
      ..invalidate(todayRoundsProvider)
      ..invalidate(weekFocusProvider)
      ..invalidate(streakProvider)
      ..invalidate(weeklyReportProvider)
      ..invalidate(heatmapProvider)
      ..invalidate(daySessionsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 $deleted 条专注记录')));
    }
  }

  /// 导出备份（看板 #45）：写应用专属外存 JSON，结果弹窗给路径。
  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    try {
      final (path, count) =
          await exportSessionsBackup(ref.read(appDatabaseProvider));
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出完成'),
          content: Text('已导出 $count 条专注记录到：\n$path\n\n'
              '可用文件管理器取走此文件；换机/清数据前建议导出。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('好'),
            ),
          ],
        ),
      );
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    }
  }

  /// 导入恢复（看板 #45）：二次确认（全量替换）→ 校验/导入 → 刷新统计。
  /// 导入前自动留存当前数据到 *_pre_import.json（导入逻辑内完成）。
  Future<void> _confirmImportBackup(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入备份？'),
        content: const Text('将用备份文件**全量替换**当前专注记录。\n'
            '导入前会自动把当前数据留存为 mikufocus_backup_pre_import.json。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final count =
          await importSessionsBackup(ref.read(appDatabaseProvider));
      ref
        ..invalidate(todayFocusProvider)
        ..invalidate(todayRoundsProvider)
        ..invalidate(weekFocusProvider)
        ..invalidate(streakProvider)
        ..invalidate(weeklyReportProvider)
        ..invalidate(heatmapProvider)
        ..invalidate(daySessionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导入 $count 条专注记录')));
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  String _describeMapping(KeyMapConfig keyMap) {
    String name(AppCommand? c) => c?.label ?? '未映射';
    return '单按：${name(keyMap.mapping[MediaKeyEvent.singleTap])} · '
        '双按：${name(keyMap.mapping[MediaKeyEvent.doubleTap])} · '
        '长按：${name(keyMap.mapping[MediaKeyEvent.longPress])}';
  }

  /// 按键映射编辑器（US-A08）：点选每个手势要触发的命令，
  /// 经 keyMapConfigProvider 立即热生效并持久化（重启保留）。
  void _showMappingSheet(BuildContext context) {
    // 播放/暂停键的手势加键名前缀；曲目键直接使用事件名
    String eventName(MediaKeyEvent e) => switch (e) {
          MediaKeyEvent.next || MediaKeyEvent.previous => e.label,
          _ => '播放/暂停 · ${e.label}',
        };

    // 可绑定的命令集合。tickMark（打点）不在列表中：它是上一曲键在
    // 正计时模式下由 mode_dispatch 改写出的语义（ADR-0005），不是可绑命令。
    const commands = [
      AppCommand.toggleStartPause,
      AppCommand.addFiveMinutes,
      AppCommand.skipPhase,
      AppCommand.finishSession,
      AppCommand.forwardNext,
      AppCommand.ignored,
    ];

    // isScrollControlled + 滚动视图：横屏（M500 推荐姿态）下高度受限也能用
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final keyMap = ref.watch(keyMapConfigProvider);
          final notifier = ref.read(keyMapConfigProvider.notifier);
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('按键映射',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  for (final event in MediaKeyEvent.values)
                    ListTile(
                      title: Text(eventName(event)),
                      trailing: Text(
                        (keyMap.mapping[event] ?? AppCommand.ignored).label,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      onTap: () async {
                        final current =
                            keyMap.mapping[event] ?? AppCommand.ignored;
                        final picked = await showModalBottomSheet<AppCommand>(
                          context: context,
                          builder: (context) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final c in commands)
                                  ListTile(
                                    title: Text(c.label),
                                    trailing: c == current
                                        ? const Icon(Icons.check)
                                        : null,
                                    onTap: () =>
                                        Navigator.of(context).pop(c),
                                  ),
                              ],
                            ),
                          ),
                        );
                        if (picked != null) {
                          await notifier.remap(event, picked);
                        }
                      },
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      '提示：绑定了双按/三按的手势组合中，单按需等待约 0.3 秒多击窗口结算才会生效；'
                      '「音乐下一首」仅在计时接管按键期间有效（按键已归还时双按直接到音乐 App）。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  TextButton(
                    onPressed: notifier.resetToDefaults,
                    child: const Text('恢复默认映射'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 及格线分钟数 → 显示文案（「2 小时」/「45 分钟」/「1 小时 30 分」）。
String _formatGoal(int minutes) {
  if (minutes < 60) return '$minutes 分钟';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h 小时' : '$h 小时 $m 分';
}

/// 单元素选色项：点击弹出「预设色板 + 自定义拾色器」（看板 #58）。
///
/// 预设 13 色（原 5 色 + 背景图库高频色 8 色）以色块网格展示；
/// 底部「自定义颜色」进入 HSV 拾色器（色相/饱和度/明度三滑杆，实时预览）。
class _ColorPickTile extends StatelessWidget {
  const _ColorPickTile({
    required this.title,
    required this.selected,
    required this.onPick,
  });

  final String title;
  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: selected,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
          const SizedBox(width: 6),
          Text(_colorLabel(selected),
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ],
      ),
      onTap: () async {
        final picked = await showModalBottomSheet<Color>(
          context: context,
          builder: (context) => _ColorPickSheet(initial: selected),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}

/// 颜色 → 显示名：命中预设用预设名，否则显示 hex。
String _colorLabel(Color c) {
  final argb = c.toARGB32();
  for (var i = 0; i < kGlancePalette.length; i++) {
    if (kGlancePalette[i].toARGB32() == argb) return kGlancePaletteNames[i];
  }
  return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

/// 选色底部弹层：预设色板网格 + 自定义 HSV 拾色入口。
class _ColorPickSheet extends StatefulWidget {
  const _ColorPickSheet({required this.initial});

  final Color initial;

  @override
  State<_ColorPickSheet> createState() => _ColorPickSheetState();
}

class _ColorPickSheetState extends State<_ColorPickSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  bool _custom = false;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final current = _hsv.toColor();
    // 包一层滚动：M500 横屏矮窗口里内容（色板+开关+三滑杆）会超屏高
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 预设色板：网格色块（13 色，紧凑不占屏）
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < kGlancePalette.length; i++)
                  _Swatch(
                    color: kGlancePalette[i],
                    selected:
                        kGlancePalette[i].toARGB32() == current.toARGB32(),
                    outline: outline,
                    onTap: () => Navigator.of(context).pop(kGlancePalette[i]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 自定义开关行：进入 HSV 三滑杆
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自定义颜色'),
              subtitle: Text(
                  '色相/饱和度/明度自由调（当前 ${_colorLabel(current)}）'),
              value: _custom,
              onChanged: (v) => setState(() => _custom = v),
            ),
            if (_custom) ...[
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: current,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: outline),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${_colorLabel(current)}  ·  点「自定义颜色」开关收起',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(current),
                    child: const Text('用这个颜色'),
                  ),
                ],
              ),
              _HsvSlider(
                label: '色相',
                value: _hsv.hue,
                max: 360,
                track: (v) => LinearGradient(colors: [
                  for (var h = 0; h <= 360; h += 30)
                    HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                ]),
                fraction: (v) => HSVColor.fromAHSV(1, v, _hsv.saturation, _hsv.value).toColor(),
                onChanged: (v) =>
                    setState(() => _hsv = _hsv.withHue(v)),
              ),
              _HsvSlider(
                label: '饱和度',
                value: _hsv.saturation * 100,
                max: 100,
                track: (v) => LinearGradient(colors: [
                  HSVColor.fromAHSV(1, _hsv.hue, 0, _hsv.value).toColor(),
                  HSVColor.fromAHSV(1, _hsv.hue, 1, _hsv.value).toColor(),
                ]),
                fraction: (v) => HSVColor.fromAHSV(1, _hsv.hue, v / 100, _hsv.value).toColor(),
                onChanged: (v) =>
                    setState(() => _hsv = _hsv.withSaturation(v / 100)),
              ),
              _HsvSlider(
                label: '明度',
                value: _hsv.value * 100,
                max: 100,
                track: (v) => LinearGradient(colors: [
                  Colors.black,
                  HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor(),
                ]),
                fraction: (v) => HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, v / 100).toColor(),
                onChanged: (v) => setState(() => _hsv = _hsv.withValue(v / 100)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 单个预设色块。
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.outline,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final Color outline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : outline,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 20, color: Colors.white)
            : null,
      ),
    );
  }
}

/// HSV 单滑杆：渐变轨道按当前其余两通道实时生成。
class _HsvSlider extends StatelessWidget {
  const _HsvSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.track,
    required this.fraction,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final LinearGradient Function(double v) track;
  final Color Function(double v) fraction;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
            width: 52,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: GradientSliderTrackShape(
                  gradient: track(value)),
              thumbColor: fraction(value),
              activeTickMarkColor: Colors.transparent,
            ),
            child: Slider(
              value: value.clamp(0, max),
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// 渐变轨道（M3 默认 track 不支持渐变，自己画一层薄矩形）。
class GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  GradientSliderTrackShape({required this.gradient});

  final LinearGradient gradient;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
    required TextDirection textDirection,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme.copyWith(
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
      ),
      enableAnimation: enableAnimation,
      thumbCenter: thumbCenter,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
      textDirection: textDirection,
    );
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final paint = Paint()..shader = gradient.createShader(trackRect);
    final radius = Radius.circular(trackRect.height / 2);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect.deflate(2), radius),
      paint,
    );
  }
}

/// 主题方案四色圆点预览（专注/休息/强调/危险）。
class _ThemeColorDots extends StatelessWidget {
  const _ThemeColorDots({required this.skin});

  final AppSkin skin;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in [
          skin.focusRingColor,
          skin.breakRingColor,
          skin.accentColor,
          skin.dangerColor,
        ])
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// 时长选择项：点击弹出常用分钟数列表。
/// 时长选择项：弹出「预设列表 + 自定义滑杆」（看板 #58：预设之外可微调任意分钟）。
class _DurationTile extends StatelessWidget {
  const _DurationTile({
    required this.title,
    required this.value,
    required this.minutes,
    required this.onChanged,
    this.sliderMax = 240,
  });

  final String title;
  final Duration value;
  final List<int> minutes;
  final ValueChanged<Duration> onChanged;

  /// 自定义滑杆上限（分钟）
  final int sliderMax;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: Text('${value.inMinutes} 分钟',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      onTap: () async {
        final picked = await showModalBottomSheet<int>(
          context: context,
          builder: (context) =>
              _DurationSheet(value: value, minutes: minutes, max: sliderMax),
        );
        if (picked != null) onChanged(Duration(minutes: picked));
      },
    );
  }
}

/// 时长选择弹层：上半是预设列表，底部滑杆可微调到任意分钟（1 ~ [max]）。
///
/// 滑杆拖动即时改「使用这个时长」按钮的文案，点按钮才落盘——避免拖动途中
/// 连写 SharedPreferences。
class _DurationSheet extends StatefulWidget {
  const _DurationSheet({
    required this.value,
    required this.minutes,
    required this.max,
  });

  final Duration value;
  final List<int> minutes;
  final int max;

  @override
  State<_DurationSheet> createState() => _DurationSheetState();
}

class _DurationSheetState extends State<_DurationSheet> {
  late double _slider = widget.value.inMinutes
      .clamp(1, widget.max)
      .toDouble();

  @override
  Widget build(BuildContext context) {
    final sliderMinute = _slider.round();
    // 包一层滚动：专注时长预设多达 14 档，M500 横屏矮窗口会超屏高
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in widget.minutes)
              ListTile(
                title: Text('$m 分钟'),
                trailing:
                    m == widget.value.inMinutes ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(m),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _slider,
                      min: 1,
                      max: widget.max.toDouble(),
                      label: '$sliderMinute 分钟',
                      divisions: widget.max - 1,
                      onChanged: (v) => setState(() => _slider = v),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop(sliderMinute),
                    child: Text('$sliderMinute 分钟'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ AI 功能

/// AI 功能区（V0.5，ADR-0006 安静原则）：
/// 总开关（开启前必须弹数据使用说明并单独同意）、服务商、API Key、
/// 测试连通性、查看实际上传字段、删除 AI 数据。
class _AiSection extends ConsumerStatefulWidget {
  const _AiSection();

  @override
  ConsumerState<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends ConsumerState<_AiSection> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    final vendorId = ref.watch(aiVendorProvider);
    final vendor = LlmVendor.byId(vendorId);
    final apiKey = ref.watch(aiApiKeyProvider);

    return Column(
      children: [
        // 总开关：默认关闭；开启必须经单独同意（07 §2 数据使用说明 v1）
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome),
          title: const Text('AI 周报解读'),
          subtitle: const Text('默认关闭。开启后由你手动点击才会请求云端'),
          value: settings.enabled,
          onChanged: (on) async {
            if (on) {
              final agreed = await _showConsentDialog(context);
              if (agreed == true) {
                await ref
                    .read(aiSettingsProvider.notifier)
                    .enableWithConsent();
              }
            } else {
              await ref.read(aiSettingsProvider.notifier).disable();
            }
          },
        ),
        if (settings.enabled) ...[
          // 服务商（OpenAI 兼容协议：DeepSeek / Kimi / 通义千问）
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('AI 服务商'),
            trailing: DropdownButton<String>(
              value: vendor.id,
              underline: const SizedBox.shrink(),
              items: [
                for (final v in LlmVendor.presets)
                  DropdownMenuItem(value: v.id, child: Text(v.displayName)),
              ],
              onChanged: (id) {
                if (id != null) {
                  ref.read(aiVendorProvider.notifier).setVendor(id);
                }
              },
            ),
          ),
          // API Key：仅存本机 SP，按厂商分键互不覆盖
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('API Key'),
            subtitle: Text(apiKey.isEmpty
                ? '未配置（到 ${vendor.displayName} 官网申请）'
                : '已配置（${apiKey.substring(0, apiKey.length < 4 ? apiKey.length : 4)}…）'),
            onTap: () => _editApiKey(context, ref, vendor),
          ),
          // 测试连通性：真实发一次最小请求，结果即反馈
          ListTile(
            leading: const Icon(Icons.wifi_tethering_outlined),
            title: const Text('测试连通性'),
            subtitle: const Text('向服务商发送一条请求验证 Key 与网络（生成需等待，最长约 1 分钟）'),
            trailing: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _testing ? null : () => _testConnection(context, ref),
          ),
          // US-AI-A04：实际上传字段逐字段可核对
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('查看实际上传字段'),
            subtitle: const Text('最近一次请求发送给服务商的完整 JSON'),
            onTap: () => _showLastUpload(context, ref),
          ),
          // 跨程序记忆日志（看板 #54）：本机 AI 每天一条的记忆文件，
          // 路径要能被抄到电脑上，所以直接展示完整路径而不是给个入口
          ListTile(
            leading: const Icon(Icons.history_edu_outlined),
            title: const Text('跨程序记忆日志'),
            subtitle: const Text('每天一条，近 7 日随请求一起发送；外部程序可直接读写该文件'),
            onTap: () => _showMemoryLog(context, ref),
          ),
          // US-AI-D04：一键删除全部 AI 数据并关闭功能
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('删除 AI 数据'),
            subtitle: const Text('清除解读缓存、同意记录、上传快照与 API Key，并关闭 AI 功能'),
            onTap: () => _confirmDeleteAiData(context, ref),
          ),
        ],
      ],
    );
  }

  /// 数据使用说明（文案版本见 [AiSettingsNotifier.currentConsentVersion]，
  /// 文案变更需升版本号重新征得同意）。
  ///
  /// v2（2026-09-26，看板 #54）：补「近 7 日记忆」披露——记忆日志会随请求
  /// 一起发送，其中**外部程序写入的 memory 内容也在内**。这件事必须写在
  /// 用户点的这个框里：写日志的是外部程序，但发出去的是这个 App。
  Future<bool?> _showConsentDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('数据使用说明'),
        content: const SingleChildScrollView(
          child: Text(
            '开启后，只有你手动点击「AI 解读」时，才会把以下本周聚合数据发送给你选择的 AI 服务商：\n\n'
            '• 本周/上周专注总时长与环比\n'
            '• 番茄轮数、中断次数与时长\n'
            '• 时段分布（上午/下午/晚上/深夜）\n'
            '• 连续记录天数\n'
            '• 近 7 日记忆日志（设置页可查看全文与文件路径）\n\n'
            '记忆日志每天一条，由本机生成，含当天的上述聚合数字与 AI 说过的话。'
            '你或其他程序写进日志 memory 字段的内容也会一并发送——'
            '请不要把不想外发的内容写进去。\n\n'
            '不会发送：具体时间点、应用名称、任何可识别个人身份的信息。\n\n'
            'API Key 仅保存在本机。你可以随时查看实际上传字段、查看或清空记忆日志、'
            '关闭 AI 功能或删除全部 AI 数据。',
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不同意'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('同意并开启'),
          ),
        ],
      ),
    );
  }

  Future<void> _editApiKey(
      BuildContext context, WidgetRef ref, LlmVendorConfig vendor) async {
    final controller = TextEditingController(text: ref.read(aiApiKeyProvider));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${vendor.displayName} API Key'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '粘贴 API Key（仅存本机）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await ref.read(aiApiKeyProvider.notifier).setKey(controller.text);
    }
    controller.dispose();
  }

  Future<void> _testConnection(BuildContext context, WidgetRef ref) async {
    final vendor = LlmVendor.byId(ref.read(aiVendorProvider));
    final key = ref.read(aiApiKeyProvider);
    if (key.isEmpty) {
      _toast(context, '请先配置 API Key');
      return;
    }
    setState(() => _testing = true);
    String msg;
    try {
      final provider =
          OpenAiCompatibleLlmProvider(vendor: vendor, apiKey: key);
      // 连通性自测只要一个字级别的回复：token 预算收到 32
      // （沿用 generateInsight 而非 ping()，是为了保留 LlmFailure.detail
      //  的原始摘要——「连接失败」不区分超时/余额不足就杀死了真机排查，§6-46(d)）
      final text = await provider
          .generateInsight(const AiPrompt('回复「连接正常」四个字即可。', maxTokens: 32));
      msg = text == null ? '未配置 Key' : '连接正常：${vendor.displayName}';
    } on LlmFailure catch (e) {
      // 诊断友好（真机教训）：失败必须带原始摘要（HTTP 码/异常描述），
      // 否则「连接失败」无法区分超时/余额不足/TLS 等完全不同的根因
      msg = '连接失败：${_failureText(e.kind)}'
          '${e.detail == null ? '' : '（${e.detail}）'}';
    }
    if (mounted) {
      setState(() => _testing = false);
      _toast(this.context, msg);
    }
  }

  void _showLastUpload(BuildContext context, WidgetRef ref) {
    final raw = ref.read(aiLastUploadJsonProvider);
    String text;
    if (raw == null) {
      text = '尚未发起过解读请求，无上传记录。';
    } else {
      try {
        text = const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
      } on FormatException {
        text = raw;
      }
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('实际上传字段'),
        content: SingleChildScrollView(
          child: Text(text,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAiData(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 AI 数据？'),
        content: const Text('将清除解读缓存、同意记录、上传快照、记忆日志与 '
            'API Key，并关闭 AI 功能。本机专注记录不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(aiSettingsProvider.notifier).deleteAiData();
      // 记忆日志是 AI 数据的一部分（US-AI-D04 的「删除=彻底离开」），
      // 但它落在磁盘上而非 SP，须单独清（清掉后外部程序仍可再写）
      await ref.read(aiMemoryLogServiceProvider).clear();
      if (context.mounted) _toast(context, 'AI 数据已删除');
    }
  }

  /// 跨程序记忆日志（看板 #54）：展示文件路径、条数与近 7 日预览，
  /// 并提供清空。路径是重点——M500 上没有键盘，用户是在电脑上改这个文件。
  Future<void> _showMemoryLog(BuildContext context, WidgetRef ref) async {
    final service = ref.read(aiMemoryLogServiceProvider);
    final snap = await service.snapshot();
    final recent = AiMemoryLog.recent(
      snap.entries,
      today: DateTime.now(),
      includeToday: false,
    );
    final preview = AiMemoryLog.renderBlock(recent) ?? '（近 7 日暂无条目）';
    if (!context.mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跨程序记忆日志'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('共 ${snap.entries.length} 条'
                  '${snap.invalidLines == 0 ? '' : '，另有 ${snap.invalidLines} 行无法解析（已原样保留）'}',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              const Text('文件路径', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(snap.path,
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace', height: 1.4)),
              const SizedBox(height: 12),
              const Text('近 7 日（随请求一起发送给服务商）',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(preview,
                  style: const TextStyle(fontSize: 12, height: 1.5)),
              const SizedBox(height: 12),
              const Text(
                '格式：一行一个 JSON 对象，date 为唯一键（同日只保留一条）。'
                '外部程序把要传进来的记忆写进 memory 字段即可，'
                '下次请求就会带上；应用只改自己的字段，不碰你写的键。',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('clear'),
            child: const Text('清空日志'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );

    if (action != 'clear' || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空记忆日志？'),
        content: const Text('将删除全部日记忆条目，近 7 日记忆随之清空。'
            '本机专注记录不受影响；外部程序之后仍可继续写入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await service.clear();
      if (context.mounted) _toast(context, '记忆日志已清空');
    }
  }

  static String _failureText(LlmFailureKind kind) => switch (kind) {
        LlmFailureKind.network => '网络不可用',
        LlmFailureKind.timeout => '请求超时（生成较慢，可重试）',
        LlmFailureKind.unauthorized => 'API Key 无效（401）',
        LlmFailureKind.quota => '余额不足或被限流',
        LlmFailureKind.badResponse => '响应格式异常',
      };

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
