/// 使用统计页：今日/本周专注时长 + fl_chart 柱状图 + 各应用使用时长。
///
/// 同样按 5 英寸 720p 小屏设计：纵向单栏、图表高度受限、数字优先。
///
/// 背景（`docs/10-背景图库登记表.md`）：整页铺一张随机背景图（不透明度 40%，
/// 每 5 分钟~5 小时随机换一张），AppBar 透明让图透到状态栏；卡片改为
/// 半透明「色块」，图层顺序为 **页面底色 → 图片 → 卡片色块 → 文字**。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/timer/time_format.dart';
import '../../ai/application/ai_ask.dart';
import '../../ai/application/ai_controller.dart';
import '../../ai/presentation/ai_ask_chips.dart';
import '../../backgrounds/application/background_controller.dart';
import '../../backgrounds/presentation/page_background.dart';
import '../application/stats_controller.dart';
import '../domain/elastic_streak.dart';
import '../domain/usage_stats_source.dart';
import '../domain/weekly_report.dart';

/// 统计页。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayFocus = ref.watch(todayFocusProvider);
    final todayRounds = ref.watch(todayRoundsProvider);
    final weekFocus = ref.watch(weekFocusProvider);
    final appUsage = ref.watch(todayAppUsageProvider);
    final usagePermission = ref.watch(usagePermissionProvider);
    final streak = ref.watch(streakProvider);
    final weeklyReport = ref.watch(weeklyReportProvider);
    final heatmap = ref.watch(heatmapProvider);
    final easterEgg = ref.watch(easterEggProvider);
    // 每日目标（热力图及格线，看板 #37）：今日卡片的目标进度条复用同一基准
    final goalMinutes = ref.watch(dailyGoalMinutesProvider);
    // V0.5：AI 总开关关闭时零入口零请求（ADR-0006 安静原则）
    final aiEnabled =
        ref.watch(aiSettingsProvider.select((s) => s.enabled));

    return Scaffold(
      // 背景透到 AppBar 与状态栏后面（透明 AppBar + 内容自己让出高度）
      extendBodyBehindAppBar: true,
      appBar: transparentAppBar(
        title: '使用统计',
        actions: [
          // 详细时间统计（看板 #19：指定日期 + 24h 时间轴，幽灵排查工具）
          IconButton(
            tooltip: '详细时间统计',
            onPressed: () => Navigator.of(context).pushNamed('/stats/detail'),
            icon: const Icon(Icons.timeline),
          ),
        ],
      ),
      body: ScrollAwareBackground(
        // 竖屏姿态改用规则 2 池（PD 2026-10-06：「竖屏时使用统计背景也用
        // 规则 2」——独立 BgPage，与计时页竖屏互不干扰）；横屏维持全池随机
        page: MediaQuery.orientationOf(context) == Orientation.portrait
            ? BgPage.statsPortrait
            : BgPage.stats,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, appBarTopPadding(context) + 12, 16, 24),
          children: [
            // 今日专注总时长 + 番茄数 + 目标进度 + 当日细节（US-D01）
            _TodayFocusCard(
              focus: todayFocus,
              rounds: todayRounds,
              goalMinutes: goalMinutes,
            ),
            const SizedBox(height: 16),

            // 初音彩蛋（看板 #47：39 系列小彩蛋，命中才出现）
            easterEgg.when(
              data: (msg) => msg == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Card(
                        color: backdropPanelColor(context,
                            tint: context.skin.accentColor),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Icon(Icons.celebration_outlined,
                                size: 18, color: context.skin.accentColor),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(msg,
                                    style: const TextStyle(fontSize: 14))),
                          ]),
                        ),
                      ),
                    ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // 近 7 天柱状图
            const _SectionLabel('本周专注'),
            const SizedBox(height: 8),
            SizedBox(
              height: 180, // 720p 小屏：图表限高，保证一屏看完
              child: weekFocus.when(
                data: (days) => _WeekBarChart(days: days),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('暂无数据')),
              ),
            ),
            const SizedBox(height: 16),

            // 本周日均 + 较上周同期（本轮新增）
            _WeekAverageCard(report: weeklyReport),
            const SizedBox(height: 16),

            // 近 12 周热力图（看板 #34）：坚持度一眼化
            const _SectionLabel('近 12 周'),
            const SizedBox(height: 8),
            heatmap.when(
              data: (h) => _FocusHeatmap(weeks: h.grid, millis: h.millis),
              loading: () => const SizedBox(
                  height: 96,
                  child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // 连续记录（US-D03 弹性连续）+ 近 7 天达标迷你条（本轮新增）
            _StreakCard(
              streak: streak,
              week: weekFocus,
              goalMinutes: goalMinutes,
            ),

            // 每周报告（US-D04：环比 + 最专注时段）
            weeklyReport.when(
              data: (r) => (r.thisWeekMillis <= 0 && r.lastWeekMillis <= 0)
                  ? const SizedBox.shrink()
                  : Card(
                      color: backdropPanelColor(context),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('每周报告',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text(
                              '本周 ${formatDurationText(Duration(milliseconds: r.thisWeekMillis))}'
                              '${r.changeRatio == null ? '' : _changeText(r.changeRatio!)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            if (r.bestSlot != null)
                              Text(
                                '最专注时段：${r.bestSlot!.label}'
                                '（${formatDurationText(Duration(milliseconds: r.bestSlotMillis))}）',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // AI 周报解读（V0.5：挂在每周报告下方，用户主动点击的唯一入口）
            if (aiEnabled) ...[
              const SizedBox(height: 16),
              const _AiInsightSection(),
            ],
            const SizedBox(height: 16),

            // 今日应用使用 Top 3 + 专注/屏幕占比（US-E01）
            _AppUsageSection(
              usage: appUsage,
              permissionMissing: usagePermission.value == false,
              todayFocusMillis: todayFocus.value?.inMilliseconds ?? 0,
            ),
          ],
        ),
      ),
    );
  }
}

/// 小节标题（统计页统一排版）。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600));
}

/// 今日专注卡（本轮改造）：
/// - 大数字从 40sp 收到 **32sp**（= 80%），让位给下面四行细节；
/// - 细节行：每日目标进度条 / 分几段完成 / 最长一段 / 最佳时段。
class _TodayFocusCard extends ConsumerWidget {
  const _TodayFocusCard({
    required this.focus,
    required this.rounds,
    required this.goalMinutes,
  });

  final AsyncValue<Duration> focus;
  final AsyncValue<int> rounds;
  final int goalMinutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final focusMillis = focus.value?.inMilliseconds ?? 0;
    final goalMillis = goalMinutes * 60 * 1000;
    final progress = goalMillis <= 0
        ? 0.0
        : (focusMillis / goalMillis).clamp(0.0, 1.0);
    final percent = goalMillis <= 0 ? 0 : (focusMillis * 100 / goalMillis).round();
    // 当日细节复用详细页同一份聚合（daily_summary 纯函数），口径不会两处漂移
    final today = DateTime.now();
    final summary = ref.watch(
        dailySummaryProvider(DateTime(today.year, today.month, today.day)));
    // 当日无记录时细节行整块不出现（避免一排「--」占地方）
    final s = summary.valueOrNull;
    final detail = (s != null && s.sessionCount > 0) ? s : null;

    return Card(
      color: backdropPanelColor(context),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('今日专注',
                style: TextStyle(fontSize: 16, color: scheme.onSurface)),
            const SizedBox(height: 8),
            Text(
              focus.when(
                data: formatDurationText,
                loading: () => '--',
                error: (_, __) => '--',
              ),
              style: const TextStyle(
                  fontSize: 32, // 原 40sp 的 80%
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              rounds.when(
                data: (r) => '$r 个番茄',
                loading: () => '--',
                error: (_, __) => '--',
              ),
              style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            // 每日目标进度（复用热力图及格线，看板 #37）
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(
                    context.skin.focusRingColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('每日目标 $goalMinutes 分',
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const Spacer(),
                Text(
                  progress >= 1 ? '已达标 · $percent%' : '已完成 $percent%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: progress >= 1
                        ? context.skin.focusRingColor
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            // 当日细节行（分几段/最长一段/最佳时段/中断）
            if (detail != null) ...[
              const SizedBox(height: 10),
              Divider(
                  height: 1, color: scheme.onSurface.withValues(alpha: 0.12)),
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.splitscreen_outlined,
                text: '分 ${detail.sessionCount} 段完成 · '
                    '最长一段 ${formatDurationText(Duration(milliseconds: detail.longestSegmentMillis))}',
              ),
              if (detail.bestSlot != null) ...[
                const SizedBox(height: 6),
                _DetailRow(
                  icon: Icons.schedule_outlined,
                  text: '最佳时段：${detail.bestSlot!.label}',
                ),
              ],
              if (detail.interruptionCount > 0) ...[
                const SizedBox(height: 6),
                _DetailRow(
                  icon: Icons.pause_circle_outline,
                  text: '中断 ${detail.interruptionCount} 次'
                      '${detail.interruptionMillis > 0 ? ' · 共 ${formatDurationText(Duration(milliseconds: detail.interruptionMillis))}' : ''}',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 细节行：小图标 + 一行说明。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13, color: scheme.onSurface)),
        ),
      ],
    );
  }
}

/// 本周日均 + 较上周同期（本轮新增）。
///
/// 日均按**本周已过天数**摊（`daysElapsed`），不是除以 7——
/// 周一只过了 3 小时就除以 7 会把日均压得毫无意义。
class _WeekAverageCard extends StatelessWidget {
  const _WeekAverageCard({required this.report});

  final AsyncValue<WeeklyReport> report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return report.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (r) {
        if (r.thisWeekMillis <= 0 && r.lastWeekMillis <= 0) {
          return const SizedBox.shrink();
        }
        final days = r.daysElapsed <= 0 ? 1 : r.daysElapsed;
        final average = formatDurationText(
            Duration(milliseconds: r.thisWeekMillis ~/ days));
        return Card(
          color: backdropPanelColor(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('本周日均',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text(average,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('按本周已过 $days 天摊',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 52,
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('较上周同期',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text(
                        r.changeRatio == null
                            ? '无基线'
                            : _signedPercent(r.changeRatio!),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          // 涨用专注色、跌用中性色：涨跌是习惯变化，不是「好坏」
                          color: r.changeRatio == null
                              ? scheme.onSurfaceVariant
                              : context.skin.focusRingColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '上周同期 ${formatDurationText(Duration(milliseconds: r.lastWeekMillis))}',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 连续记录 + 近 7 天达标迷你条（本轮新增：坚持度不用翻热力图也能看）。
class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.streak,
    required this.week,
    required this.goalMinutes,
  });

  final AsyncValue<StreakResult> streak;
  final AsyncValue<List<Duration>> week;
  final int goalMinutes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final streakResult = streak.valueOrNull;
    final days = streakResult?.days ?? 0;
    final bufferUsed = streakResult?.bufferUsed ?? 0;
    final weekDays = week.valueOrNull;
    if (streakResult == null && weekDays == null) {
      return const SizedBox.shrink();
    }

    return Card(
      color: backdropPanelColor(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_fire_department_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  days > 0 ? '已连续 $days 天' : '还没有连续记录',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              days > 0
                  ? (bufferUsed > 0
                      ? '本周缓冲已用 $bufferUsed/2 天'
                      : '本周缓冲未使用（每周允许 2 天）')
                  : '今天专注一次就开始计数',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (weekDays != null && weekDays.isNotEmpty) ...[
              const SizedBox(height: 10),
              _WeekGoalStrip(days: weekDays, goalMinutes: goalMinutes),
            ],
          ],
        ),
      ),
    );
  }
}

/// 近 7 天达标迷你条：一格一天（左旧右新），达及格线亮色、未达标淡色。
class _WeekGoalStrip extends StatelessWidget {
  const _WeekGoalStrip({required this.days, required this.goalMinutes});

  /// 长度 7：6 天前 → 今天
  final List<Duration> days;
  final int goalMinutes;

  static const _labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final goalMillis = goalMinutes * 60 * 1000;
    final todayWeekday = DateTime.now().weekday;
    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: goalMillis > 0 && days[i].inMilliseconds >= goalMillis
                        ? context.skin.focusRingColor
                            .withValues(alpha: 0.85)
                        : scheme.onSurface.withValues(alpha: 0.10),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  // i=0 是 6 天前，换算其星期几
                  _labels[((todayWeekday - 1 - (6 - i)) % 7 + 7) % 7],
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 今日应用使用：Top 3 + 专注/屏幕占比（本轮收敛：原 Top5 太长，
/// 且只报时长看不出「时间花在哪儿」）。
class _AppUsageSection extends ConsumerWidget {
  const _AppUsageSection({
    required this.usage,
    required this.permissionMissing,
    required this.todayFocusMillis,
  });

  final AsyncValue<({List<AppUsageInfo> top, int totalMillis})> usage;

  /// 未授权（`usagePermissionProvider == false`）
  final bool permissionMissing;

  final int todayFocusMillis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('今日应用使用'),
        const SizedBox(height: 8),
        if (permissionMissing)
          Card(
            color: backdropPanelColor(context),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '统计各应用使用时长需要「使用情况访问」权限。\n'
                    '数据由系统实时查询，本 App 不留存、不上传。',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.query_stats),
                    label: const Text('去开启权限'),
                    onPressed: () async {
                      await ref
                          .read(usageStatsSourceProvider)
                          .requestPermission();
                      // 从系统设置返回后刷新权限状态与数据
                      ref.invalidate(usagePermissionProvider);
                    },
                  ),
                ],
              ),
            ),
          )
        else
          usage.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Text('读取失败'),
            data: (data) {
              if (data.top.isEmpty) {
                return const Text('今日暂无应用使用数据');
              }
              // 专注 / 屏幕：把「屏幕上花了多久」和「专注了多久」并排看，
              // 比单看时长更能说明问题（屏幕为 0 时不给比值，避免除零误导）
              final ratio = data.totalMillis <= 0
                  ? null
                  : todayFocusMillis / data.totalMillis;
              return Card(
                color: backdropPanelColor(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('专注 / 屏幕',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                          const Spacer(),
                          Text(
                            '${formatDurationText(Duration(milliseconds: todayFocusMillis))}'
                            ' / ${formatDurationText(Duration(milliseconds: data.totalMillis))}'
                            '${ratio == null ? '' : '  ≈ ${ratio.toStringAsFixed(2)}×'}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (final info in data.top)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(info.packageName,
                              style: const TextStyle(fontSize: 14)),
                          trailing: Text(formatDurationText(
                              Duration(milliseconds: info.foregroundMillis))),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// 环比文案：+20%（较上周）/ -13%（较上周）。
String _changeText(double ratio) {
  final pct = (ratio * 100).round();
  final sign = pct >= 0 ? '+' : '';
  // 「同期」二字不能省：基线是上周同一进度点（周一至同样的星期几同一时刻），
  // 不是上周完整一周（08-A1）
  return '（较上周同期 $sign$pct%）';
}

/// 带符号百分比（本周日均卡用，不带「较上周同期」后缀以免重复）。
String _signedPercent(double ratio) {
  final pct = (ratio * 100).round();
  return '${pct >= 0 ? '+' : ''}$pct%';
}

/// 近 7 天专注时长柱状图。
class _WeekBarChart extends StatelessWidget {
  const _WeekBarChart({required this.days});

  /// 长度为 7：6 天前 → 今天，单位任意（此处按分钟换算）。
  final List<Duration> days;

  static const _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final todayWeekday = DateTime.now().weekday; // 1=周一
    final maxMinutes = days.fold<int>(
        0, (m, d) => d.inMinutes > m ? d.inMinutes : m);

    return BarChart(
      BarChartData(
        maxY: (maxMinutes == 0 ? 60 : maxMinutes * 1.2).toDouble(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                // i=0 是 6 天前，换算其星期几
                final i = value.toInt();
                final weekday = ((todayWeekday - 1 - (6 - i)) % 7 + 7) % 7;
                return Text(_weekLabels[weekday],
                    style: const TextStyle(fontSize: 12));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].inMinutes.toDouble(),
                  width: 14,
                  borderRadius: BorderRadius.circular(4),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 近 12 周专注热力图：列=周（左旧右新）、行=周一~周日。
/// 着色 = ratio 模型（看板 #37）：用户设每日及格线，未达标 alpha=ratio²
/// （差距二次方放大），达标满色，超标向白混合 (ratio-1)²；未来格留空。
/// 格子按可用宽度自适应铺满（LayoutBuilder）；点按格子在下方信息行
/// 显示当天日期、时长与达标状态。
class _FocusHeatmap extends StatefulWidget {
  const _FocusHeatmap({required this.weeks, required this.millis});

  /// [week][weekday]：当日/及格线比值（0 = 无专注）；-1 = 未来日
  final List<List<double>> weeks;

  /// 零点毫秒 key → 当日专注毫秒（点按查详情）
  final Map<int, int> millis;

  @override
  State<_FocusHeatmap> createState() => _FocusHeatmapState();
}

class _FocusHeatmapState extends State<_FocusHeatmap> {
  static const _rowLabels = ['一', '', '', '四', '', '', '日'];
  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  /// 选中的格子（周列, 行）；null = 未选
  (int, int)? _selected;

  DateTime get _firstMonday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(
        Duration(days: today.weekday - 1 + 7 * (widget.weeks.length - 1)));
  }

  String get _infoText {
    final sel = _selected;
    if (sel == null) return '达到及格线为满色 · 越深越超标 · 点按格子看当天';
    final day = _firstMonday.add(Duration(days: sel.$1 * 7 + sel.$2));
    final key = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final ms = widget.millis[key] ?? 0;
    final ratio = widget.weeks[sel.$1][sel.$2];
    final detail = ms > 0
        ? '专注 ${formatDurationText(Duration(milliseconds: ms))}'
            '（${ratio >= 1 ? '已达标' : '达及格线 ${(ratio * 100).round()}%'}）'
        : '无专注记录';
    return '${day.month}月${day.day}日 周${_weekdayNames[day.weekday - 1]} · $detail';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heatColor = context.skin.focusRingColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const labelCol = 16.0;
            const gap = 4.0; // 格子 margin 两侧合算 4
            final cell =
                ((constraints.maxWidth - labelCol - gap) / widget.weeks.length -
                        gap)
                    .clamp(8.0, 30.0);
            final pitch = cell + gap;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 行标签列（周一/周四/周日锚点）
                Column(
                  children: [
                    for (final label in _rowLabels)
                      SizedBox(
                        height: pitch,
                        child: Center(
                          child: Text(label,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: gap),
                for (var w = 0; w < widget.weeks.length; w++)
                  Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        _cell(w, d, cell, heatColor, scheme),
                    ],
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(_infoText,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  /// 格子着色（ratio 模型）：无数据=空色；未达标 alpha=ratio²（下限 0.08
  /// 保持可读）；达标满色；超标向白混合 (ratio-1)²×0.6（上限 55% 白）。
  Color _cellColor(double ratio, Color heatColor, ColorScheme scheme) {
    if (ratio <= 0) return scheme.surfaceContainerHighest;
    if (ratio >= 1) {
      final over = (ratio - 1).clamp(0.0, 1.5);
      final whiten = (over * over * 0.6).clamp(0.0, 0.55);
      return Color.lerp(heatColor, Colors.white, whiten)!;
    }
    return heatColor.withValues(alpha: (ratio * ratio).clamp(0.08, 1.0));
  }

  Widget _cell(
      int w, int d, double cell, Color heatColor, ColorScheme scheme) {
    final ratio = widget.weeks[w][d];
    if (ratio < 0) {
      // 未来日：占位留空，保持网格对齐
      return Container(
          width: cell, height: cell, margin: const EdgeInsets.all(2));
    }
    final selected = _selected == (w, d);
    return GestureDetector(
      onTap: () => setState(() => _selected = selected ? null : (w, d)),
      child: Container(
        width: cell,
        height: cell,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(cell * 0.22),
          color: _cellColor(ratio, heatColor, scheme),
          border:
              selected ? Border.all(color: scheme.onSurface, width: 1.5) : null,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ AI 解读

/// AI 周报解读区（V0.5）：渲染请求状态机——
/// Idle=入口按钮 / Loading=转圈 / Ready=段落+建议卡 / Degraded=一行原因。
/// 一切云端失败静默降级为结构化周报（照常显示在上方的「每周报告」卡）。
class _AiInsightSection extends ConsumerWidget {
  const _AiInsightSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiInsightControllerProvider);
    final theme = Theme.of(context);
    return Card(
      color: backdropPanelColor(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.auto_awesome, size: 18),
              SizedBox(width: 6),
              Text('AI 解读',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            switch (state) {
              AiInsightIdle() => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('让 AI 解读本周数据'),
                      onPressed: () => ref
                          .read(aiInsightControllerProvider.notifier)
                          .requestInterpretation(),
                    ),
                    const SizedBox(height: 6),
                    Text('完成本周第一轮专注后也会自动解读一次',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              AiInsightLoading() => const Row(children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('正在解读…', style: TextStyle(fontSize: 14)),
                ]),
              AiInsightReady(:final value, :final fromCache, :final dataUpdated) =>
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in value.paragraphs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(p,
                            style:
                                const TextStyle(fontSize: 14, height: 1.5)),
                      ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('建议：${value.suggestion}',
                          style: const TextStyle(fontSize: 14, height: 1.5)),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: Text(
                          // 数据变了只提示，不自动重发（AI 安静原则，08-A2）
                          dataUpdated
                              ? '本周数据已更新，点「重新解读」可刷新'
                              : fromCache
                                  ? '本周已解读（本地缓存回看，未重复请求）'
                                  : '解读完成 · 本周内回看不再请求',
                          style: TextStyle(
                              fontSize: 12,
                              color: dataUpdated
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(aiInsightControllerProvider.notifier)
                            .requestInterpretation(force: true),
                        child: const Text('重新解读'),
                      ),
                    ]),
                  ],
                ),
              AiInsightDegraded(:final reason) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_degradeText(reason),
                        style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant)),
                    // 瞬时类故障给重试；配置类问题去设置页解决，不重试
                    if (reason == AiDegradeReason.network ||
                        reason == AiDegradeReason.timeout ||
                        reason == AiDegradeReason.badResponse) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => ref
                            .read(aiInsightControllerProvider.notifier)
                            .requestInterpretation(),
                        child: const Text('重试'),
                      ),
                    ],
                  ],
                ),
            },
            // 问 AI 一句（看板 #50/#51）：点选式周报问答，与解读状态无关，
            // AI 开启即显示；M500 打字困难，不给输入框
            const Divider(height: 24),
            const AiAskChips(questions: aiAskWeeklyQuestions),
          ],
        ),
      ),
    );
  }

  /// 降级矩阵（07 §6）各配一行提示文案。
  static String _degradeText(AiDegradeReason reason) => switch (reason) {
        AiDegradeReason.disabled => 'AI 功能未开启',
        AiDegradeReason.noConsent => '需先在「设置 → AI 功能」中同意数据使用说明',
        AiDegradeReason.noKey => '请先在「设置 → AI 功能」中配置 API Key',
        // 不是故障：数据量不足时解读只会变成空话，本地拦下（08-A6）
        AiDegradeReason.insufficientData =>
          '本周数据还太少，暂不足以解读——攒够 1 小时或 3 次专注后再来',
        AiDegradeReason.network => '网络不可用，上方周报数据不受影响',
        AiDegradeReason.timeout => '请求超时（云端生成较慢），请稍后重试',
        AiDegradeReason.unauthorized => 'API Key 无效或已过期，请到「设置 → AI 功能」检查',
        AiDegradeReason.quota => '服务商余额不足或被限流，请检查账户或更换服务商',
        AiDegradeReason.badResponse => '解读结果异常，请重试',
      };
}
