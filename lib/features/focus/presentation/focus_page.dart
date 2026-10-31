/// 专注主界面：为 M500 的 5 英寸 1280×720 小屏设计。
///
/// M500 机身按横向放置设计（侧边按键，右朝上左朝下），App 经 manifest
/// 锁定 sensorLandscape。**横屏（实际姿态）=「余光」设计（2026-08-01 重设计）**：
/// 设备放在桌角处于用户余光范围，交互靠提示音+实体键，屏幕的任务是
/// 「半秒瞟一眼就懂状态」。三原则：
///   1. 颜色报状态——全屏底色随阶段染色（专注=主题专注色、休息=休息色、
///      待继续=最亮），阶段切换整屏变色，余光无需聚焦即可感知；
///   2. 大字报时间——时间数字撑满视觉中心（约屏高 40%，等宽数字防抖动），
///      一米外直接可读；细环进度降级为底部通栏进度条（细环在一米外不可读）；
///   3. 不求助时无杂物——平时只有时间+阶段+轮次豆；唯一「屏幕求人」的
///      时刻是暂停/待继续：呼吸感大字提示「按播放键继续」。
/// 触屏操作收敛到右上角小组件（模式/统计/设置），主操作就是机身按键。
/// **竖屏（回退保险）**：单列纵向信息流（保留原组件）。
///
/// 两种计时模式（ADR-0005）：番茄倒计时（剩余时间+进度条）与
/// 正计时（累计时长+打点数）；模式切换仅在无进行中会话时可用。
library;

import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/glance_colors_provider.dart';
import '../../../app/theme.dart';
import '../../../core/commands/app_command.dart';
import '../../../core/platform/device_profile.dart';
import '../../../core/timer/count_up_timer.dart';
import '../../../core/timer/numeral.dart';
import '../../../core/timer/time_format.dart';
import '../../../core/timer/timer_engine.dart';
import '../../../core/timer/timer_mode.dart';
import '../../../platform/device/device_info_channel.dart';
import '../../../platform/media_session/now_playing_channel.dart';
import '../../../platform/prefs/prefs_provider.dart';
import '../../backgrounds/application/background_controller.dart';
import '../../backgrounds/presentation/page_background.dart';
import '../../lyrics/application/lyrics_service.dart';
import '../application/display_settings.dart';
import '../application/focus_controller.dart';
import '../application/transition_settings.dart';
import 'round_transition.dart';

/// 首次霸占按键引导的已读标记（shared_preferences）。
const kHijackNoticeShownKey = 'hijack_notice_shown';

/// 专注页。
class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  /// 本次页面生命周期内是否已检查过霸占引导（避免重复弹窗）
  bool _noticeChecked = false;

  /// 按竖排开关应用屏幕方向：开 = 允许竖屏（竖屏走新「余光」布局），
  /// 关 = 恢复锁定横屏（M500 历史行为）。manifest 的 sensorLandscape
  /// 只是默认值，运行时以 SystemChrome 为准。
  void _applyOrientationPref(bool portraitEnabled) {
    unawaited(SystemChrome.setPreferredOrientations(
      portraitEnabled
          ? const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    ));
  }

  @override
  void initState() {
    super.initState();
    _applyOrientationPref(ref.read(portraitLayoutEnabledProvider));
  }

  /// 首次霸占会话的一次性引导说明（PRD §4：管理用户预期——
  /// 计时开启期间实体键归本 App，音乐 App 暂时用不了按键）。
  void _maybeShowHijackNotice(bool keysAcquired) {
    if (!keysAcquired || _noticeChecked) return;
    _noticeChecked = true;
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(kHijackNoticeShownKey) ?? false) return;
    unawaited(prefs.setBool(kHijackNoticeShownKey, true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('计时期间按键归本 App'),
          content: const Text(
              '专注计时开启后，机身实体键将用于控制计时（音乐 App 暂时收不到按键）。\n\n'
              '结束计时、或暂停超过阈值（默认 10 分钟）后，按键自动归还音乐 App。'
              '可在「设置 → 实体按键」中更改接管策略。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(focusControllerProvider);
    final controller = ref.read(focusControllerProvider.notifier);
    _maybeShowHijackNotice(state.keysAcquired);
    // 竖排开关热切换：设置页返回立即生效（无需重启）
    ref.listen<bool>(portraitLayoutEnabledProvider,
        (_, enabled) => _applyOrientationPref(enabled));

    // 设备识别（看板 #56）：比例 ≈ 16:9 **或** 机型含 m500 → 视为 M500，
    // 不显示触屏侧键（M500 有实体键，5 英寸屏两侧寸土寸金）；
    // 两个信号都不满足（普通手机/平板）→ 横屏两侧挂触屏按钮。
    // 通道未就绪时按「非 M500 机型」处理，比例信号先顶上，到达后自动修正。
    final viewSize = MediaQuery.sizeOf(context);
    final ratioLikeM500 = isM500LikeRatio(viewSize.width, viewSize.height);
    final deviceIsM500 =
        ref.watch(deviceIdentityProvider).valueOrNull?.isM500 ?? false;
    final showSideControls = showTouchSideControls(
      ratioLikeM500: ratioLikeM500,
      deviceIsM500: deviceIsM500,
    );

    return Scaffold(
      // 2026-10-01 看板 #57：**不要**用 SafeArea 包整个 body——insets
      // （状态栏/刘海）会把连同背景层在内的整页一起缩进。初始冷启动
      // insets=0 时一切正常，但从设置页返回后系统重新下发 insets，
      // 背景图上、左两侧就出现黑边（真机复现，M500 恒 insets=0 从未暴露）。
      // 横屏布局内部自行把 insets 加到**内容**上；背景恒 edge-to-edge。
      // 竖屏回退布局没有背景层，自己包 SafeArea 即可。
      body: OrientationBuilder(
        builder: (context, orientation) =>
            orientation == Orientation.landscape
                ? _GlanceLandscape(
                    state: state,
                    controller: controller,
                    showSideControls: showSideControls,
                  )
                : ref.watch(portraitLayoutEnabledProvider)
                    ? _PortraitGlance(state: state, controller: controller)
                    : SafeArea(
                        child:
                            _PortraitLayout(state: state, controller: controller),
                      ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 横屏「余光」

/// 横屏「余光」布局：桌角远观场景，颜色/大字/少物三原则。
///
/// 尺寸自适应（看板 #56）：所有装饰尺寸都乘缩放系数 [uiScaleFor]——
/// 以 M500 的逻辑高为基准按视口高度等比缩放，M500 上系数恰为 1.0
/// （与历史调参值完全一致），其它设备上各元素相对比例不变。
class _GlanceLandscape extends ConsumerWidget {
  const _GlanceLandscape({
    required this.state,
    required this.controller,
    required this.showSideControls,
  });

  final FocusViewState state;
  final FocusController controller;

  /// 是否显示左右触屏侧键（非 M500 设备，两个识别信号都不满足）
  final bool showSideControls;

  /// 阶段色（一眼级信号）：专注=主题专注色，休息=休息色。
  ///
  /// 暂停**不改色**：暂停是「冻结」不是「换段」，颜色沿用暂停前那一段
  /// （[FocusViewState.colorPhase]）。原先 paused 分支硬切到 accentColor，
  /// 视觉上像是先跳去休息阶段再跳回来（PD 2026-10-07 反馈）。
  /// 「停了」由时钟空心描边 + kicker 的 PAUSED 表达，不靠换色。
  Color _phaseColor(BuildContext context) {
    if (state.mode == TimerMode.countUp) {
      return switch (state.countUpPhase) {
        CountUpPhase.running || CountUpPhase.paused =>
          context.skin.focusRingColor,
        _ => Theme.of(context).colorScheme.outline,
      };
    }
    return switch (state.colorPhase) {
      TimerPhase.focusing => context.skin.focusRingColor,
      TimerPhase.shortBreak || TimerPhase.longBreak =>
        context.skin.breakRingColor,
      // colorPhase 已把 paused 解析成暂停前的阶段，走到这里说明引擎没记住
      // 暂停前阶段（不该发生）——退回专注色，绝不用休息色。
      TimerPhase.paused => context.skin.focusRingColor,
      _ => Theme.of(context).colorScheme.outline,
    };
  }

  /// 时钟色（P0 自定义）：专注/休息分别取自用户配色；暂停沿用暂停前那段。
  Color _clockColor(BuildContext context, GlanceColors colors) {
    if (state.mode == TimerMode.countUp) {
      return switch (state.countUpPhase) {
        CountUpPhase.running || CountUpPhase.paused => colors.focusClockColor,
        _ => Theme.of(context).colorScheme.outline,
      };
    }
    return switch (state.colorPhase) {
      TimerPhase.focusing => colors.focusClockColor,
      TimerPhase.shortBreak || TimerPhase.longBreak => colors.breakClockColor,
      TimerPhase.paused => colors.focusClockColor,
      _ => Theme.of(context).colorScheme.outline,
    };
  }

  /// 进度条色（P0 自定义）：与时钟分离，可做强对比（如葱色钟+红条）。
  /// 暂停沿用暂停前那一段的条色（同 [_phaseColor] 的理由）。
  Color _barColor(BuildContext context, GlanceColors colors) {
    if (state.mode == TimerMode.countUp) {
      return switch (state.countUpPhase) {
        CountUpPhase.running || CountUpPhase.paused => colors.focusBarColor,
        _ => Theme.of(context).colorScheme.outline,
      };
    }
    return switch (state.colorPhase) {
      TimerPhase.focusing => colors.focusBarColor,
      TimerPhase.shortBreak || TimerPhase.longBreak => colors.breakBarColor,
      TimerPhase.paused => colors.focusBarColor,
      _ => Theme.of(context).colorScheme.outline,
    };
  }

  String get _phaseLabel {
    if (state.mode == TimerMode.countUp) return state.countUpPhase.label;
    return state.phase.label;
  }

  /// 是否处于「屏幕求人」时刻（暂停/待继续——需要用户按键决策）
  bool get _awaitingTap =>
      state.mode == TimerMode.countUp
          ? state.countUpPhase == CountUpPhase.paused
          : state.phase == TimerPhase.paused;

  /// 是否显示触屏主按钮：运行中隐藏（减少干扰），idle/暂停/完成态显示。
  bool get _showPrimaryButton {
    if (state.mode == TimerMode.countUp) {
      return state.countUpPhase != CountUpPhase.running;
    }
    return state.phase != TimerPhase.focusing &&
        state.phase != TimerPhase.shortBreak &&
        state.phase != TimerPhase.longBreak;
  }

  /// 是否显示标签入口（US-B05）：仅无进行中会话时（idle/完成态）——
  /// 会话开始后标签已烙印，运行/暂停中不提供修改（保持余光页少物原则）。
  bool get _showTagChip {
    if (state.mode == TimerMode.countUp) {
      return state.countUpPhase == CountUpPhase.idle ||
          state.countUpPhase == CountUpPhase.finished;
    }
    return state.phase == TimerPhase.idle ||
        state.phase == TimerPhase.completed;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ref.watch(glanceColorsProvider);
    final glow = ref.watch(glowIntensityProvider) / 100;
    final phaseColor = _phaseColor(context);
    final clockColor = _clockColor(context, colors);
    final barColor = _barColor(context, colors);
    final isCountUp = state.mode == TimerMode.countUp;
    final total = state.phaseTotal.inMilliseconds;
    final progress = isCountUp
        ? null
        : total <= 0
            ? 0.0
            : (1 - state.remaining.inMilliseconds / total).clamp(0.0, 1.0);
    final awaiting = _awaitingTap;
    // 求人时刻提亮染色（0.16 → 0.26），余光也能感到「它在叫我」
    final bgAlpha = awaiting ? 0.26 : 0.14;
    // 视口高度缩放系数（M500 ≈ 1.0，见类注释）
    final s = uiScaleFor(MediaQuery.sizeOf(context).height);
    // 系统 insets（状态栏/刘海）：只作用于内容，背景层不受影响（看板 #57）
    final pad = MediaQuery.paddingOf(context);
    // 右侧键的形态：运行中=暂停，其余（idle/暂停/完成）=播放
    final running = isCountUp
        ? state.countUpPhase == CountUpPhase.running
        : state.phase == TimerPhase.focusing ||
            state.phase == TimerPhase.shortBreak ||
            state.phase == TimerPhase.longBreak;

    // 整屏染色底：阶段切换 700ms 渐变扫过，余光的第一信号；
    // 外层 _PhasePulse 在阶段轮转时叠加一次 900ms 脉冲（提示音的视觉冗余）
    //
    // 背景图（本轮新增）：图层顺序 = **阶段染色 → 图片 → 内容**，
    // 图片不透明度 30%（比统计页更低），因为阶段染色是「一眼信号」，
    // 不能被氛围图盖掉；且这一档与「纯色无图」随机交替（纯色概率略高）。
    // 计时页不滚动，故背景恒为顶部对齐的静止层。
    return _PhasePulse(
      // 用 colorPhase 而非 phase：暂停不是换段，不该触发整屏脉冲
      // （PD 2026-10-07：暂停时颜色曾闪成休息色再跳回）。
      phaseKey: '${state.mode.name}-${state.colorPhase.name}-'
          '${state.countUpPhase.name}-${state.completedRounds}',
      color: phaseColor,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      color: Color.alphaBlend(
          phaseColor.withValues(alpha: bgAlpha), scheme.surface),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const StaticBackdrop(page: BgPage.focus),
          _Entrance(
        child: Column(
        children: [
          // 顶部信息条：阶段词 + 触屏小组件（模式/统计/设置）。
          // 顶边距含状态栏 insets（背景已 edge-to-edge，内容要让位）
          Padding(
            padding:
                EdgeInsets.fromLTRB(20 * s, 6 * s + pad.top, 8 * s, 0),
            child: Row(
              children: [
                Text(
                  _phaseLabel,
                  style: TextStyle(
                    fontSize: 22 * s,
                    fontWeight: FontWeight.w700,
                    color: phaseColor,
                  ),
                ),
                if (state.keysAcquired)
                  Padding(
                    padding: EdgeInsets.only(left: 6 * s),
                    child: Icon(Icons.headset, size: 16 * s),
                  ),
                if (_showTagChip)
                  Padding(
                    padding: EdgeInsets.only(left: 8 * s),
                    child: const _TagChip(),
                  ),
                const Spacer(),
                _GlanceModeSwitcher(
                    state: state, onSelect: controller.setMode, scale: s),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '使用统计',
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/stats'),
                  icon: Icon(Icons.bar_chart, size: 20 * s),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '设置',
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/settings'),
                  icon: Icon(Icons.settings, size: 20 * s),
                ),
              ],
            ),
          ),
          // 视觉中心：阶段字标 + 巨大时间（+求人提示 / 轮次豆）
          //
          // 轮次转场（看板 #62）：整块包进 RoundTransition——旧内容先
          // 下沉淡出（260ms），新内容里字标/时钟/轮次豆各按自己的
          // 时间点落位（见 round_transition.dart 的时间轴图）。
          // 转场键含**轮次号与模式**：这两者变化时中央也是整块换字。
          Expanded(
            child: RoundTransition(
              phaseKey: '${state.mode.name}-${state.phase.name}-'
                  '${state.countUpPhase.name}-${state.completedRounds}',
              intensity: ref.watch(transitionIntensityProvider),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 阶段字标（editorial 排版：大写字距宽的英文 kicker，
                      // 给巨字时钟一个层级锚点，余光下先读色再读字）
                      _StageKicker(state: state, color: phaseColor, scale: s),
                      SizedBox(height: 4 * s),
                      _GlanceClock(
                          state: state,
                          color: clockColor,
                          glow: glow,
                          scale: s),
                      SizedBox(height: 8 * s),
                      if (awaiting)
                        _BreathingPrompt(
                          color: phaseColor,
                          text: state.mode == TimerMode.countUp ||
                                  state.completedRounds == 0 &&
                                      state.phase != TimerPhase.completed
                              ? '按播放键继续'
                              : '按播放键，开始下一轮',
                          scale: s,
                        )
                      else if (!isCountUp &&
                          state.phase != TimerPhase.idle &&
                          state.phase != TimerPhase.completed)
                        _RoundPips(state: state, color: phaseColor, scale: s)
                      else if (isCountUp && state.markCount > 0)
                        Text('打点 ${state.markCount} 个',
                            style: TextStyle(
                                fontSize: 20 * s,
                                color: scheme.onSurfaceVariant))
                      else if (state.phase == TimerPhase.completed)
                        Text(
                          '本轮会话已结束 · 共 ${state.completedRounds} 轮',
                          style: TextStyle(
                              fontSize: 20 * s,
                              color: scheme.onSurfaceVariant),
                        )
                      else
                        const SizedBox.shrink(),
                      if (_showPrimaryButton) ...[
                        SizedBox(height: 12 * s),
                        _GlancePrimaryButton(
                          state: state,
                          onPressed: controller.tapPrimaryButton,
                          scale: s,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 底部通栏进度条（替代细环：一米外唯一可读的进度形态）。
          // 侧键隐藏（M500）时它是 Column 最后一个子项 → 贴底（历史行为）。
          // 底边距含导航条 insets（看板 #57）
          Padding(
            padding: EdgeInsets.only(bottom: pad.bottom),
            child: _GlanceProgressBar(
                progress: progress,
                running: isCountUp &&
                    state.countUpPhase == CountUpPhase.running,
                // 流光只给「番茄运行中」：暂停/idle/正计时一律静态（P1）
                sweeping: !isCountUp &&
                    (state.phase == TimerPhase.focusing ||
                        state.phase == TimerPhase.shortBreak ||
                        state.phase == TimerPhase.longBreak),
                color: barColor,
                scale: s),
          ),
        ],
      ),
      ),
          // 触屏侧键（看板 #56）：非 M500 设备才显示——左「+5分钟/打点」、
          // 右「暂停/继续」。2026-10-01 修复「比例完全失衡」：必须挂在
          // StackFit.expand 的 Stack 层（_Entrance 之上、不参与入场动画），
          // Align 才能按整屏垂直居中；此前误挂在 Column 里，两个按钮被
          // 当成两行纵向堆叠在进度条下方，把进度条顶离屏底。
          if (showSideControls) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                // 水平让位刘海/曲边 insets（看板 #57）
                padding: EdgeInsets.only(left: 10 * s + pad.left),
                child: _GhostIconButton(
                  size: 30 * s,
                  icon: isCountUp ? Icons.flag_outlined : Icons.add,
                  semanticLabel: isCountUp ? '打时间标记点' : '加五分钟',
                  onTap: controller.addFiveMinutes,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 10 * s + pad.right),
                child: _GhostIconButton(
                  size: 30 * s,
                  icon: running
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  semanticLabel: running ? '暂停' : '开始或继续',
                  onTap: controller.tapPrimaryButton,
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// 幽灵图标按钮（看板 #56）：非 M500 设备计时页的触屏侧键。
///
/// 2026-10-01 用户口径：**缩小图标、去掉圆形背景**——只画白色图标本体，
/// 不再有任何圆底/渐变/描边/落影。可读性靠图标自带的柔和黑投影
/// （任何背景图/染色上都压得住）；点击热区仍是 [size] 的方形
/// （InkWell 水波为圆形），但视觉上零装饰。
class _GhostIconButton extends StatelessWidget {
  const _GhostIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.size = 30,
    this.color = Colors.white,
    this.opacity = 1.0,
  });

  final IconData icon;

  /// 图标边长（逻辑像素），同时也是最小触控热区边长。
  final double size;
  final String semanticLabel;
  final VoidCallback onTap;

  /// 图标本体颜色（竖屏六键 2026-10-06：#dcf4ff 冷白）。
  final Color color;

  /// 图标本体不透明度（竖屏六键统一 60%）。
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: size,
              color: color.withValues(alpha: opacity),
              shadows: [
                // 柔和贴身投影：浅色图标在浅色背景图上也保持轮廓
                Shadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  offset: const Offset(0, 1),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 阶段切换脉冲：阶段轮转瞬间整屏泛一次阶段色（900ms 一次性，
/// 峰谷 0→0.18→0）——提示音之外的视觉冗余，余光场景的「眨眼」。
/// 一次性动画不常驻；phaseKey 不变不触发（性能 P1 原则）。
class _PhasePulse extends StatefulWidget {
  const _PhasePulse({
    required this.phaseKey,
    required this.color,
    required this.child,
  });

  /// 阶段标识：模式 + 阶段 + 正计时子阶段 + 轮次，任一变化视为一次轮转
  final String phaseKey;
  final Color color;
  final Widget child;

  @override
  State<_PhasePulse> createState() => _PhasePulseState();
}

class _PhasePulseState extends State<_PhasePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 70),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_PhasePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phaseKey != widget.phaseKey) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _opacity,
            builder: (context, _) => Container(
              color: widget.color.withValues(alpha: _opacity.value * 0.18),
            ),
          ),
        ),
      ],
    );
  }
}

/// 阶段字标：巨字时钟上方的英文 kicker（大字距小写排版锚点）。
/// 色随阶段、字形恒定——远距场景下它是「色块」而非「文字」。
///
/// 轮次转场（看板 #62）：阶段字是**硬切**的（换段瞬间旧字直接消失），
/// 这里给它补上换位——旧字上移淡出、新字从上方落位（160→640ms），
/// 与巨钟换色、轮次豆点亮串成时间轴。静止时零成本（controller 停在终值）。
class _StageKicker extends StatelessWidget {
  const _StageKicker({
    required this.state,
    required this.color,
    required this.scale,
  });

  final FocusViewState state;
  final Color color;
  final double scale;

  String get _text {
    if (state.mode == TimerMode.countUp) {
      return switch (state.countUpPhase) {
        CountUpPhase.running => 'COUNT UP',
        CountUpPhase.paused => 'PAUSED',
        CountUpPhase.finished => 'DONE',
        CountUpPhase.idle => 'READY',
      };
    }
    return switch (state.phase) {
      TimerPhase.focusing => 'FOCUS',
      TimerPhase.shortBreak => 'SHORT BREAK',
      TimerPhase.longBreak => 'LONG BREAK',
      // 中途暂停 = PAUSED；待继续（冻结在整段起点）= READY
      TimerPhase.paused =>
        state.remaining < state.phaseTotal ? 'PAUSED' : 'READY',
      TimerPhase.completed => 'DONE',
      TimerPhase.idle => 'READY',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final scope = RoundTransitionScope.maybeOf(context);
    final lineColor = color.withValues(alpha: 0.45);
    // kicker 侧短横线随阶段一起换（同色系装饰，归入换位动画）
    final bar = SizedBox(
      height: 1.5,
      child: Container(width: 28 * s, color: lineColor),
    );
    final word = Text(
      _text,
      style: TextStyle(
        fontSize: 15 * s,
        fontWeight: FontWeight.w600,
        letterSpacing: 8,
        color: color.withValues(alpha: 0.75),
      ),
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // editorial 海报排版：kicker 两侧短横线（远距 = 一对色块括号）
        bar,
        const SizedBox(width: 12),
        // letterSpacing 会在末字符后多留 8 空隙，右侧间距少 8 作补偿
        _SwapOutIn(
          tag: _text,
          animation: scope?.kicker,
          enterFrom: RoundTransitionTiming.enterShift,
          child: word,
        ),
        const SizedBox(width: 4),
        bar,
      ],
    );
    if (scope == null || !scope.isPlaying) return row;
    // 退场段：整条 kicker 随旧内容一起下沉淡出（由 RoundTransition 负责），
    // 此处只做换位——新字从上方落位。
    return ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1.0).animate(scope.kicker),
      child: row,
    );
  }
}

/// 字标/短词的**换位**包装：值变化时旧内容上移淡出、新内容从上方落位。
///
/// 与 [AnimatedSwitcher] 的区别：位移方向与时长由外部 [animation] 统一编排
/// （同一时刻只有这一处在动），而 switcher 只能用自己的固定时长。
class _SwapOutIn extends StatelessWidget {
  const _SwapOutIn({
    required this.tag,
    required this.child,
    this.animation,
    this.enterFrom = -0.045,
  });

  /// 参与比较的值（变了就换）。
  final Object? tag;

  /// 外部编排的进度（null = 不做动画，静态渲染）。
  final Animation<double>? animation;

  /// 新内容起始位移（负 = 上方）。
  final double enterFrom;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final anim = animation;
    if (anim == null) return child;
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        // 单调上行进度 → 映射成「淡入 + 落位」，退场交给外层
        final t = anim.value.clamp(0.0, 1.0);
        return Opacity(
          // 前 15% 保持透明，避免和旧字叠成重影
          opacity: ((t - 0.15) / 0.85).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, enterFrom * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

/// 巨大时钟：等宽数字防宽度抖动，撑满视觉中心（FittedBox 按空间缩放）。
/// 余光 2.0 强化（看板 #35）：
///  - 数字带阶段色辉光（霓虹感，一米外「浮」在染色底上）；
///  - 暂停/待继续 = 空心描边字——「时间被掏空」就是停了的图形隐喻；
///  - 每位数字独立 odometer：变化时 250ms 滚入滚出（每秒个位滚一次，
///    「计时器活着」的最小证据，测试时开始计时即可见）。
///
/// 轮次转场（看板 #62，PD 定调「数字快速回滚 + 颜色淡入淡出」）：
/// 常驻的逐位向下滚是「秒在走」，轮次切换时**方向反过来**——新数字自上方
/// 快速滚回（300ms，整齐同步），同时阶段色做 300ms 交叉淡入淡出（旧色退、
/// 新色进）。两件事由编排层同一条进度驱动，因此「颜色换完 = 数字也落定」。
class _GlanceClock extends StatefulWidget {
  const _GlanceClock({
    required this.state,
    required this.color,
    required this.glow,
    required this.scale,
  });

  final FocusViewState state;
  final Color color;

  /// 辉光强度 0.0-1.0（0 = 关闭；设置页可调，看板 #37）
  final double glow;

  /// 视口高度缩放系数（目标渲染高度约屏高 42% 的基准字号随之缩放）
  final double scale;

  @override
  State<_GlanceClock> createState() => _GlanceClockState();
}

class _GlanceClockState extends State<_GlanceClock> {
  /// 本次转场的时钟色起点（交叉淡入淡出的**起点**，转场结束即作废）。
  ///
  /// 关键：只在**当前这次转场里**有效。[PD 2026-10-07 修复] 原实现只在
  /// 颜色变化时写这里、从不清理，于是上一次转场的旧色（例如很久前某个休息
  /// 段的红色）会一直留在字段里；下一次转场若颜色恰好没变（暂停/继续就属
  /// 这种——暂停沿用原阶段色），就拿这个陈旧色当淡化起点，表现为
  /// 「蓝 → 红 → 蓝」闪一下。转场结束必须作废，且起止色相同时不做淡化。
  Color? _swapFromColor;

  @override
  void didUpdateWidget(_GlanceClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _swapFromColor = oldWidget.color;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isCountUp = state.mode == TimerMode.countUp;
    // 空心态：番茄 paused / 正计时 paused（含待继续——冻结在起点也是停）
    final hollow = isCountUp
        ? state.countUpPhase == CountUpPhase.paused
        : state.phase == TimerPhase.paused;
    // 目标渲染高度约屏高 42%（FittedBox 会按实际空间缩到恰好放下）；
    // 给足上限让它自己缩，竖向空间才是约束。基准字号随视口缩放，
    // 保证其它设备上时钟相对屏高的比例与 M500 一致。
    final base = TextStyle(
      fontSize: 240 * widget.scale,
      height: 1.0,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final text =
        formatDurationClock(isCountUp ? state.elapsed : state.remaining);

    Widget buildWith(Color color, {required bool swap}) {
      // 辉光直接挂在字形 Text 上：与 odometer 滚动严格同步——独立底层
      // 会留下「不动的残影」（看板 #37 反馈）；无 ClipRect 故零裁切硬边。
      final glow = widget.glow;
      final glowShadows = glow <= 0
          ? null
          : [
              Shadow(color: color.withValues(alpha: 0.9 * glow), blurRadius: 18),
              Shadow(color: color.withValues(alpha: 0.5 * glow), blurRadius: 45),
              Shadow(color: color.withValues(alpha: 0.3 * glow), blurRadius: 90),
            ];
      final style = hollow
          ? base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..strokeJoin = StrokeJoin.round
                ..color = color)
          : base.copyWith(color: color, shadows: glowShadows);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < text.length; i++)
            text[i] == ':'
                ? Text(':', style: style)
                : _OdometerDigit(
                    char: text[i],
                    style: style,
                    // 转场中：反向（自上方滚回）+ 缩短到 300ms
                    rollFromAbove: swap,
                  ),
        ],
      );
    }

    Widget clockOf(Color color, {required bool swap}) => RepaintBoundary(
          // 整钟独立重绘层：兄弟节点的帧不再带动时钟重绘（卡顿优化）
          child: buildWith(color, swap: swap),
        );

    final scope = RoundTransitionScope.maybeOf(context);
    final swap = scope != null && scope.isPlaying;
    final from = _swapFromColor;
    // 非转场：作废本次起点（下次转场重新记），直接给目标色，零成本。
    // 赋值放在 build 里是安全的——它只是缓存，不触发重建。
    if (!swap) {
      _swapFromColor = null;
      return clockOf(widget.color, swap: false);
    }
    // 转场中但颜色没变（暂停/继续沿用原阶段色）：不做淡化，只播数字回滚。
    if (from == null || from == widget.color) {
      return clockOf(widget.color, swap: true);
    }
    // 起止色确实不同：从本次起点交叉淡入淡出（进度与 odometer 回滚同源，
    // 因此「颜色换到位」与「数字落定」是同一时刻）
    return AnimatedBuilder(
      animation: scope!.clock,
      builder: (context, _) => clockOf(
        Color.lerp(from, widget.color, scope.clock.value.clamp(0.0, 1.0))!,
        swap: true,
      ),
    );
  }
}

/// 单字符 odometer：值变化时新字符自下方滚入、旧字符向下方滚出（400ms，
/// 随滚动渐隐）。不做裁切（Clip.none）——滑出边界的残影随透明度消失，
/// 换辉光零硬边。等宽数字 + 冒号不参与，布局零抖动。
class _OdometerDigit extends StatelessWidget {
  const _OdometerDigit({
    required this.char,
    required this.style,
    this.rollFromAbove = false,
  });

  final String char;
  final TextStyle style;

  /// 轮次转场：反向（自上方滚回）+ 时长缩短，见 [_GlanceClockState]。
  final bool rollFromAbove;

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary：逐位 odometer——秒个位滚动的一帧只重绘这一位，
    // 同排其它位与整钟不再跟着重绘（PD 2026-10-06：卡顿优化，
    // 纯渲染层隔离，视觉与动画零变化）
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: rollFromAbove ? 300 : 400),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: Offset(0, rollFromAbove ? -0.85 : 0.85),
            end: Offset.zero,
          ).animate(animation);
          return SlideTransition(
            position: slide,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none, // 残影滑出不裁切（随渐隐消失）
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        child: Text(char, key: ValueKey<String>(char), style: style),
      ),
    );
  }
}

/// 入场编排：开屏一次性——内容 700ms 淡入 + 轻微上浮（看板 #35）。
/// StatefulWidget 保持元素，秒级重建不会重演。
class _Entrance extends StatefulWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..forward();
  late final Animation<double> _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.8, curve: Curves.easeOut));
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// 轮次豆：长休节奏进度的图形化（●●●○），远距可读性优于「第 N 轮」文字。
/// 轮次豆组：几颗豆 = 几轮一轮。转场时**按序点亮**（每颗 80ms 间隔，
/// 见 [RoundTransitionScope.staggered]）——长休时四颗同时亮读不出
/// 「这一轮刚走完」，依次点亮才有「走完」的过程感。
class _RoundPips extends ConsumerWidget {
  const _RoundPips({
    required this.state,
    required this.color,
    required this.scale,
  });

  final FocusViewState state;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total =
        ref.watch(pomodoroConfigProvider).roundsBeforeLongBreak;
    final done = state.completedRounds % total;
    // 正在长休 = 一轮节奏刚走完，豆子全亮
    final filled = state.phase == TimerPhase.longBreak ? total : done;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          _PipDot(
            lit: i < filled,
            color: color,
            diameter: 12 * scale,
            index: i,
            count: total,
          ),
      ],
    );
  }
}

/// 单颗轮次豆：点亮瞬间做一次 0.6→1.0 弹出（300ms easeOutBack，
/// 一次性动画）；保持态/熄灭态不播（性能 P1 原则）。
///
/// 轮次转场（看板 #62）：点亮进度改由编排层下发（[staggered]），
/// 于是多颗豆天然错峰；无编排层时（单测/旧调用）退回本地的
/// 「未点亮 → 点亮」一次性动画，行为与转场前一致。
class _PipDot extends StatefulWidget {
  const _PipDot({
    required this.lit,
    required this.color,
    this.diameter = 12,
    this.index = 0,
    this.count = 1,
  });

  final bool lit;
  final Color color;
  final double diameter;

  /// 本颗在整组里的序号（错峰用）
  final int index;

  /// 本组总颗数（错峰切格用）
  final int count;

  @override
  State<_PipDot> createState() => _PipDotState();
}

class _PipDotState extends State<_PipDot>
    with SingleTickerProviderStateMixin {
  // value: 1.0 = 静止在终态不播；点亮瞬间 forward(from: 0) 播一次
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300), value: 1.0);
  late final Animation<double> _local = Tween(begin: 0.6, end: 1.0)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

  @override
  void didUpdateWidget(_PipDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.lit && widget.lit) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoundTransitionScope.maybeOf(context);
    // 编排层在场且正在转场 → 走错峰进度；否则用本地一次性动画
    final Animation<double> anim = (scope != null && scope.isPlaying)
        ? scope.staggered(widget.index, widget.count)
        : _local;
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) => Transform.scale(
        scale: anim.value,
        child: Container(
          width: widget.diameter,
          height: widget.diameter,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.lit
                ? widget.color
                : Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// 呼吸提示：暂停/待继续时「屏幕求人」的唯一时刻——
/// 提示音把用户的注意力叫来，这句话告诉他下一步。
/// 仅一行文本做透明度呼吸（局部动画，GPU 开销可忽略）。
class _BreathingPrompt extends StatefulWidget {
  const _BreathingPrompt({
    required this.text,
    required this.color,
    required this.scale,
  });

  final String text;
  final Color color;
  final double scale;

  @override
  State<_BreathingPrompt> createState() => _BreathingPromptState();
}

class _BreathingPromptState extends State<_BreathingPrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _opacity = Tween(begin: 0.35, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Text(
        widget.text,
        style: TextStyle(
            // 大程度缩小（PD 2026-10-06：30→16，求人提示只是余光信号，
            // 不该与轮次圈槽争抢视觉权重）
            fontSize: 16 * widget.scale,
            fontWeight: FontWeight.w700,
            color: widget.color),
      ),
    );
  }
}

/// 底部通栏进度条：番茄=本轮已走比例；正计时运行中=静态通栏（进行中指示，
/// 不做无限动画——性能 P1 原则）；无会话=空槽。
/// 番茄运行中叠加一道 6s 周期的高光流光（唯一常驻动画，慢到余光刚好
/// 感到「它在走」；暂停/idle/正计时立即停帧）。
class _GlanceProgressBar extends StatefulWidget {
  const _GlanceProgressBar({
    required this.progress,
    required this.running,
    required this.sweeping,
    required this.color,
    this.scale = 1.0,
  });

  final double? progress;
  final bool running;

  /// 是否播放流光（仅番茄运行中）
  final bool sweeping;
  final Color color;

  /// 视口高度缩放系数（条高随之缩放）
  final double scale;

  @override
  State<_GlanceProgressBar> createState() => _GlanceProgressBarState();
}

class _GlanceProgressBarState extends State<_GlanceProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    // 往返扫（到边界后原路返回）：高光始终在填充段内可见——单向扫
    // 到边界即跳回起点，肉眼「还没到边界就消失」（PD 2026-10-06）
    if (widget.sweeping) _sweep.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_GlanceProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sweeping && !_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    } else if (!widget.sweeping && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = widget.progress ?? (widget.running ? 1.0 : 0.0);
    final fillColor = widget.progress == null && widget.running
        ? widget.color.withValues(alpha: 0.4)
        : widget.color;
    final radius = 6 * widget.scale;
    final bar = SizedBox(
      height: radius,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final filled = constraints.maxWidth * fraction;
          return ClipRect(
            child: Stack(
              children: [
                Container(color: scheme.surfaceContainerHighest),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: filled,
                    color: fillColor,
                  ),
                ),
                // 流光：一道白色高光梯度扫过填充段（仅番茄运行中挂载）。
                // 高光全程保持在填充段内（0..filled-band），往返扫，
                // 不到边界就消失（PD 2026-10-06）
                if (widget.sweeping && filled > 0)
                  AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, _) {
                      final band = filled * 0.35;
                      final travel =
                          (filled - band).clamp(0.0, double.infinity) *
                              _sweep.value;
                      return Positioned(
                        top: 0,
                        bottom: 0,
                        width: band,
                        left: travel,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0x00FFFFFF),
                                Color(0x59FFFFFF),
                                Color(0x00FFFFFF),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
    return bar;
  }
}

/// 模式切换（横屏紧凑版）：番茄倒计时 / 正计时。会话进行中置灰。
class _GlanceModeSwitcher extends StatelessWidget {
  const _GlanceModeSwitcher({
    required this.state,
    required this.onSelect,
    this.scale = 1.0,
  });

  final FocusViewState state;
  final Future<bool> Function(TimerMode) onSelect;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30 * scale,
      child: SegmentedButton<TimerMode>(
        showSelectedIcon: false,
        style: ButtonStyle(
          textStyle: WidgetStateProperty.all(
              TextStyle(fontSize: 12 * scale)),
          visualDensity: VisualDensity.compact,
          padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 8)),
        ),
        segments: const [
          ButtonSegment(value: TimerMode.pomodoro, label: Text('番茄')),
          ButtonSegment(value: TimerMode.countUp, label: Text('正计时')),
        ],
        selected: {state.mode},
        onSelectionChanged: state.sessionActive
            ? null // 有进行中会话：置灰，防止切换语义混乱
            : (selection) => onSelect(selection.first),
      ),
    );
  }
}

// ------------------------------------------------------------------ 竖屏「余光」

/// 竖屏「余光」布局（2026-10-05 PD 定稿）：横屏同一套设计的**竖向重排**，
/// 不是新 UI——辉光管样式/阶段染色/进度条/幽灵按钮全部复用横屏组件。
///
/// 结构：中央竖排辉光管（分钟在上、句读居中、秒在下，逐管 odometer）；
/// 左列自上而下 设置 → 统计 → 番茄/正计时竖向胶囊 → FOCUS（竖排、列内
/// 垂直居中）→ 暂停 → 加时 → 终止（左下小方块）；右列 专注中 + 歌词
/// （无背景竖排单列，无音乐播放时整区隐藏）；右缘竖进度条（由下至上）；
/// 底部轮次豆 + 通栏粗进度条（由右向左，贴边无圆角同横屏）。
class _PortraitGlance extends ConsumerWidget {
  const _PortraitGlance({required this.state, required this.controller});

  final FocusViewState state;
  final FocusController controller;

  // 三个颜色逻辑与横屏 _GlanceLandscape 完全一致（专注/休息/暂停映射），
  // 在此独立实现，避免改动横屏代码。暂停同样沿用暂停前那一段的颜色
  // （[FocusViewState.colorPhase]，PD 2026-10-07）。

  Color _phaseColor(BuildContext context) {
    if (state.mode == TimerMode.countUp) {
      return switch (state.countUpPhase) {
        CountUpPhase.running || CountUpPhase.paused =>
          context.skin.focusRingColor,
        _ => Theme.of(context).colorScheme.outline,
      };
    }
    return switch (state.colorPhase) {
      TimerPhase.focusing => context.skin.focusRingColor,
      TimerPhase.shortBreak || TimerPhase.longBreak =>
        context.skin.breakRingColor,
      TimerPhase.paused => context.skin.focusRingColor,
      _ => Theme.of(context).colorScheme.outline,
    };
  }

  Color _clockColor(BuildContext context, GlanceColors colors) {
    if (state.mode == TimerMode.countUp) {
      return switch (state.countUpPhase) {
        CountUpPhase.running || CountUpPhase.paused => colors.focusClockColor,
        _ => Theme.of(context).colorScheme.outline,
      };
    }
    return switch (state.colorPhase) {
      TimerPhase.focusing => colors.focusClockColor,
      TimerPhase.shortBreak || TimerPhase.longBreak => colors.breakClockColor,
      TimerPhase.paused => colors.focusClockColor,
      _ => Theme.of(context).colorScheme.outline,
    };
  }

  Color _barColor(BuildContext context, GlanceColors colors) {
    if (state.mode == TimerMode.countUp) {
      return switch (state.countUpPhase) {
        CountUpPhase.running || CountUpPhase.paused => colors.focusBarColor,
        _ => Theme.of(context).colorScheme.outline,
      };
    }
    return switch (state.colorPhase) {
      TimerPhase.focusing => colors.focusBarColor,
      TimerPhase.shortBreak || TimerPhase.longBreak => colors.breakBarColor,
      TimerPhase.paused => colors.focusBarColor,
      _ => Theme.of(context).colorScheme.outline,
    };
  }

  bool get _awaitingTap =>
      state.mode == TimerMode.countUp
          ? state.countUpPhase == CountUpPhase.paused
          : state.phase == TimerPhase.paused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ref.watch(glanceColorsProvider);
    final glow = ref.watch(glowIntensityProvider) / 100;
    final phaseColor = _phaseColor(context);
    final clockColor = _clockColor(context, colors);
    final barColor = _barColor(context, colors);
    final isCountUp = state.mode == TimerMode.countUp;
    final total = state.phaseTotal.inMilliseconds;
    final progress = isCountUp
        ? null
        : total <= 0
            ? 0.0
            : (1 - state.remaining.inMilliseconds / total).clamp(0.0, 1.0);
    final running = isCountUp
        ? state.countUpPhase == CountUpPhase.running
        : switch (state.phase) {
            TimerPhase.focusing ||
            TimerPhase.shortBreak ||
            TimerPhase.longBreak =>
              true,
            _ => false,
          };
    final awaiting = _awaitingTap;
    final bgAlpha = awaiting ? 0.26 : 0.14;
    // 竖屏取宽高较小者为「高」做缩放锚点（与横屏同一套比例体系）
    final s = uiScaleForSize(
        MediaQuery.sizeOf(context).width, MediaQuery.sizeOf(context).height);
    final pad = MediaQuery.paddingOf(context);
    final numeral = ref.watch(clockNumeralProvider);

    return _PhasePulse(
      // 用 colorPhase 而非 phase：暂停不是换段，不该触发整屏脉冲
      // （PD 2026-10-07：暂停时颜色曾闪成休息色再跳回）。
      phaseKey: '${state.mode.name}-${state.colorPhase.name}-'
          '${state.countUpPhase.name}-${state.completedRounds}',
      color: phaseColor,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        color: Color.alphaBlend(
            phaseColor.withValues(alpha: bgAlpha), scheme.surface),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 竖屏以规则 2 池（竖构图壁纸）为主，与横屏各自独立抽图
            const StaticBackdrop(page: BgPage.focusPortrait),
            _Entrance(
              // 主区：三列固定/弹性宽度，杜绝 Stack 松散约束下的错位
              child: Padding(
                // 左右内边距对称（6*s）：Stack 中心 = 屏幕中心，
                // 辉光管严格左右居中（PD 2026-10-06）
                padding: EdgeInsets.fromLTRB(
                    6 * s + pad.left, 14 * s + pad.top, 6 * s + pad.right, 0),
                child: Column(
                  children: [
                    Expanded(
                      // Stack 而非三列 Row：辉光管始终整屏左右居中，
                      // 两侧轨道各挂各的，轨道宽度差不再带动时钟偏移
                      // （PD 2026-10-06：辉光管左右居中，勿动）。
                      child: Stack(
                        children: [
                          LayoutBuilder(
                            builder: (context, c) => Center(
                              child: ConstrainedBox(
                                // 限高基准 80%：阿拉伯 1.15 档再 ×1.05（封顶
                                // 97%，不顶出屏幕）、中文句读 0.95 档再 ×1.05
                                //（PD 2026-10-06：辉光管再放大至 105%）
                                constraints: BoxConstraints(
                                  maxHeight: c.maxHeight *
                                      (numeral == ClockNumeral.arabic
                                          ? 0.97
                                          : 0.88 * 0.95 * 1.05),
                                  maxWidth: c.maxWidth,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  // 整钟独立重绘层：兄弟节点（歌词轮询、
                                  // L 带流光、阶段染色过渡）的帧不再带动
                                  // 时钟重绘（PD 2026-10-06 卡顿优化）
                                  child: RepaintBoundary(
                                    child: _VerticalGlanceClock(
                                      state: state,
                                      color: clockColor,
                                      glow: glow,
                                      scale: s,
                                      numeral: numeral,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            // 再左移一点点（PD 2026-10-06）；外 Padding 还有
                            // 6*s+pad.left 兜底，不会贴到屏缘外
                            left: -2 * s,
                            top: 0,
                            bottom: 0,
                            child: SizedBox(
                              width: 48 * s,
                              child: _PortraitLeftRail(
                                state: state,
                                controller: controller,
                                color: phaseColor,
                                glow: glow,
                                scale: s,
                              ),
                            ),
                          ),
                          // 下一阶段（竖屏右下小方块）：与左下终止方块左右
                          // 对称、同尺寸；压在歌词图层**下面**（先画它，右轨
                          // 后画盖在上面）——右轨整体 IgnorePointer，歌词
                          // 遮上来也不挡点击（PD 2026-10-06）
                          Positioned(
                            right: 15 * s,
                            bottom: 0,
                            child: Opacity(
                              opacity: state.sessionActive ? 1 : 0.4,
                              child: _SkipSquareButton(
                                onTap: controller.skipPhase,
                                scale: s,
                                fill: const Color(0xFFDCF4FF)
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          Positioned(
                            // 右缘留出竖进度条位（14*s）+ 外 padding
                            right: 15 * s,
                            top: 0,
                            bottom: 0,
                            width: 78 * s,
                            child: IgnorePointer(
                              child: _PortraitRightRail(
                                state: state,
                                color: phaseColor,
                                clockColor: clockColor,
                                scale: s,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 底部区：求人提示 / 轮次豆 / 打点数（与下方通栏条留距，
                    // 24*s 保证呼吸提示不被底部进度条压住——条高 10*s 再留余量）
                    // 固定槽高（PD 2026-10-06）：awaiting 提示词与轮次圈共用
                    // 同一个 40*s 高的槽——按播放后只有内容替换、槽高不变，
                    // 上方辉光管区域不再被挤压跳动
                    SizedBox(
                      height: 40 * s,
                      child: Center(
                        child: awaiting
                            ? _BreathingPrompt(
                                color: phaseColor,
                                text: state.mode == TimerMode.countUp ||
                                        state.completedRounds == 0 &&
                                            state.phase != TimerPhase.completed
                                    ? '按播放键继续'
                                    : '按播放键，开始下一轮',
                                scale: s,
                              )
                            : !isCountUp &&
                                    state.phase != TimerPhase.idle &&
                                    state.phase != TimerPhase.completed
                                ? _RoundPips(
                                    state: state,
                                    color: phaseColor,
                                    scale: s)
                                : isCountUp && state.markCount > 0
                                    ? Text('打点 ${state.markCount} 个',
                                        style: TextStyle(
                                            fontSize: 14 * s,
                                            color: scheme.onSurfaceVariant))
                                    : const SizedBox.shrink(),
                      ),
                    ),
                    // 底部留白 16*s（PD 2026-10-06：整体下移从底部分摊——
                    // 压缩此间距让 Expanded 区增高，辉光管中心随之下移；
                    // 仍高于通栏进度条顶面，提示词不被压）
                    SizedBox(height: 16 * s),
                  ],
                ),
              ),
            ),
            // L 形进度带：右缘竖条 + 底部通栏条由同一条带圆角拐角的路径
            // 描边而成，填充从拐角起沿竖条向上、再沿底条向左推进——
            // 拐角圆角是路径自带的，不可能「看不到」（PD 2026-10-06）
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: pad.bottom,
              child: IgnorePointer(
                child: _PortraitLProgressBar(
                  progress: progress,
                  running: isCountUp && running,
                  // 流光对齐横屏源码语义：仅番茄运行中（focusing/休息段），
                  // 暂停/idle/正计时一律静态（性能 P1 原则）
                  sweeping: !isCountUp && running,
                  color: barColor,
                  scale: s,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 左列控件轨（竖屏）：设置 → 统计 → 模式切换（纯文字 + 辉光线）→
/// FOCUS（列内居中）→ 暂停 / 加时（比横屏侧键加大）→ 终止（左下小方块）。
class _PortraitLeftRail extends StatelessWidget {
  const _PortraitLeftRail({
    required this.state,
    required this.controller,
    required this.color,
    required this.glow,
    required this.scale,
  });

  final FocusViewState state;
  final FocusController controller;
  final Color color;

  /// 辉光亮度系数（与辉光管同一设置，透传给辉光分隔线）。
  final double glow;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final isCountUp = state.mode == TimerMode.countUp;
    final running = isCountUp
        ? state.countUpPhase == CountUpPhase.running
        : switch (state.phase) {
            TimerPhase.focusing ||
            TimerPhase.shortBreak ||
            TimerPhase.longBreak =>
              true,
            _ => false,
          };
    // 七个图标等距布置在左轨（PD 2026-10-06）：设置 → 统计 → 番茄/正计时
    // → FOCUS → 暂停 → 加时 → 终止。spaceBetween 让首尾贴近上下边界；
    // 窄轨内居中——七项共用一条竖向中心线（PD：竖向中心线对齐）。
    // 暂停/开始切换只换字形，位置不再随状态抖动。
    // 竖屏六键统一样式（PD 2026-10-06）：设置/统计/暂停/加时四个幽灵图标
    // + 终止/下一阶段两个方块——全部 60% 透明度、#dcf4ff 冷白。
    const keyColor = Color(0xFFDCF4FF);
    const keyOpacity = 0.6;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _GhostIconButton(
          size: 22 * s,
          icon: Icons.settings,
          semanticLabel: '设置',
          color: keyColor,
          opacity: keyOpacity,
          onTap: () => Navigator.of(context).pushNamed('/settings'),
        ),
        _GhostIconButton(
          size: 22 * s,
          icon: Icons.bar_chart,
          semanticLabel: '使用统计',
          color: keyColor,
          opacity: keyOpacity,
          onTap: () => Navigator.of(context).pushNamed('/stats'),
        ),
        _PortraitModeSwitcher(
            state: state,
            onSelect: controller.setMode,
            color: color,
            glow: glow,
            scale: s),
        _VerticalKicker(color: color, scale: s),
        _GhostIconButton(
          size: 34 * s,
          icon: running ? Icons.pause_rounded : Icons.play_arrow_rounded,
          semanticLabel: running ? '暂停' : '开始或继续',
          color: keyColor,
          opacity: keyOpacity,
          onTap: controller.tapPrimaryButton,
        ),
        _GhostIconButton(
          size: 34 * s,
          icon: isCountUp ? Icons.flag_outlined : Icons.add,
          semanticLabel: isCountUp ? '打时间标记点' : '加五分钟',
          color: keyColor,
          opacity: keyOpacity,
          onTap: controller.addFiveMinutes,
        ),
        // 终止：无进行中会话时是空操作，置灰提示「现在按了也没用」
        Opacity(
          opacity: state.sessionActive ? 1 : 0.4,
          child: _StopSquareButton(
              onTap: controller.finishSession,
              scale: s,
              fill: keyColor.withValues(alpha: keyOpacity)),
        ),
      ],
    );
  }
}

/// 模式切换（竖屏，2026-10-06 重做）：**无胶囊背景**——纯竖排文字
/// 「番茄 / 正计时」，中间一条白色辉光横线分隔。辉光线与辉光管共用
/// 设置里的辉光亮度（0 = 线也熄），但刻意更暗淡（alpha 更低、 blur
/// 更小）；线长略长于文字（「正计时」三字列宽约 40*s，线取 44*s）。
class _PortraitModeSwitcher extends StatelessWidget {
  const _PortraitModeSwitcher({
    required this.state,
    required this.onSelect,
    required this.color,
    required this.glow,
    required this.scale,
  });

  final FocusViewState state;
  final Future<bool> Function(TimerMode) onSelect;
  final Color color;

  /// 辉光亮度系数（设置 0–150% / 100），与辉光管同一旋钮。
  final double glow;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final enabled = !state.sessionActive;
    Widget cell(TimerMode mode, String label) {
      final selected = state.mode == mode;
      return InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? () => onSelect(mode) : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ch in label.split(''))
              Text(
                ch,
                style: TextStyle(
                  fontSize: 13 * s,
                  height: 1.15,
                  color: selected
                      ? color
                      : Colors.white.withValues(alpha: 0.6),
                  shadows: selected
                      ? [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
                      : null,
                ),
              ),
          ],
        ),
      );
    }

    // 辉光线：比管暗淡一档但仍醒目（PD 2026-10-06：再亮一点）——
    // alpha 0.6×glow（管是 0.9×glow），本体亮度也随辉光旋钮走
    final glowAlpha = (0.6 * glow).clamp(0.0, 1.0);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          cell(TimerMode.pomodoro, '番茄'),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 7 * s),
            child: Container(
              width: 44 * s,
              height: 1.2 * s,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                    alpha: (0.65 + 0.35 * glow).clamp(0.0, 1.0)),
                boxShadow: glow > 0
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: glowAlpha),
                          blurRadius: 6 * s,
                          spreadRadius: 0.6 * s,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
          cell(TimerMode.countUp, '正计时'),
        ],
      ),
    );
  }
}

/// FOCUS 竖排字标：横屏 kicker 的竖排等价——衬线大写字母逐字成列，
/// 上下各一条短横线（横屏短横线旋转 90°）。
class _VerticalKicker extends StatelessWidget {
  const _VerticalKicker({required this.color, required this.scale});

  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final lineColor = color.withValues(alpha: 0.45);
    final style = TextStyle(
      fontSize: 13 * s,
      fontWeight: FontWeight.w600,
      color: color.withValues(alpha: 0.75),
      shadows: [Shadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 1.5, height: 20 * s, color: lineColor),
        SizedBox(height: 8 * s),
        for (final ch in 'FOCUS'.split('')) ...[
          Text(ch, style: style),
          SizedBox(height: 4 * s),
        ],
        SizedBox(height: 4 * s),
        Container(width: 1.5, height: 20 * s, color: lineColor),
      ],
    );
  }
}

/// 终止按钮（竖屏左下小方块）：白色实心圆角方块，与长按实体键同语义
///（结束会话并保存记录）。红色仅作按压态反馈。
class _StopSquareButton extends StatelessWidget {
  const _StopSquareButton({
    required this.onTap,
    required this.scale,
    this.fill = Colors.white,
  });

  final VoidCallback onTap;
  final double scale;

  /// 方块填充色（竖屏六键统一 #dcf4ff @60%）。
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Semantics(
      button: true,
      label: '结束并保存',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40 * s,
            height: 40 * s,
            child: Center(
              child: Container(
                width: 16 * s,
                height: 16 * s,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(3 * s),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 3),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 下一阶段按钮（竖屏右下小方块，2026-10-06）：与左下 [_StopSquareButton]
/// 左右对称、同尺寸同语言——白色实心圆角方块，内嵌「跳到下一阶段」 glyph
/// （skip-next）。番茄 = 跳过当前阶段；正计时由命令总线降级为打点。
/// 无进行中会话时置灰（与终止一致）。
class _SkipSquareButton extends StatelessWidget {
  const _SkipSquareButton({
    required this.onTap,
    required this.scale,
    this.fill = Colors.white,
  });

  final VoidCallback onTap;
  final double scale;

  /// 方块填充色（竖屏六键统一 #dcf4ff @60%）。
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Semantics(
      button: true,
      label: '下一阶段',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40 * s,
            height: 40 * s,
            child: Center(
              child: Container(
                width: 16 * s,
                height: 16 * s,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(3 * s),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 3),
                  ],
                ),
                child: Icon(
                  Icons.skip_next_rounded,
                  size: 12 * s,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 右列（竖屏）：阶段词（专注中）+ 歌词竖排单列。
class _PortraitRightRail extends StatelessWidget {
  const _PortraitRightRail({
    required this.state,
    required this.color,
    required this.clockColor,
    required this.scale,
  });

  final FocusViewState state;
  final Color color;

  /// 辉光管当前色（阶段色）：歌词「同步辉光管」模式的数据源。
  final Color clockColor;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Padding(
      // 整列贴近右缘进度条（PD 2026-10-06：稍微右移、贴近进度条；
      // 6*s = 竖条 10*s 已占的右缘里再留的视觉余量）
      padding: EdgeInsets.only(right: 6 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            state.mode == TimerMode.countUp
                ? state.countUpPhase.label
                : state.phase.label,
            style: TextStyle(
              // 微放大一点点（18→19，不换行：仍是单行短词）
              fontSize: 19 * s,
              fontWeight: FontWeight.w700,
              color: color,
              shadows: [Shadow(color: color.withValues(alpha: 0.55), blurRadius: 8)],
            ),
          ),
          SizedBox(height: 18 * s),
          Flexible(child: _LyricColumn(scale: s, clockColor: clockColor)),
        ],
      ),
    );
  }
}

/// 歌词列（竖屏）：无背景、竖排、单列，样式与「专注中」同款压壁纸直排。
/// 数据源 = 外部媒体会话（2s 轮询，仅本区存活期间）；有 .lrc 显示当前
/// 行，没有则显示「歌名 · 歌手」；无外部播放时整区隐藏。
/// 换行动画 = 横向版 odometer：新行自左向右滑入替换旧行（400ms，
/// 比辉光管的下翻简单一档）；时机由 200ms 本地节拍外推播放位置——
/// 不等 2s 轮询，到点即换（PD 2026-10-06）。
class _LyricColumn extends ConsumerStatefulWidget {
  const _LyricColumn({required this.scale, required this.clockColor});

  final double scale;

  /// 辉光管当前色（阶段色），「同步辉光管」开启时作歌词颜色。
  final Color clockColor;

  @override
  ConsumerState<_LyricColumn> createState() => _LyricColumnState();
}

class _LyricColumnState extends ConsumerState<_LyricColumn> {
  /// 本地节拍：2s 轮询只是采样点，播放中按流逝时间外推播放位置，
  /// 换行时机误差 ≤ 200ms（而不是干等下一次轮询）
  Timer? _estimator;
  final Stopwatch _sw = Stopwatch();
  int _basePosMs = 0;

  @override
  void initState() {
    super.initState();
    ref.read(nowPlayingProvider.notifier).acquire();
    _estimator = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _estimator?.cancel();
    ref.read(nowPlayingProvider.notifier).release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 快照到达即重锚：基线位置 + 到达时刻；暂停则停止外推
    ref.listen<NowPlaying?>(nowPlayingProvider, (_, next) {
      _basePosMs = next?.positionMs ?? 0;
      _sw
        ..stop()
        ..reset();
      if (next?.playing ?? false) _sw.start();
    });
    final np = ref.watch(nowPlayingProvider);
    if (np == null) return const SizedBox.shrink();
    final positionMs = _basePosMs + _sw.elapsedMilliseconds;
    final lrc = ref
        .watch(lrcProvider((np.title, np.artist)))
        .valueOrNull;
    final line = lrc == null ? null : lrcLineAt(lrc, Duration(milliseconds: positionMs));
    final display = (line != null && line.text.isNotEmpty)
        ? line.text
        : (np.artist.isEmpty ? np.title : '${np.title} · ${np.artist}');
    // 固定字号（不随内容长度缩放——变长的是列，不是字）；字号/颜色可在
    // 设置页「歌词」三项里调；字体 = files/lyrics/fonts/ 下选中的 .ttf/.otf；
    // 「同步辉光管」开启时颜色 = 计时阶段色（变阶段即变）。
    final fontName = ref.watch(lyricFontProvider).valueOrNull;
    final fontSize = ref.watch(lyricFontSizeProvider);
    final followClock = ref.watch(lyricFollowClockProvider);
    final lyricArgb =
        followClock ? widget.clockColor.toARGB32() : ref.watch(lyricColorProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // 从左到右替换：新行自左侧滑入，旧行原地淡出（比辉光管的下翻
      // 简单一档，时长同为 400ms——PD 2026-10-06）
      transitionBuilder: (child, animation) {
        final isNew = child.key == ValueKey<String>(display);
        final slide = Tween<Offset>(
          begin: isNew ? const Offset(-0.5, 0) : Offset.zero,
          end: Offset.zero,
        ).animate(animation);
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: Column(
        key: ValueKey<String>(display),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final ch in display.split(''))
            Padding(
              padding: EdgeInsets.only(bottom: 3.5 * widget.scale),
              child: Text(
                ch,
                style: TextStyle(
                  fontSize: fontSize * widget.scale,
                  height: 1.1,
                  fontFamily: fontName == null ? null : 'LyricFont',
                  color: Color(lyricArgb),
                  shadows: [
                    Shadow(
                        color: Colors.black.withValues(alpha: 0.7),
                        blurRadius: 6),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 竖排辉光管时钟：横屏 _GlanceClock 的竖排等价——分钟两位在上、
/// 句读居中、秒两位在下（逐管 odometer 与辉光/空心暂停语义完全一致）；
/// 中文数字体系下冒号变句读 ○，暂停时变 ● 且缩至 80%。
class _VerticalGlanceClock extends StatelessWidget {
  const _VerticalGlanceClock({
    required this.state,
    required this.color,
    required this.glow,
    required this.scale,
    required this.numeral,
  });

  final FocusViewState state;
  final Color color;
  final double glow;
  final double scale;
  final ClockNumeral numeral;

  @override
  Widget build(BuildContext context) {
    final isCountUp = state.mode == TimerMode.countUp;
    final paused = isCountUp
        ? state.countUpPhase == CountUpPhase.paused
        : state.phase == TimerPhase.paused;
    final base = TextStyle(
      fontSize: 240 * scale,
      height: 1.0,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final glowShadows = glow <= 0
        ? null
        : [
            Shadow(color: color.withValues(alpha: 0.9 * glow), blurRadius: 18),
            Shadow(color: color.withValues(alpha: 0.5 * glow), blurRadius: 45),
            Shadow(color: color.withValues(alpha: 0.3 * glow), blurRadius: 90),
          ];
    final style = paused
        ? base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = color)
        : base.copyWith(color: color, shadows: glowShadows);
    final dur = isCountUp ? state.elapsed : state.remaining;
    final glyphs = <String>[
      // 超 1 小时补小时两位（正计时长跑场景）
      if (dur.inHours > 0) ...clockGlyphPair(dur.inHours, numeral),
      ...clockGlyphPair(dur.inMinutes.remainder(60), numeral),
      ...clockGlyphPair(dur.inSeconds.remainder(60), numeral),
    ];
    final minuteCount =
        dur.inHours > 0 ? 4 : 2; // 分隔符前是分钟两位（+可选小时两位）
    // 分隔符：阿拉伯数字 = 横屏同款全尺寸冒号字形、**横放**（PD
    // 2026-10-06：竖排布局里两点竖着的冒号太弱，旋转 90° 成横向两点），
    // 字号/辉光/暂停描边与数字完全一致；中文句读不用字体字形（大字重下
    // ○ 会露出边角的非正圆），改绘制正圆：运行=空心环，暂停=实心圆点
    // 且整体缩至 80%。
    final separator = numeral == ClockNumeral.arabic
        ? AnimatedScale(
            scale: paused ? 0.8 : 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: RotatedBox(
              quarterTurns: 1,
              child: Text(':', style: style),
            ),
          )
        : _TodouMark(
            diameter: 64 * scale,
            color: color,
            filled: paused,
            glow: glow,
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < glyphs.length; i++) ...[
          _OdometerDigit(char: glyphs[i], style: style),
          if (i == minuteCount - 1) separator,
        ],
      ],
    );
  }
}

/// 句读符（中文数字体系的分隔符）：几何绘制的正圆——运行 = 空心圆环
///（字标 ○），暂停 = 实心圆点（●）并缩至 80%。字体 ○ 在大字号下
/// 轮廓不圆（能看到边边角角），故不用字形。
class _TodouMark extends StatelessWidget {
  const _TodouMark({
    required this.diameter,
    required this.color,
    required this.filled,
    required this.glow,
  });

  final double diameter;
  final Color color;

  /// true = 暂停实心点；false = 运行空心环。
  final bool filled;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: filled ? 0.8 : 1.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
        width: diameter,
        height: diameter,
        margin: EdgeInsets.symmetric(vertical: diameter * 0.6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color : Colors.transparent,
          border: filled
              ? null
              : Border.all(color: color, width: (diameter * 0.14).clamp(2.0, 8.0)),
          boxShadow: glow > 0
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: (filled ? 0.6 : 0.45) * glow),
                    blurRadius: diameter * 0.55,
                    spreadRadius: diameter * 0.05,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

/// L 形进度带（竖屏）：右缘竖条 + 底部通栏条不再是两条独立 Widget，
/// 而是**同一条带圆角拐角的路径**（中心线：竖条中轴 → 四分之一圆弧 →
/// 底条中轴），描边宽度 = 条粗。拐角圆角由路径几何保证，与壁纸对比
/// 必然可见（PD 2026-10-06：圆角把两条连起来，像手机边缘一样）。
///
/// 填充从屏幕右下角起：先沿竖条由下至上，过拐角后再沿底条由右向左
/// ——与旧版两条各自的填充方向完全一致，进度语义不变。
class _PortraitLProgressBar extends StatefulWidget {
  const _PortraitLProgressBar({
    required this.progress,
    required this.running,
    required this.color,
    required this.scale,
    this.sweeping = false,
  });

  final double? progress;
  final bool running;
  final Color color;
  final double scale;

  /// 番茄运行中流光（与横屏通栏条同一开关语义）。
  final bool sweeping;

  @override
  State<_PortraitLProgressBar> createState() => _PortraitLProgressBarState();
}

class _PortraitLProgressBarState extends State<_PortraitLProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.sweeping) _sweep.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PortraitLProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sweeping && !_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    } else if (!widget.sweeping && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = (widget.progress ?? (widget.running ? 1.0 : 0.0))
        .clamp(0.0, 1.0);
    final fillColor = widget.progress == null && widget.running
        ? widget.color.withValues(alpha: 0.4)
        : widget.color;
    final painter = _LBandPainter(
      fraction: fraction,
      fillColor: fillColor,
      trackColor: scheme.surfaceContainerHighest,
      thickness: 10 * widget.scale,
      // 拐角半径沿用此前两条约定的 24*s，同时不超出带形可走空间
      cornerRadius: 24 * widget.scale,
      sweeping: widget.sweeping && fraction > 0,
      sweepPhase: _sweep.value,
    );
    if (!widget.sweeping) return CustomPaint(painter: painter);
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, _) => CustomPaint(
        painter: painter.copyWith(sweepPhase: _sweep.value),
      ),
    );
  }
}

/// L 带几何 + 绘制（纯绘制器，几何见 [_PortraitLProgressBar] 注释）。
class _LBandPainter extends CustomPainter {
  _LBandPainter({
    required this.fraction,
    required this.fillColor,
    required this.trackColor,
    required this.thickness,
    required this.cornerRadius,
    required this.sweeping,
    required this.sweepPhase,
  });

  final double fraction;
  final Color fillColor;
  final Color trackColor;
  final double thickness;
  final double cornerRadius;
  final bool sweeping;
  final double sweepPhase;

  _LBandPainter copyWith({double? sweepPhase}) => _LBandPainter(
        fraction: fraction,
        fillColor: fillColor,
        trackColor: trackColor,
        thickness: thickness,
        cornerRadius: cornerRadius,
        sweeping: sweeping,
        sweepPhase: sweepPhase ?? this.sweepPhase,
      );

  /// 带形中心线路径：竖条中轴（顶）→ 圆弧（右下角）→ 底条中轴（左端）。
  Path _centerline(Size size, double r) {
    final w = size.width;
    final h = size.height;
    final x = w - thickness / 2; // 竖条中轴 x
    final y = h - thickness / 2; // 底条中轴 y
    return Path()
      ..moveTo(x, thickness / 2)
      ..lineTo(x, y - r)
      ..arcTo(Rect.fromCircle(center: Offset(x - r, y - r), radius: r), 0,
          pi / 2, false)
      ..lineTo(thickness / 2, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = cornerRadius
        .clamp(0.0, (size.height - thickness) / 2)
        .toDouble();
    final path = _centerline(size, r);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, trackPaint);
    if (fraction <= 0) return;

    final metrics = path.computeMetrics().first;
    final total = metrics.length;
    final fillLen = total * fraction;
    // 填充段 = 路径的「拐角端」起 fillLen：竖条先满、再过拐角、最后底条
    final fillPath = metrics.extractPath(total - fillLen, total);
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(fillPath, fillPaint);

    if (!sweeping || fillLen <= thickness) return;
    // 流光：一道柔和高光**跟随填充推进方向**往返扫——从已填充的远端
    // （底条左端，竖条满时 = 顶端）扫向填充前沿（拐角方向），即肉眼
    // 上的「从左到右、再向上」，与进度流向一致（PD 2026-10-06）。
    // 质感 = 三层递减透明度的描边叠出柔边（无 MaskFilter 模糊，锐利
    // 且 GPU 开销小），替代上一版单层高斯模糊 blob。
    final band = fillLen * 0.35;
    final start = total - band - (fillLen - band) * sweepPhase;
    final bandPath = metrics.extractPath(start, start + band);
    final layers = <(double, double)>[
      (1.0, 0.10),
      (0.7, 0.13),
      (0.45, 0.18),
    ];
    for (final (widthFrac, alpha) in layers) {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * widthFrac
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(bandPath, paint);
    }
  }

  @override
  bool shouldRepaint(_LBandPainter old) =>
      old.fraction != fraction ||
      old.fillColor != fillColor ||
      old.trackColor != trackColor ||
      old.thickness != thickness ||
      old.cornerRadius != cornerRadius ||
      old.sweeping != sweeping ||
      old.sweepPhase != sweepPhase;
}

// ------------------------------------------------------------------ 竖屏回退

/// 竖屏布局（回退保险）：单列纵向信息流。
class _PortraitLayout extends StatelessWidget {
  const _PortraitLayout({required this.state, required this.controller});

  final FocusViewState state;
  final FocusController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _PhaseHeader(state: state),
          const SizedBox(height: 4),
          _ModeSwitcher(state: state, onSelect: controller.setMode),
          const SizedBox(height: 4),
          Expanded(child: _CountdownRing(state: state)),
          const SizedBox(height: 8),
          _KeyHintCard(state: state),
          const SizedBox(height: 12),
          _BottomBar(state: state, onPrimary: controller.tapPrimaryButton),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// 顶部：当前阶段 + 已完成轮数/打点数 + 按键接管状态。
class _PhaseHeader extends StatelessWidget {
  const _PhaseHeader({required this.state});

  final FocusViewState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          state.mode == TimerMode.countUp
              ? state.countUpPhase.label
              : state.phase.label,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        Row(
          children: [
            if (state.keysAcquired)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.headset, size: 18),
              ),
            Text(
              state.mode == TimerMode.countUp
                  ? '打点 ${state.markCount} 个'
                  : '第 ${state.completedRounds + 1} 轮',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ],
    );
  }
}

/// 模式切换器：番茄倒计时 / 正计时。会话进行中置灰。
class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.state, required this.onSelect});

  final FocusViewState state;
  final Future<bool> Function(TimerMode) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: SegmentedButton<TimerMode>(
        showSelectedIcon: false,
        style: ButtonStyle(
          textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          visualDensity: VisualDensity.compact,
        ),
        segments: const [
          ButtonSegment(value: TimerMode.pomodoro, label: Text('番茄倒计时')),
          ButtonSegment(value: TimerMode.countUp, label: Text('正计时')),
        ],
        selected: {state.mode},
        onSelectionChanged: state.sessionActive
            ? null // 有进行中会话：置灰，防止切换语义混乱
            : (selection) => onSelect(selection.first),
      ),
    );
  }
}

/// 中部：计时圆环 + 超大号时间（竖屏回退用）。番茄=剩余时间+进度；正计时=累计。
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.state});

  final FocusViewState state;

  @override
  Widget build(BuildContext context) {
    final isCountUp = state.mode == TimerMode.countUp;
    const diameter = 240.0;
    final fontSize = (diameter * 0.35).clamp(56.0, 96.0);
    final total = state.phaseTotal.inMilliseconds;
    final progress = isCountUp
        ? null
        : total <= 0
            ? 0.0
            : (1 - state.remaining.inMilliseconds / total).clamp(0.0, 1.0);
    // 暂停沿用暂停前那一段的环色（colorPhase）——原代码把 paused 硬编码成
    // 专注色，休息阶段暂停会闪成专注色。
    final ringColor = switch (state.colorPhase) {
      TimerPhase.focusing => context.skin.focusRingColor,
      TimerPhase.shortBreak || TimerPhase.longBreak =>
        context.skin.breakRingColor,
      // 引擎没记住暂停前阶段（不该发生）：退回专注色，别落到灰
      TimerPhase.paused => context.skin.focusRingColor,
      _ => Theme.of(context).colorScheme.outline,
    };

    return Center(
      child: RepaintBoundary(
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: isCountUp
                      ? (state.countUpPhase == CountUpPhase.running ? 1.0 : 0.0)
                      : progress,
                  strokeWidth: 10,
                  color: isCountUp ? context.skin.focusRingColor : ringColor,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              Text(
                formatDurationClock(
                    isCountUp ? state.elapsed : state.remaining),
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 按键提示卡（竖屏回退用）：实体键 → 功能说明；最近触发的命令高亮。
class _KeyHintCard extends StatelessWidget {
  const _KeyHintCard({required this.state});

  final FocusViewState state;

  @override
  Widget build(BuildContext context) {
    final isCountUp = state.mode == TimerMode.countUp;
    final hints = <(String, String, AppCommand?)>[
      ('播放/暂停 · 单按', '开始 / 暂停', AppCommand.toggleStartPause),
      ('播放/暂停 · 长按', '结束并保存', AppCommand.finishSession),
      if (!isCountUp) ('下一曲', '跳过当前阶段', AppCommand.skipPhase),
      ('上一曲', isCountUp ? '打时间标记点' : '+5 分钟', AppCommand.addFiveMinutes),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            for (final (keyName, action, command) in hints)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(keyName,
                          style: const TextStyle(fontSize: 14)),
                    ),
                    Text(
                      action,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: state.lastCommand == command
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: state.lastCommand == command
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
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

/// 标签入口（US-B05）：idle/完成态显示，点击选择或新建标签；
/// 选中的标签在下一次会话开始时烙印到 drift 行（可复盘）。
class _TagChip extends ConsumerWidget {
  const _TagChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tag = ref.watch(currentTagProvider);
    return ActionChip(
      avatar: const Icon(Icons.label_outline, size: 16),
      label: Text(tag ?? '加标签', style: const TextStyle(fontSize: 13)),
      visualDensity: VisualDensity.compact,
      onPressed: () => _showTagSheet(context, ref),
    );
  }

  Future<void> _showTagSheet(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(currentTagProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('本次专注标签',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.label_off_outlined),
              title: const Text('无标签'),
              onTap: () {
                notifier.setTag(null);
                Navigator.of(context).pop();
              },
            ),
            for (final t in ref.watch(currentTagProvider.notifier).savedTags)
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: Text(t),
                trailing: IconButton(
                  tooltip: '从清单删除',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => notifier.removeSavedTag(t),
                ),
                onTap: () {
                  notifier.setTag(t);
                  Navigator.of(context).pop();
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建标签'),
              onTap: () async {
                final input = await _askNewTag(context);
                if (input != null && input.isNotEmpty) {
                  await notifier.setTag(input);
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askNewTag(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '如：编程、写作、阅读'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result;
  }
}

/// 横屏主操作按钮（触屏备用）：运行中隐藏，idle / 暂停 / 完成态出现。
/// 与「单按」共用一个后端入口 [FocusController.tapPrimaryButton]。
class _GlancePrimaryButton extends StatelessWidget {
  const _GlancePrimaryButton({
    required this.state,
    required this.onPressed,
    this.scale = 1.0,
  });

  final FocusViewState state;
  final VoidCallback onPressed;
  final double scale;

  String get _label {
    if (state.mode == TimerMode.countUp) {
      return switch (state.countUpPhase) {
        CountUpPhase.idle || CountUpPhase.finished => '开始专注',
        CountUpPhase.paused => '继续',
        CountUpPhase.running => '暂停',
      };
    }
    return switch (state.phase) {
      TimerPhase.idle || TimerPhase.completed => '开始专注',
      TimerPhase.paused => '继续',
      _ => '暂停',
    };
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: Size(168 * scale, 52 * scale),
        textStyle: TextStyle(
            fontSize: 20 * scale, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      child: Text(_label),
    );
  }
}

/// 底部操作区（竖屏回退用）：大按钮（触屏备用）+ 统计 / 设置入口。
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state, required this.onPrimary});

  final FocusViewState state;
  final VoidCallback onPrimary;

  String _primaryText() {
    if (state.mode == TimerMode.countUp) {
      return switch (state.countUpPhase) {
        CountUpPhase.idle || CountUpPhase.finished => '开始专注',
        CountUpPhase.paused => '继续',
        CountUpPhase.running => '暂停',
      };
    }
    return switch (state.phase) {
      TimerPhase.idle || TimerPhase.completed => '开始专注',
      TimerPhase.paused => '继续',
      _ => '暂停',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          iconSize: 32,
          tooltip: '使用统计',
          onPressed: () => Navigator.of(context).pushNamed('/stats'),
          icon: const Icon(Icons.bar_chart),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              textStyle:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            onPressed: onPrimary,
            child: Text(_primaryText()),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          iconSize: 32,
          tooltip: '设置',
          onPressed: () => Navigator.of(context).pushNamed('/settings'),
          icon: const Icon(Icons.settings),
        ),
      ],
    );
  }
}
