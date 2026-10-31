/// 记忆日志的应用层接线（看板 #54）：跨程序记忆的读写与自动落盘。
///
/// 三个面，刻意分开：
/// - **写入面** [AiMemoryLogService.saveToday]：把当日白名单数字与本次产生的
///   AI 文本落到「今天」这一条上（同日覆盖，见 memory_log.dart 的所有权表）；
/// - **读取面** [AiMemoryLogService.recentEntries]：近 N 日条目（预留接口，
///   外部联动自检与设置页预览都用它）；
/// - **注入面** [AiMemoryLogService.readInjectionBlock]：把近 7 日（不含当日）
///   渲染成提示词可用的块，交给四个 builder。
///
/// 纪律（沿用 ADR-0006 与 08 轮的口径）：
/// - **未开启 AI 时零副作用**：不建文件、不读不写——关掉的功能不该留痕迹；
/// - **任何失败静默**：记忆是增强项，磁盘/数据库出问题就当作「没有记忆」，
///   绝不让它把解读链路拖垮（与缓存损坏同级的处理）；
/// - **不新增上传字段**：注入内容全部来自既有白名单字段与 AI 自己的输出，
///   外部程序写进 `memory` 的部分由用户自己负责（设置页已如实披露）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_prompt.dart';
import '../../../core/ai/memory_log.dart';
import '../../../platform/files/memory_log_store.dart';
import '../../stats/application/stats_controller.dart';
import 'ai_controller.dart';

/// 记忆日志存储（测试覆盖为临时目录）。
final aiMemoryLogStoreProvider =
    Provider<AiMemoryLogStore>((ref) => AiMemoryLogStore());

/// 记忆日志服务。
final aiMemoryLogServiceProvider =
    Provider<AiMemoryLogService>((ref) => AiMemoryLogService(ref));

/// 设置页展示用的日志快照。
class AiMemoryLogSnapshot {
  const AiMemoryLogSnapshot({
    required this.path,
    required this.entries,
    required this.invalidLines,
  });

  /// 日志文件绝对路径（供外部程序对接）
  final String path;

  /// 全部条目（按日期升序）
  final List<AiMemoryEntry> entries;

  /// 无法解析、被原样保留的行数
  final int invalidLines;
}

/// 记忆日志服务。
class AiMemoryLogService {
  AiMemoryLogService(this._ref);

  final Ref _ref;

  AiMemoryLogStore get _store => _ref.read(aiMemoryLogStoreProvider);

  /// 读取近 [days] 日日志（**读取面**：含当日，按日期升序）。
  /// 读失败返回空列表——记忆是增强项，坏了不能拖垮主链路。
  Future<List<AiMemoryEntry>> recentEntries({
    int days = kMemoryWindowDays,
    DateTime? now,
    bool includeToday = true,
  }) async {
    try {
      final file = await _store.read();
      return AiMemoryLog.recent(
        file.entries,
        today: now ?? DateTime.now(),
        days: days,
        includeToday: includeToday,
      );
    } catch (_) {
      return const <AiMemoryEntry>[];
    }
  }

  /// 近 7 日（**不含当日**）记忆注入块；无内容或读失败返回 null。
  ///
  /// 不含当日：当天数字已经在事实块里，两边都注入就会出现「同一份数据
  /// 两个口径」——08-A1 已经教过一次代价。
  Future<String?> readInjectionBlock() async =>
      AiMemoryLog.renderBlock(await recentEntries(includeToday: false));

  /// 自动保存当日条目：写入当日白名单数字，并合并本次产生的 AI 文本。
  ///
  /// 触发点：每完成一轮专注（app 壳监听）只写数字；当日点评/周报解读
  /// 成功后追加 `note` / `insight`。**未开启 AI 时零副作用**（不建文件）。
  /// 返回是否成功落盘；失败静默。
  Future<bool> saveToday({String? note, String? insight}) async {
    if (!_ref.read(aiSettingsProvider).enabled) return false;
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final summary = await _ref.read(dailySummaryProvider(today).future);
      final saved = await _store.upsert(AiMemoryEntry(
        date: memoryDateKey(now),
        updatedAt: isoLocalWithOffset(now),
        promptVersion: kPromptVersion,
        facts: dailyFactsJson(summary),
        note: note,
        insight: insight,
      ));
      return saved != null;
    } catch (_) {
      // 记忆落盘失败不得影响计时与解读：静默吞掉（与缓存损坏同级处理）
      return false;
    }
  }

  /// 设置页展示用快照（路径 + 条目 + 坏行数）。
  Future<AiMemoryLogSnapshot> snapshot() async {
    try {
      final file = await _store.read();
      return AiMemoryLogSnapshot(
        path: await _store.path(),
        entries: file.entries,
        invalidLines: file.invalidLines.length,
      );
    } catch (_) {
      return const AiMemoryLogSnapshot(
        path: '(路径不可用)',
        entries: <AiMemoryEntry>[],
        invalidLines: 0,
      );
    }
  }

  /// 清空日志文件（「删除 AI 数据」联动）。
  Future<void> clear() => _store.clear();
}
