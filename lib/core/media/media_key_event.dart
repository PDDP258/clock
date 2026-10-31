/// 媒体按键语义事件 + 多击分组器（纯 Dart，不依赖 Flutter，可单元测试）。
///
/// 目标设备 M500 的侧边实体键为主板直连、出厂映射为标准媒体键
/// （上一曲 88 / 播放暂停 85 / 下一曲 87），事件本地直达、时序可靠，
/// 无需任何蓝牙 AVRCP 兼容处理。
library;

import 'dart:async';

/// 媒体按键的语义事件。物理按键 → 语义事件的转换规则：
/// - 播放/暂停键在 [ClickGrouper.window] 内按 1/2/3 次 → 单按/双按/三按
/// - 播放/暂停键长按 → [MediaKeyEvent.longPress]（由平台侧上报，见 handler 注释）
/// - 下一曲 / 上一曲 → [MediaKeyEvent.next] / [MediaKeyEvent.previous]
enum MediaKeyEvent {
  singleTap,
  doubleTap,
  tripleTap,
  longPress,
  next,
  previous,
}

/// 语义事件中文展示名（自检页/设置页共用）。
extension MediaKeyEventX on MediaKeyEvent {
  /// 展示名
  String get label => switch (this) {
        MediaKeyEvent.singleTap => '单按',
        MediaKeyEvent.doubleTap => '双按',
        MediaKeyEvent.tripleTap => '三按',
        MediaKeyEvent.longPress => '长按',
        MediaKeyEvent.next => '下一曲',
        MediaKeyEvent.previous => '上一曲',
      };
}

/// 延时调度器抽象：默认用 dart:async 的 Timer，测试时可注入手动调度器。
typedef Scheduler = void Function(Duration delay, void Function() callback);

/// 多击分组器：把一串物理击键按 300ms 静默窗口聚合成单按/双按/三按。
///
/// 窗口取值 = 平台标准双击间隔（Android ViewConfiguration.getDoubleTapTimeout
/// 与 Flutter kDoubleTapTimeout 均为 300ms；Web/iOS 的双击判定同量级）——
/// 再长（旧值 800ms）单按感知延迟明显，再短容易把「慢双按」误判成两次单按。
///
/// 算法：
/// 1. 每次击键调用 [tap]，计数 +1，并以「代次号」重新武装一个窗口回调；
/// 2. 窗口到期时若代次号已变（说明窗口内又来了新击键），旧回调作废；
/// 3. 代次号一致说明已静默满一个窗口，结算当前计数并发出语义事件。
class ClickGrouper {
  ClickGrouper({
    required this.onResolved,
    this.window = const Duration(milliseconds: 300),
    Scheduler? scheduler,
  }) : _scheduler = scheduler ?? Timer.new;

  /// 结算出语义事件后的回调
  final void Function(MediaKeyEvent event) onResolved;

  /// 多击判定时间窗，默认 300ms（平台标准双击间隔）
  final Duration window;

  final Scheduler _scheduler;

  int _count = 0;
  int _generation = 0;

  /// 记录一次播放/暂停键击键。
  void tap() {
    _count++;
    final gen = ++_generation;
    _scheduler(window, () {
      if (gen != _generation) return; // 窗口内有新击键，本次回调作废
      _flush();
    });
  }

  /// 立即结算当前计数（测试用，也可用于「不等窗口」的兜底路径）。
  void flushNow() {
    _generation++; // 作废所有已武装的窗口回调
    _flush();
  }

  /// 当前挂起的击键计数（测试断言用）
  int get pendingCount => _count;

  void _flush() {
    if (_count == 0) return;
    final event = switch (_count) {
      1 => MediaKeyEvent.singleTap,
      2 => MediaKeyEvent.doubleTap,
      _ => MediaKeyEvent.tripleTap, // 3 次及以上统一按三按处理
    };
    _count = 0;
    onResolved(event);
  }
}
