/// 按键声反馈：纯 Dart 部分（事件、设置、决策），可独立单元测试。
///
/// 设计依据（技术架构设计 §5.5，ADR-0005）：
/// 免触屏场景下按键没有反馈等于盲操作——每次命令被接收即给出
/// 声音确认（端到端延迟 <100ms），开始/暂停/结束/跳过使用
/// 可区分音型；阶段切换有提醒音；音、提醒可分别开关（US-G03）。
/// 2026-10-01 用户口径：**震动通道整体移除**（含设置开关与 VIBRATE 权限）。
library;

/// 反馈事件：FocusController 把 AppCommand 结合当前状态解释成语义事件。
///
/// 与 AppCommand 的区别：AppCommand 是「按键想干什么」（中性命令），
/// FeedbackEvent 是「实际发生了什么」（开始还是暂停，只有控制器知道）。
enum FeedbackEvent {
  /// 开始专注（idle/completed → focusing）
  start,

  /// 暂停计时
  pause,

  /// 从暂停恢复（音型同 start，上行动感）
  resume,

  /// 结束本次专注并保存
  end,

  /// 跳过当前阶段
  skip,

  /// 打点 / +5 分钟（短促确认）
  mark,

  /// 阶段切换提醒（专注→休息、休息→专注；非按键触发，由计时轮转触发）
  phaseChange,

  /// 四轮完成进长休的庆祝音（看板 #47 彩蛋可达化；替代该次 phaseChange）
  celebrate,
}

/// 声音反馈设置（shared_preferences 持久化）。
class KeyFeedbackSettings {
  const KeyFeedbackSettings({
    this.keySoundOn = true,
    this.phaseAlertOn = true,
  });

  /// 按键确认音开关
  final bool keySoundOn;

  /// 阶段切换提醒音开关
  final bool phaseAlertOn;

  static const KeyFeedbackSettings defaults = KeyFeedbackSettings();

  KeyFeedbackSettings copyWith({
    bool? keySoundOn,
    bool? phaseAlertOn,
  }) {
    return KeyFeedbackSettings(
      keySoundOn: keySoundOn ?? this.keySoundOn,
      phaseAlertOn: phaseAlertOn ?? this.phaseAlertOn,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'keySoundOn': keySoundOn,
        'phaseAlertOn': phaseAlertOn,
      };

  factory KeyFeedbackSettings.fromJson(Map<String, dynamic> json) {
    return KeyFeedbackSettings(
      keySoundOn: json['keySoundOn'] as bool? ?? true,
      phaseAlertOn: json['phaseAlertOn'] as bool? ?? true,
    );
  }
}

/// 一次反馈的执行计划（决策结果）：播哪个音。
class FeedbackPlan {
  const FeedbackPlan({this.toneAsset});

  /// 需播放的提示音资产路径；null = 不发声
  final String? toneAsset;
}

/// 反馈策略：事件 + 设置 → 执行计划。纯函数，便于单测。
abstract final class FeedbackPolicy {
  /// 事件对应的提示音资产（不考虑开关）。
  static String toneAssetFor(FeedbackEvent event) => switch (event) {
        FeedbackEvent.start || FeedbackEvent.resume =>
          'assets/audio/tone_start.wav',
        FeedbackEvent.pause => 'assets/audio/tone_pause.wav',
        FeedbackEvent.end => 'assets/audio/tone_end.wav',
        FeedbackEvent.skip => 'assets/audio/tone_skip.wav',
        FeedbackEvent.mark => 'assets/audio/tone_mark.wav',
        FeedbackEvent.phaseChange => 'assets/audio/tone_phase.wav',
        FeedbackEvent.celebrate => 'assets/audio/tone_celebrate.wav',
      };

  /// 决策一次反馈。
  ///
  /// 开关语义（US-G03 分别开关）：
  /// - 按键类事件的提示音受 keySoundOn 控制；
  /// - 阶段提醒音与庆祝音受 phaseAlertOn 控制（独立于按键音，夜间可只关提醒）。
  static FeedbackPlan decide(KeyFeedbackSettings s, FeedbackEvent event) {
    final soundOn = switch (event) {
      FeedbackEvent.phaseChange || FeedbackEvent.celebrate => s.phaseAlertOn,
      _ => s.keySoundOn,
    };
    return FeedbackPlan(toneAsset: soundOn ? toneAssetFor(event) : null);
  }
}
