/// 详细时间统计页（看板 #19，幽灵排查工具）：指定日期的会话级明细 +
/// 24 小时时间轴可视化。
///
/// 设计要点：
/// - 会话块 = 一行 focus_session（startAt → endAt；进行中 endAt=null，
///   查看今天时延伸到当前时刻、半透明显示）；
/// - 横屏优先（M500 锁定横屏）：日期切换条 + 摘要行 + 时间轴 + 明细列表
///   纵向排布，列表区滚动；
/// - 幽灵轮次排查路径：切到目标日期，看时间轴上「自己明确没操作的时段」
///   是否出现会话块，再到明细列表核对起止时刻与轮数。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/timer/time_format.dart';
import '../../../core/timer/timer_mode.dart';
import '../../../platform/db/app_database.dart';
import '../../ai/application/ai_ask.dart';
import '../../ai/application/ai_controller.dart';
import '../../ai/application/daily_comment.dart';
import '../../ai/presentation/ai_ask_chips.dart';
import '../../backgrounds/application/background_controller.dart';
import '../../backgrounds/presentation/page_background.dart';
import '../application/stats_controller.dart';
import '../domain/daily_summary.dart';
import '../domain/focus_interruption.dart';
import '../domain/weekly_report.dart';

/// 详细时间统计页。
class StatsDetailPage extends ConsumerStatefulWidget {
  const StatsDetailPage({super.key});

  @override
  ConsumerState<StatsDetailPage> createState() => _StatsDetailPageState();
}

class _StatsDetailPageState extends ConsumerState<StatsDetailPage> {
  DateTime _day = DateTime.now();

  bool get _isToday =>
      isSameLocalDay(_day.millisecondsSinceEpoch,
          DateTime.now().millisecondsSinceEpoch);

  void _shiftDay(int delta) {
    setState(() => _day = DateTime(_day.year, _day.month, _day.day + delta));
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2024),
      lastDate: now,
    );
    if (picked != null) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(daySessionsProvider(_day));

    return Scaffold(
      // 背景透到 AppBar 与状态栏后面（透明 AppBar + 内容自己让出高度）
      extendBodyBehindAppBar: true,
      appBar: transparentAppBar(title: '详细时间统计'),
      body: ScrollAwareBackground(
        // 详细页只抽规则 2 的图（宽铺满、高溢出）且按溢出深度加权：
        // 这一页本来就能滚，背景跟着走最有「翻画册」感（docs/10 §5/§6）。
        // 竖屏姿态与统计页竖屏同策略：规则 2 池 + 溢出深度加权，但独立
        // BgPage，与计时页竖屏互不干扰（PD 2026-10-06）。
        page: MediaQuery.orientationOf(context) == Orientation.portrait
            ? BgPage.statsDetailPortrait
            : BgPage.statsDetail,
        child: Column(
          children: [
            // 日期切换条
            Padding(
              padding: EdgeInsets.only(
                  top: appBarTopPadding(context), left: 8, right: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '前一天',
                    onPressed: () => _shiftDay(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: _pickDay,
                      child: Center(
                        child: Text(
                          '${_day.year}-${_day.month.toString().padLeft(2, '0')}-'
                          '${_day.day.toString().padLeft(2, '0')}'
                          '${_isToday ? '（今天）' : ''}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _isToday
                        ? null
                        : () => setState(() => _day = DateTime.now()),
                    child: const Text('今天'),
                  ),
                  IconButton(
                    tooltip: '后一天',
                    // 查看今天时不允许翻向未来
                    onPressed: _isToday ? null : () => _shiftDay(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            // 摘要行 + 时间轴 + 明细列表
            Expanded(
              child: sessionsAsync.when(
                data: (sessions) => _buildBody(context, sessions),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('读取失败')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<FocusSession> sessions) {
    // 当日小结（看板 #46）：聚合复用 daily_summary 纯函数，
    // 与周报同口径（时段四桶/中断=专注内暂停）
    final summary = buildDailySummary([
      for (final s in sessions)
        DailySessionFact(
          startAtMillis: s.startAt,
          focusMillis: s.actualFocusMillis,
          rounds: s.rounds,
          pauses: parseInterruptions(s.pausesJson),
        ),
    ]);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: [
        // 当日小结卡（含 AI 一句话点评：仅今天且 AI 开启时显示）
        Card(
          margin: EdgeInsets.zero,
          color: backdropPanelColor(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary.sessionCount == 0)
                  const Text('该日无专注记录',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w500))
                else ...[
                  // 用户语言口径（看板 #49）：大字总时长 + 分段数/最长一段 +
                  // 起止时刻；番茄/中断是机制语言，不在此处出现
                  // （中断在时间轴上以红条可视化）
                  Text(
                    formatDurationText(
                        Duration(milliseconds: summary.focusMillis)),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '分 ${summary.sessionCount} 段完成'
                    ' · 最长一段 ${formatDurationText(Duration(milliseconds: summary.longestSegmentMillis))}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (summary.firstStartMillis != null &&
                      summary.lastEndMillis != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '从 ${formatInterruptionClock(summary.firstStartMillis!)}'
                      ' 到 ${formatInterruptionClock(summary.lastEndMillis!)}',
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
                if (summary.bestSlot != null) ...[
                  const SizedBox(height: 4),
                  Text('最佳时段：${summary.bestSlot!.label}',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
                if (_isToday) const _DailyCommentLine(),
                // 问 AI 这天（看板 #51）：任意查看日可问，AI 开启即显示；
                // 无记录日数据全零，AI 会照实说，不额外屏蔽
                AiAskChips(questions: aiAskDailyQuestions, day: _day),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 24h 时间轴
        _DayTimeline(sessions: sessions, day: _day, isToday: _isToday),
        const SizedBox(height: 4),
        // 图例（Wrap：窄屏自动换行，避免多项溢出）
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _LegendDot(color: context.skin.focusRingColor, label: '番茄'),
            _LegendDot(color: context.skin.accentColor, label: '正计时'),
            _LegendDot(
                color: context.skin.focusRingColor.withValues(alpha: 0.4),
                label: '进行中'),
            _LegendDot(color: context.skin.dangerColor, label: '中断'),
            _LegendDot(
                color: Theme.of(context).colorScheme.onSurface, label: '打点'),
          ],
        ),
        const SizedBox(height: 8),
        // 会话明细
        for (final s in sessions) _SessionTile(session: s),
      ],
    );
  }
}

/// 图例色点 + 标签。
class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// 24 小时时间轴：横向条带，会话按起止时刻画色块。
/// 刻度 0/6/12/18/24 时；查看今天时叠加「现在」竖线。
class _DayTimeline extends StatelessWidget {
  const _DayTimeline({
    required this.sessions,
    required this.day,
    required this.isToday,
  });

  final List<FocusSession> sessions;
  final DateTime day;
  final bool isToday;

  static const _barHeight = 28.0;
  static const _dayMillis = 24 * 60 * 60 * 1000;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dayStart = DateTime(day.year, day.month, day.day);
    final startMs = dayStart.millisecondsSinceEpoch;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    double frac(int ms) => ((ms - startMs) / _dayMillis).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return Column(
          children: [
            SizedBox(
              height: _barHeight,
              child: Stack(
                children: [
                  // 底槽
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  // 6/12/18 时网格线
                  for (final h in const [6, 12, 18])
                    Positioned(
                      left: w * h / 24,
                      top: 0,
                      bottom: 0,
                      child: Container(
                          width: 1, color: scheme.outlineVariant),
                    ),
                  // 会话色块（R8：按专注段渲染，休息空隙即断断续续的空白）
                  for (final s in sessions)
                    ..._buildBlocks(context, s, w, frac, nowMs),
                  // 「现在」竖线（仅今天）
                  if (isToday)
                    Positioned(
                      left: math.max(0, w * frac(nowMs) - 1),
                      top: -2,
                      bottom: -2,
                      child: Container(width: 2, color: scheme.onSurface),
                    ),
                ],
              ),
            ),
            // 时刻刻度
            SizedBox(
              height: 16,
              child: Stack(
                children: [
                  for (final h in const [0, 6, 12, 18, 24])
                    Positioned(
                      left: (w * h / 24 - 14).clamp(0.0, math.max(0, w - 28)),
                      child: SizedBox(
                        width: 28,
                        child: Text(
                          '$h:00',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 10, color: scheme.onSurfaceVariant),
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
  }

  /// 解析会话的专注段区间（R8，schema v4 intervalsJson）。
  /// 老数据 / 解析失败 → 空列表（调用方回退整段渲染）。
  static List<(int, int)> _segmentsOf(FocusSession s) {
    final raw = s.intervalsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return <(int, int)>[
        for (final seg in decoded)
          if (seg is List && seg.length == 2)
            ((seg[0] as num).toInt(), (seg[1] as num).toInt()),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// 会话色块（R8）：有专注段数据时每段一块——段间空白即休息/暂停空隙，
  /// 断断续续的完成过程在时间轴上直接可见；无数据回退整段渲染（老数据）。
  List<Widget> _buildBlocks(
    BuildContext context,
    FocusSession s,
    double w,
    double Function(int) frac,
    int nowMs,
  ) {
    final inProgress = s.endAt == null;
    final isPomodoro = s.mode == TimerMode.pomodoro.storageKey;
    final base = isPomodoro
        ? context.skin.focusRingColor
        : context.skin.accentColor;
    final color = inProgress ? base.withValues(alpha: 0.4) : base;

    final segments = _segmentsOf(s);
    List<(int, int)> spans;
    if (segments.isNotEmpty) {
      spans = List.of(segments);
      // 进行中的会话：查看今天时末段延伸到当前时刻（正在专注的那一段）
      if (inProgress && isToday && spans.isNotEmpty) {
        final last = spans.last;
        spans[spans.length - 1] = (last.$1, nowMs);
      }
    } else {
      // 回退：老数据无段区间，整段渲染（进行中：今天延伸到现在，
      // 历史日防御性延伸到当日结束）
      final endMs = s.endAt ?? (isToday ? nowMs : s.startAt + _dayMillis);
      spans = [(s.startAt, endMs)];
    }
    // 防御（R12）：色块累计不得超过实际专注时长。老/损坏数据会把「关机重开
    // 时刻」当作段终点（半小时专注被画成跨整天大块），暂停会话的末段也会被
    // 延伸到当前时刻——两者都会让时间轴显示远超真实专注的色块。以实际专注
    // 为准从末段裁剪，时间轴永远不长于真实专注。
    return _renderSpans(
      context,
      s,
      w,
      frac,
      isToday,
      nowMs,
      color,
      _clampSpansToActual(spans, s.actualFocusMillis),
    );
  }

  /// 裁剪色块区间，使其累计时长不超过 [actualMillis]（R12 防御）。
  /// 超出时从最后一段末尾砍掉（正常数据 sum(段) == 实际专注，不会触发；
  /// 仅老/损坏数据或暂停末段延伸会超出）。
  static List<(int, int)> _clampSpansToActual(
    List<(int, int)> spans,
    int actualMillis,
  ) {
    if (spans.isEmpty) return spans;
    var total = 0;
    for (final (a, b) in spans) {
      if (b > a) total += b - a;
    }
    // 容差：进行中会话末段会随心跳延伸到当前时刻，允许少量超出
    if (total <= actualMillis + _clampToleranceMillis) return spans;
    final out = <(int, int)>[];
    var budget = actualMillis;
    for (final (a, b) in spans) {
      final d = b - a;
      if (d <= 0) continue;
      if (budget >= d) {
        out.add((a, b));
        budget -= d;
      } else {
        if (budget > 0) out.add((a, a + budget));
        break;
      }
    }
    return out;
  }

  static const _clampToleranceMillis = 65 * 1000;

  List<Widget> _renderSpans(
    BuildContext context,
    FocusSession s,
    double w,
    double Function(int) frac,
    bool isToday,
    int nowMs,
    Color color,
    List<(int, int)> spans,
  ) {

    return <Widget>[
      for (final (segStart, segEnd) in spans)
        Positioned(
          left: (w * frac(segStart)).clamp(0.0, math.max(0, w - 3)),
          top: 3,
          bottom: 3,
          width: math.min(
              math.max(3.0, w * (frac(segEnd) - frac(segStart))), w),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      // 中断细条（US-D02）：叠在专注块上的危险色细条——段区间把暂停包在
      // 内部不可见，中断必须单独标记；暂停中的中断延伸到现在
      for (final (pStart, pEnd) in parseInterruptions(s.pausesJson))
        Positioned(
          left: (w * frac(pStart)).clamp(0.0, math.max(0, w - 2)),
          top: 3,
          bottom: 3,
          width: math.min(
              math.max(
                  2.0,
                  w *
                      (frac(pEnd ?? (isToday ? nowMs : pStart)) -
                          frac(pStart))),
              w),
          child: Container(
            decoration: BoxDecoration(
              color: context.skin.dangerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      // 打点（US-B02 复盘）：正计时打点作为凸出块顶的刻度线，复盘时可见
      for (final offset in parseMarks(s.marksJson))
        Positioned(
          left: (w * frac(s.startAt + offset)).clamp(0.0, math.max(0, w - 2)),
          top: 0,
          height: 6,
          width: 2,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
    ];
  }
}

/// 单条会话明细：起止时刻 + 实际专注 + 轮数 + 模式 + 状态。
class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final FocusSession session;

  static String _hhmm(int millis) {
    final t = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = session.endAt == null;
    final mode = TimerModeX.fromStorageKey(session.mode);
    final status = inProgress
        ? '进行中'
        : session.completed
            ? '已结束'
            : '提前结束';
    final isPomodoro = mode == TimerMode.pomodoro;
    final dotColor = isPomodoro
        ? context.skin.focusRingColor
        : context.skin.accentColor;
    // 中断（US-D02）：次数 + 发生时刻列表（识别分心规律的直接材料）
    final interruptions = parseInterruptions(session.pausesJson);
    final interruptionText = interruptions.isEmpty
        ? ''
        : ' · 中断 ${interruptions.length} 次（'
            '${interruptions.map((p) => formatInterruptionClock(p.$1)).join('、')}）';
    // 任务/标签（US-B05）
    final tagText = session.tag == null ? '' : ' · 🏷 ${session.tag}';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: inProgress ? dotColor.withValues(alpha: 0.4) : dotColor,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(
        '${_hhmm(session.startAt)} – '
        '${inProgress ? '至今' : _hhmm(session.endAt!)}',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        (isPomodoro
                ? '${mode.label} · ${session.rounds} 轮 · $status'
                : '${mode.label} · $status') +
            tagText +
            interruptionText,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        formatDurationText(Duration(milliseconds: session.actualFocusMillis)),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ------------------------------------------------------------------ AI 点评

/// AI 当日点评行（看板 #46）：仅 AI 总开关开启时渲染内容。
/// Idle=引导/手动生成入口；Loading=转圈；Ready=点评 + 「换一句」。
class _DailyCommentLine extends ConsumerWidget {
  const _DailyCommentLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiEnabled =
        ref.watch(aiSettingsProvider.select((s) => s.enabled));
    if (!aiEnabled) return const SizedBox.shrink();

    final state = ref.watch(aiDailyCommentProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16),
        switch (state) {
          AiDailyLoading() => const Row(children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 6),
              Text('AI 点评生成中…', style: TextStyle(fontSize: 13)),
            ]),
          AiDailyReady(:final text, :final dataUpdated) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text,
                          style:
                              const TextStyle(fontSize: 13, height: 1.4)),
                      // 今天又专注了：只给被动提示，不自动重发（08-A2）
                      if (dataUpdated)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('数据已更新，点「换一句」刷新',
                              style: TextStyle(
                                  fontSize: 11, color: theme.colorScheme.primary)),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => ref
                      .read(aiDailyCommentProvider.notifier)
                      .requestDailyComment(force: true),
                  child: const Text('换一句', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          _ => Row(children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text('完成今日首轮专注后自动生成一句话点评',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () => ref
                    .read(aiDailyCommentProvider.notifier)
                    .requestDailyComment(),
                child: const Text('立即生成', style: TextStyle(fontSize: 12)),
              ),
            ]),
        },
      ],
    );
  }
}
