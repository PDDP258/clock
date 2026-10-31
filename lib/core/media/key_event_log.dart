/// 按键自检日志（US-G02，纯 Dart 可单测）：记录「键码 → 语义事件 → 命令」
/// 三级解析结果，供按键自检工具页实时展示。
///
/// 用途（技术架构设计 §5.6）：
/// - 首启自检：引导用户按一遍侧边键，确认 85/87/88 出厂映射；
/// - 系统 OTA 改变按键行为（风险 R8）后用户自助重新校准；
/// - 兼任开发期 KeyCode 探测工具。
library;

import 'dart:async';

import '../commands/app_command.dart';
import 'media_key_event.dart';

/// 语义事件对应的出厂物理键码（M500 主板直连标准 KeyEvent 通道）。
/// 播放/暂停键的四种手势（单/双/三/长按）都来自 85。
int keyCodeOf(MediaKeyEvent event) => switch (event) {
      MediaKeyEvent.singleTap ||
      MediaKeyEvent.doubleTap ||
      MediaKeyEvent.tripleTap ||
      MediaKeyEvent.longPress =>
        85,
      MediaKeyEvent.next => 87,
      MediaKeyEvent.previous => 88,
    };

/// 一条按键日志：三级解析结果 + 墙上时间。
class KeyLogEntry {
  const KeyLogEntry({
    required this.atMillis,
    required this.keyCode,
    required this.event,
    required this.command,
  });

  /// 收到的墙上时间戳（毫秒）
  final int atMillis;

  /// 物理键码（85/87/88）
  final int keyCode;

  /// 解析出的语义事件（单按/长按/下一曲……）
  final MediaKeyEvent event;

  /// 最终分发的应用命令（含 ignored）
  final AppCommand command;
}

/// 按键日志环形缓冲：容量有限、最新在前、变更可订阅。
class KeyEventLog {
  KeyEventLog({this.capacity = 50});

  /// 最大保留条数（自检页展示用，超出裁最旧）
  final int capacity;

  final List<KeyLogEntry> _entries = <KeyLogEntry>[];
  final StreamController<List<KeyLogEntry>> _controller =
      StreamController<List<KeyLogEntry>>.broadcast();

  /// 当前日志（最新在前）
  List<KeyLogEntry> get entries => List.unmodifiable(_entries);

  /// 变更流：每次 record/clear 发出最新快照
  Stream<List<KeyLogEntry>> get stream => _controller.stream;

  /// 记录一次按键解析。
  void record(MediaKeyEvent event, AppCommand command) {
    _entries.insert(
      0,
      KeyLogEntry(
        atMillis: DateTime.now().millisecondsSinceEpoch,
        keyCode: keyCodeOf(event),
        event: event,
        command: command,
      ),
    );
    if (_entries.length > capacity) {
      _entries.removeRange(capacity, _entries.length);
    }
    _controller.add(List.unmodifiable(_entries));
  }

  /// 清空日志（自检页「清除」按钮）。
  void clear() {
    _entries.clear();
    _controller.add(const <KeyLogEntry>[]);
  }

  Future<void> dispose() => _controller.close();
}
