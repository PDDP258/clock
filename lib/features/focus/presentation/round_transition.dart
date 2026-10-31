/// 轮次转场编排层（2026-10-06，看板 #62）：把「阶段/轮次/模式变化」编成
/// 一条三段式时间轴，而不是让各元素在同一帧里各自乱动。
///
/// ## 为什么需要编排
///
/// 转场前横屏已有零散动画：整屏脉冲 900ms、背景染色 700ms、巨钟逐位
/// odometer 400ms、轮次豆点亮 300ms。单看每条都合理，**同时发生**就是一团
/// ——余光扫一眼只读出「屏幕抖了一下」，读不出「换段了」。本层把它们排成：
///
/// ```
/// 0    160      260 480          700              1200ms
/// | 退场 |       | 换  场 |       |    落    定    |
///  ├─ 旧内容整体下沉淡出（0→260ms，唯一离场动作）
///        ├─ 阶段字标换位（160→640ms）
///        ├─ 巨钟数字回滚换色（200→700ms）
///              ├─ 轮次豆依次点亮（520→1200ms，每颗 80ms 间隔）
/// ```
///
/// 设计纪律（沿用本项目 P1 性能原则）：
/// - **单控制器**：一个 [AnimationController] 走完 1200ms，子元素只按
///   不同 [Interval] 取值——任何时刻只有一层在动，帧成本恒定；
/// - **一次性**：不播常驻动画（倒计时每秒的数字滚动是常驻节奏，走原有
///   odometer，不受本层影响）；
/// - **不动时零成本**：controller 静止在终值，各子元素取到终态，
///   与改造前逐像素一致。
///
/// 档位（[TransitionIntensity]）：`lite` 只留豆子点亮，`off` 全瞬切。
library;

import 'package:flutter/widgets.dart';

import '../application/transition_settings.dart';

/// 三段动画的时长常量（集中在此，便于统一微调）。
class RoundTransitionTiming {
  const RoundTransitionTiming._();

  /// 全程时长（毫秒）。`off` 档不用它。
  static const int totalMs = 1200;

  /// 第一段：旧内容下沉淡出。
  static const int exitMs = 260;

  /// 第二段：阶段字标换位。
  static const int kickerMs = 480;

  /// 第二段：巨钟数字回滚换色。
  static const int clockMs = 500;

  /// 第三段：轮次豆依次点亮的**单颗**时长。
  static const int pipMs = 320;

  /// 轮次豆依次点亮的**间隔**。
  static const int pipStaggerMs = 80;

  /// 退场位移（向下沉，正值 = 下沉；按视口高度的比例）。
  static const double exitShift = 0.055;

  /// 换位位移（负数 = 起点在上方，落位时下移）。
  static const double enterShift = -0.045;
}

/// 各阶段动画的载体（由 [RoundTransition] 构造后下发）。
///
/// 子元素只读自己那一路：字标读 [kicker]、巨钟读 [clock]、豆子读 [staggered]。
@immutable
class RoundTransitionScope {
  const RoundTransitionScope({
    required this.isPlaying,
    required this.exit,
    required this.kicker,
    required this.clock,
    required this.staggered,
  });

  /// 转场正在进行中（子元素据此判断「该不该播自己的动画」）。
  final bool isPlaying;

  /// 退场进度 0→1。
  final Animation<double> exit;

  /// 阶段字标换位进度 0→1。
  final Animation<double> kicker;

  /// 巨钟换色进度 0→1。
  final Animation<double> clock;

  /// 错峰取值：把整组进度切成 [count] 格，第 [index] 颗在自己那一格里走完。
  ///
  /// 用法：`animated(staggered(index, count))` 喂给 [ScaleTransition]。
  final Animation<double> Function(int index, int count) staggered;

  /// 当前 scope（不在转场层内则为 null）。
  static RoundTransitionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_InheritedRoundScope>()
          ?.scope;
}

/// 轮次转场编排层。
///
/// 把「会随阶段整块替换的内容」包进来，[phaseKey] 任一变化 = 一次转场：
/// ```dart
/// RoundTransition(
///   phaseKey: '${state.mode.name}-${state.phase.name}-${state.completedRounds}',
///   intensity: intensity,
///   child: CentralColumn(...),
/// )
/// ```
///
/// [child] 内部想跟随各自时间点动，就从 [RoundTransitionScope] 取动画。
class RoundTransition extends StatefulWidget {
  const RoundTransition({
    super.key,
    required this.phaseKey,
    required this.child,
    this.intensity = TransitionIntensity.full,
  });

  /// 阶段标识：任一变化视为一次转场。
  final String phaseKey;

  /// 强度档（`off` 完全瞬切，`lite` 只留轮次豆点亮）。
  final TransitionIntensity intensity;

  final Widget child;

  @override
  State<RoundTransition> createState() => _RoundTransitionState();
}

class _RoundTransitionState extends State<RoundTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: RoundTransitionTiming.totalMs),
    value: 1.0,
  )..addStatusListener(_onStatus);

  late final Animation<double> _exit = _segment(
    0,
    RoundTransitionTiming.exitMs,
    Curves.easeInCubic,
  );

  late final Animation<double> _kicker = _segment(
    160,
    RoundTransitionTiming.kickerMs,
    Curves.easeOutCubic,
  );

  late final Animation<double> _clock = _segment(
    200,
    RoundTransitionTiming.clockMs,
    Curves.easeOutCubic,
  );

  /// 轮次豆整组进度（线性；错峰在 [_staggered] 里切格）。
  late final Animation<double> _pips = _segment(
    520,
    800,
    Curves.linear,
  );

  Animation<double> _segment(int startMs, int durMs, Curve curve) {
    final end = (startMs + durMs) / RoundTransitionTiming.totalMs;
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(
        startMs / RoundTransitionTiming.totalMs,
        end.clamp(0.0, 1.0),
        curve: curve,
      ),
    );
  }

  /// 退场中的旧内容（null = 无退场）。
  Widget? _outgoing;

  /// 转场进行中（供子元素判断）。
  bool _playing = false;

  @override
  void didUpdateWidget(RoundTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phaseKey == widget.phaseKey) return;
    if (widget.intensity == TransitionIntensity.off) {
      setState(() {
        _outgoing = null;
        _playing = false;
      });
      return;
    }
    setState(() {
      // 精简档不留旧子树（只让豆子走一遍，元素本身瞬切）
      _outgoing = widget.intensity == TransitionIntensity.lite ? null : _snapshot();
      _playing = true;
    });
    _controller.forward(from: 0);
  }

  /// 退场用的旧内容副本：换 key 以免与新子树共享 element 状态。
  Widget _snapshot() => KeyedSubtree(
        key: const ValueKey<String>('__round_outgoing__'),
        child: widget.child,
      );

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        _playing = false;
        _outgoing = null;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.intensity == TransitionIntensity.off) {
      return widget.child;
    }
    return _InheritedRoundScope(
      scope: RoundTransitionScope(
        isPlaying: _playing,
        exit: _exit,
        kicker: _kicker,
        clock: _clock,
        staggered: (index, count) =>
            _StaggeredCurve(_pips, index, count),
      ),
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          if (_outgoing case final old?)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _exit,
                builder: (context, child) => Opacity(
                  opacity: 1 - _exit.value,
                  child: Transform.translate(
                    offset: Offset(
                        0, _exit.value * RoundTransitionTiming.exitShift),
                    child: child,
                  ),
                ),
                child: old,
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

/// 一颗豆的错峰取值：把整组进度 [parent] 切成 [index]/[count] 起、[index+1]/[count] 止
/// 的一格，再在格内走 [Curves.easeOutBack]。
///
/// 与 [ProxyAnimation] 同理——只代理 `addListener`/`removeListener` 与 `transform`，
/// **不要**覆写 `parent`（Animation 内部的 `Listenable.merge` 会反过来监听
/// `addListener`，覆写成自引用会无限递归）。
class _StaggeredCurve extends Animation<double> {
  _StaggeredCurve(this.parent, this.index, this.count);

  final Animation<double> parent;
  final int index;
  final int count;

  @override
  double transform(double t) {
    final n = count <= 0 ? 1 : count;
    final start = n <= 1 ? 0.0 : index / n;
    final end = n <= 1 ? 1.0 : (index + 1) / n;
    final local = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(local);
  }

  @override
  double get value => transform(parent.value);

  @override
  AnimationStatus get status => parent.status;

  @override
  bool get isAnimating => parent.isAnimating;

  @override
  void addListener(VoidCallback listener) => parent.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => parent.removeListener(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) =>
      parent.addStatusListener(listener);

  @override
  void removeStatusListener(AnimationStatusListener listener) =>
      parent.removeStatusListener(listener);
}

class _InheritedRoundScope extends InheritedWidget {
  const _InheritedRoundScope({required this.scope, required super.child});

  final RoundTransitionScope scope;

  @override
  bool updateShouldNotify(_InheritedRoundScope oldWidget) =>
      oldWidget.scope.isPlaying != scope.isPlaying;
}
