/// 应用入口：只做装配，不做业务逻辑。
///
/// 装配顺序：
/// 1. 绑定 Flutter 引擎；
/// 2. 读 SharedPreferences；
/// 3. 创建 CommandBus（按键事件 → 应用命令的分发中枢）；
/// 4. AudioService.init 注册 FocusAudioHandler（霸占 MediaSession 用）；
/// 5. ProviderScope 注入上述单例后 runApp。
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/commands/app_command.dart';
import 'core/media/key_event_log.dart';
import 'features/focus/application/focus_controller.dart';
import 'platform/feedback/key_feedback_service.dart';
import 'platform/media_session/focus_audio_handler.dart';
import 'platform/prefs/prefs_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // 命令总线：FocusAudioHandler（服务侧）与 FocusController（UI 侧）
  // 通过它解耦通信，必须全局唯一。
  // US-A08：启动时恢复用户自定义按键映射（缺失/损坏回退出厂默认）。
  final commandBus = CommandBus(
      keyMap: keyMapFromStorage(prefs.getString(kKeyMapStorageKey)));

  // 按键自检日志（US-G02）：挂接 CommandBus 分发点，记录三级解析结果。
  final keyEventLog = KeyEventLog();
  commandBus.onDispatch = keyEventLog.record;

  // 注册音频服务：service 端持有 handler，负责静音 keep-alive 与按键转发。
  final audioHandler = await AudioService.init<FocusAudioHandler>(
    builder: () => FocusAudioHandler(commandBus: commandBus),
    config: const AudioServiceConfig(
      // 通知渠道 id 需与包名一致，发布前随包名一起修改
      androidNotificationChannelId: 'com.aiclock.player.channel.focus',
      androidNotificationChannelName: '专注计时',
      // androidNotificationOngoing 不能与 androidStopForegroundOnPause=false
      // 同开（audio_service 断言限制），暂停时通知可滑走，服务仍常驻。
      androidNotificationOngoing: false,
      // 暂停不撤前台服务，保证计时期间按键持续可达
      androidStopForegroundOnPause: false,
    ),
  );
  await audioHandler.init();

  // 声音反馈服务：预加载全部确认音型（<100ms 延迟的关键）。
  // P3 启动优化：不阻塞首帧——init 后台进行，play() 有 _initialized 守卫；
  // 代价仅为启动后 ~0.5s 内按键无声（按键功能本身不受影响）。
  final feedbackService = KeyFeedbackService();
  unawaited(feedbackService.init());

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        commandBusProvider.overrideWithValue(commandBus),
        focusAudioHandlerProvider.overrideWithValue(audioHandler),
        keyFeedbackServiceProvider.overrideWithValue(feedbackService),
        keyEventLogProvider.overrideWithValue(keyEventLog),
      ],
      child: const AiClockApp(),
    ),
  );
}
