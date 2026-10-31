/// 近 12 周热力图 ratio 模型与网格构建测试（看板 #37）。
/// 重点：及格线比值边界（含自定义及格线）、周一/周日锚定、未来格 -1。
library;

import 'package:ai_clock/features/stats/domain/focus_heatmap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const goal = 120 * 60 * 1000; // 默认及格线 120 分钟
  const m = 60 * 1000; // 1 分钟毫秒数

  group('focusHeatRatio 及格线比值', () {
    test('0 分钟 = 0', () => expect(focusHeatRatio(0, goal), 0));
    test('负值按 0', () => expect(focusHeatRatio(-1, goal), 0));
    test('及格线为 0 防除零', () => expect(focusHeatRatio(60 * m, 0), 0));
    test('半线 = 0.5', () => expect(focusHeatRatio(60 * m, goal), 0.5));
    test('刚好达标 = 1.0', () => expect(focusHeatRatio(120 * m, goal), 1.0));
    test('双倍超标 = 2.0', () => expect(focusHeatRatio(240 * m, goal), 2.0));
    test('比值连续不跳档（119/120 分钟差 1/120）',
        () => expect(focusHeatRatio(119 * m, goal), closeTo(119 / 120, 1e-9)));
  });

  group('buildFocusHeatmap 网格', () {
    test('12 列 × 7 行', () {
      final grid = buildFocusHeatmap(const {}, DateTime(2026, 8, 4));
      expect(grid.length, 12);
      for (final week in grid) {
        expect(week.length, 7);
      }
    });

    test('周二视角：末列今天之前无 -1，今天之后全 -1；历史列无 -1', () {
      final today = DateTime(2026, 8, 4); // 2026-08-04 是周二
      expect(today.weekday, 2);
      final grid = buildFocusHeatmap(const {}, today);
      expect(grid[11][0], 0); // 本周一
      expect(grid[11][1], 0); // 今天
      expect(grid[11][2], -1.0); // 明天起未来
      expect(grid[11][6], -1.0);
      expect(grid[10].every((r) => r >= 0), isTrue); // 上周完整
    });

    test('周日视角：本周只有一格且无 -1（weekday=7 不越界）', () {
      final today = DateTime(2026, 8, 9); // 2026-08-09 是周日
      expect(today.weekday, 7);
      final grid = buildFocusHeatmap(const {}, today);
      expect(grid[11].where((r) => r < 0), isEmpty);
      expect(grid[11][6], 0);
    });

    test('周一视角：本周一即今天，其余 6 格未来', () {
      final today = DateTime(2026, 8, 3); // 2026-08-03 是周一
      expect(today.weekday, 1);
      final grid = buildFocusHeatmap(const {}, today);
      expect(grid[11][0], 0);
      expect(grid[11].sublist(1).every((r) => r < 0), isTrue);
    });

    test('数据按默认及格线折算落到正确格子', () {
      final today = DateTime(2026, 8, 4); // 周二
      final monday = DateTime(2026, 8, 3);
      final grid = buildFocusHeatmap(
        {heatDateKey(monday): 60 * 60 * 1000}, // 60 分钟 = 半线
        today,
      );
      expect(grid[11][0], 0.5); // 本周一
      expect(grid[11][1], 0); // 今天无数据
    });

    test('自定义及格线生效（30 分钟线，60 分钟 = 2.0）', () {
      final today = DateTime(2026, 8, 4);
      final monday = DateTime(2026, 8, 3);
      final grid = buildFocusHeatmap(
        {heatDateKey(monday): 60 * 60 * 1000},
        today,
        goalMillis: 30 * m,
      );
      expect(grid[11][0], 2.0);
    });

    test('首格 = 11 周前的周一，数据落 [0][0]', () {
      final today = DateTime(2026, 8, 4);
      final firstMonday =
          DateTime(2026, 8, 3).subtract(const Duration(days: 7 * 11));
      expect(firstMonday.weekday, 1); // 锚点确为周一
      final grid = buildFocusHeatmap(
        {heatDateKey(firstMonday): 240 * m}, // 双倍超标
        today,
      );
      expect(grid[0][0], 2.0);
    });
  });
}
