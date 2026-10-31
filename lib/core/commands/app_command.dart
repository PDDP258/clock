/// 应用命令与命令总线（纯 Dart，不依赖 Flutter，可单元测试）。
///
/// 链路：实体按键 → MediaKeyEvent（语义事件）→ 按 [KeyMapConfig] 映射
/// → [AppCommand]（应用命令）→ CommandBus 广播 → FocusController 执行。
///
/// 映射表可整体替换（设置页改键位 / 多套预设），因此 CommandBus 本身
/// 不硬编码任何按键语义。
library;

import 'dart:async';
import 'dart:convert';

import '../media/media_key_event.dart';

/// 应用命令：按键最终要触发的动作。
enum AppCommand {
  /// 开始 / 暂停 / 恢复（三态切换，由控制器按当前状态解释）
  toggleStartPause,

  /// 当前阶段 +5 分钟
  addFiveMinutes,

  /// 跳过当前阶段（专注→休息、休息→下一轮专注）
  skipPhase,

  /// 结束本次番茄会话
  finishSession,

  /// 正计时打点（时间标记点）。
  ///
  /// 默认映射中不直接绑定按键：上一曲键默认映射为 [addFiveMinutes]，
  /// 由 focus_controller 按当前模式分发——正计时模式下把上一曲键
  /// 语义改写为本命令，番茄倒计时模式下保持 +5 分钟（ADR-0005）。
  tickMark,

  /// 未映射 / 忽略
  ignored,

  /// 把「下一曲」转发给系统音乐 App（两 App 同时可控，真机需求）：
  /// 本 App 暂时释放按键 → 原生侧 dispatch KEYCODE_MEDIA_NEXT → 重新霸占。
  /// 仅在按键接管期间有效（按键已归还时双按本来就直接到音乐 App）。
  forwardNext,
}

/// 命令中文展示名（自检页/设置页共用）。
extension AppCommandX on AppCommand {
  /// 展示名
  String get label => switch (this) {
        AppCommand.toggleStartPause => '开始/暂停',
        AppCommand.addFiveMinutes => '+5 分钟',
        AppCommand.skipPhase => '跳过阶段',
        AppCommand.finishSession => '结束并保存',
        AppCommand.tickMark => '打点',
        AppCommand.ignored => '未映射',
        AppCommand.forwardNext => '音乐下一首',
      };
}

/// 按键映射配置。数据类，可 JSON 序列化，便于存入 drift 的 key_map_preset 表。
class KeyMapConfig {
  const KeyMapConfig({required this.mapping});

  /// 语义事件 → 应用命令
  final Map<MediaKeyEvent, AppCommand> mapping;

  /// 出厂默认映射（ADR-0005 极简版 + 真机双按转发需求）：
  /// 单按=开始/暂停，双按=音乐下一首（转发给系统音乐 App），
  /// 长按=结束并保存，下一曲=跳过阶段，上一曲=+5 分钟
  /// （正计时模式下由 focus_controller 改写为打点 tickMark）。
  /// 双按绑定后单按需经 300ms 多击窗口结算（平台标准双击间隔，
  /// Android ViewConfiguration.getDoubleTapTimeout 同为 300ms）；
  /// 用户在映射编辑器解绑双/三按后，单按恢复立即下发。
  factory KeyMapConfig.defaults() => const KeyMapConfig(
        mapping: <MediaKeyEvent, AppCommand>{
          MediaKeyEvent.singleTap: AppCommand.toggleStartPause,
          MediaKeyEvent.doubleTap: AppCommand.forwardNext,
          MediaKeyEvent.longPress: AppCommand.finishSession,
          MediaKeyEvent.next: AppCommand.skipPhase,
          MediaKeyEvent.previous: AppCommand.addFiveMinutes,
        },
      );

  KeyMapConfig copyWith({Map<MediaKeyEvent, AppCommand>? mapping}) =>
      KeyMapConfig(mapping: mapping ?? this.mapping);

  /// 重映射单个按键，返回新配置（不可变风格）。
  KeyMapConfig remap(MediaKeyEvent event, AppCommand command) {
    return KeyMapConfig(
      mapping: Map<MediaKeyEvent, AppCommand>.of(mapping)
        ..[event] = command,
    );
  }

  /// 当前映射是否绑定了多击手势（双按/三按）。
  ///
  /// 未绑定时「单按」可绕过 300ms 多击窗口立即下发——绑定多击手势后
  /// 单按必须等窗口结算（区分单/双按的必要代价，窗口取平台标准
  /// 300ms 双击间隔，兼顾判定可靠性与感知延迟）。
  bool get bindsMultiTap =>
      mapping.containsKey(MediaKeyEvent.doubleTap) ||
      mapping.containsKey(MediaKeyEvent.tripleTap);

  Map<String, dynamic> toJson() => <String, dynamic>{
        for (final e in mapping.entries) e.key.name: e.value.name,
      };

  factory KeyMapConfig.fromJson(Map<String, dynamic> json) {
    final map = <MediaKeyEvent, AppCommand>{};
    for (final entry in json.entries) {
      final key = MediaKeyEvent.values.asNameMap()[entry.key];
      final value = AppCommand.values.asNameMap()[entry.value as String];
      if (key != null && value != null) map[key] = value;
    }
    return KeyMapConfig(mapping: map);
  }
}

/// 自定义映射在 SharedPreferences 中的存储键（US-A08）。
const kKeyMapStorageKey = 'key_map_custom';

/// 从持久化 JSON 字符串恢复映射；缺失或损坏时回退出厂默认（纯 Dart，可测）。
KeyMapConfig keyMapFromStorage(String? raw) {
  if (raw == null) return KeyMapConfig.defaults();
  try {
    return KeyMapConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on FormatException {
    return KeyMapConfig.defaults();
  }
}

/// 命令总线：接收语义按键事件，按当前映射解析为应用命令并广播。
class CommandBus {
  CommandBus({KeyMapConfig? keyMap})
      : _keyMap = keyMap ?? KeyMapConfig.defaults();

  KeyMapConfig _keyMap;

  /// 当前生效的按键映射（设置页可热替换）
  KeyMapConfig get keyMap => _keyMap;
  set keyMap(KeyMapConfig value) => _keyMap = value;

  final StreamController<AppCommand> _controller =
      StreamController<AppCommand>.broadcast();

  /// 命令流，FocusController 订阅
  Stream<AppCommand> get commands => _controller.stream;

  /// 最近一次按键解析出的命令（UI 提示 / 测试断言用）
  AppCommand? lastCommand;

  /// 分发监听（按键自检日志用，US-G02）：每次 dispatchKey 后回调
  /// 「语义事件 + 解析命令」（含 ignored）。main.dart 装配时挂接。
  void Function(MediaKeyEvent event, AppCommand command)? onDispatch;

  /// 入口：一个语义按键事件进来，解析并分发。
  /// 返回解析出的命令（ignored 也会返回但不广播）。
  AppCommand dispatchKey(MediaKeyEvent event) {
    final command = _keyMap.mapping[event] ?? AppCommand.ignored;
    lastCommand = command;
    onDispatch?.call(event, command);
    if (command != AppCommand.ignored) {
      _controller.add(command);
    }
    return command;
  }

  Future<void> dispose() => _controller.close();
}
