/// 按键自检工具页（US-G02）：实时显示「物理键码 → 语义事件 → 应用命令」
/// 三级解析结果。
///
/// 用途（技术架构设计 §5.6）：
/// - 首启自检：依次按一遍侧边键，确认 85/87/88 出厂映射；
/// - M500 系统 OTA 改变按键行为（风险 R8）后自助重新校准；
/// - FN 键码实测（FN 不走媒体会话通道，V0.2 经原生侧接入后同样在此显示）。
///
/// 实现要点：页面打开期间需要临时霸占 MediaSession 才能收到实体键
/// （否则按键归系统音乐 App）；退出时若会话未在计时则归还。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/commands/app_command.dart';
import '../../../core/media/key_event_log.dart';
import '../../../core/media/media_key_event.dart';
import '../../focus/application/focus_controller.dart';

/// 按键自检页。
class KeySelfCheckPage extends ConsumerStatefulWidget {
  const KeySelfCheckPage({super.key});

  @override
  ConsumerState<KeySelfCheckPage> createState() => _KeySelfCheckPageState();
}

class _KeySelfCheckPageState extends ConsumerState<KeySelfCheckPage> {
  /// 本页面是否主动接管了按键（退出时据此归还）
  bool _acquiredByPage = false;

  @override
  void initState() {
    super.initState();
    final handler = ref.read(focusAudioHandlerProvider);
    if (!handler.keysAcquired) {
      _acquiredByPage = true;
      handler.acquireKeys();
    }
  }

  @override
  void dispose() {
    // 页面接管期间的按键归还：仅在计时会话未接管时释放，
    // 避免打断正在进行的专注。
    if (_acquiredByPage) {
      final sessionActive = ref.read(focusControllerProvider).sessionActive;
      if (!sessionActive) {
        ref.read(focusAudioHandlerProvider).releaseKeys();
      }
    }
    super.dispose();
  }

  String _formatTime(int millis) {
    final t = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(keyEventLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('按键自检'),
        actions: [
          IconButton(
            tooltip: '清空记录',
            icon: const Icon(Icons.delete_outline),
            onPressed: log.clear,
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '请依次按侧边实体键：应看到键码 85（播放/暂停）、87（下一曲）、'
              '88（上一曲）及对应语义。若键码不符，说明系统更新改变了按键行为，'
              '请反馈给厂商并重新校准映射。',
              style: TextStyle(fontSize: 14),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<KeyLogEntry>>(
              stream: log.stream,
              initialData: log.entries,
              builder: (context, snapshot) {
                final entries = snapshot.data ?? const <KeyLogEntry>[];
                if (entries.isEmpty) {
                  return const Center(
                    child: Text('暂无按键记录\n按一下侧边键试试\n\n'
                        '也可以旋转音量旋钮——若日志出现新键码，\n'
                        '说明旋钮可被接管（请把键码反馈给开发）',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final ignored = e.command == AppCommand.ignored;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        child: Text('${e.keyCode}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      title: Text(e.event.label),
                      subtitle: Text(_formatTime(e.atMillis)),
                      trailing: Text(
                        e.command.label,
                        style: TextStyle(
                          fontSize: 14,
                          color: ignored ? Colors.grey : null,
                          fontWeight:
                              ignored ? FontWeight.w400 : FontWeight.w600,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
