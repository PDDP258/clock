/// 自定义提示音设置页：7 个音槽分别绑定用户音频片段。
///
/// 每行显示当前状态（内置音 / 自定义文件名），点击进入编辑浮窗
/// （波形 + 音符起点 + 0~5000ms 时长轴，见 `tone_editor_sheet.dart`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/custom_tone.dart';
import '../application/tone_settings.dart';
import 'tone_editor_sheet.dart';

/// 自定义提示音页（设置页 → 自定义提示音）。
class ToneSettingsPage extends ConsumerWidget {
  const ToneSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = ref.watch(customTonesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('自定义提示音')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '每个提示音可单独换成你自己的音频片段（最长 5 秒）：'
              '选一条音乐/录音，在波形上拖动音符定起点，'
              '下面的轴定长度。不设置的槽位用内置音。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          for (final entry in kToneSlots.entries)
            ListTile(
              leading: Icon(
                tones.containsKey(entry.key)
                    ? Icons.music_note_rounded
                    : Icons.volume_up_outlined,
                color: tones.containsKey(entry.key) ? scheme.primary : null,
              ),
              title: Text(entry.value),
              subtitle: Text(
                tones.containsKey(entry.key)
                    ? '自定义 · ${(tones[entry.key]!.name.isEmpty ? '音频' : tones[entry.key]!.name)}'
                    : '内置音',
                style: tones.containsKey(entry.key)
                    ? TextStyle(color: scheme.primary, fontSize: 13)
                    : null,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _edit(context, ref, entry.key, entry.value,
                  tones[entry.key]),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String slotKey,
    String slotLabel,
    ToneCustom? current,
  ) async {
    final notifier = ref.read(customTonesProvider.notifier);
    await showToneEditorSheet(
      context,
      slotLabel: slotLabel,
      channel: ref.read(audioToolsChannelProvider),
      initial: current,
      onSave: (tone) async {
        if (tone == null) {
          await notifier.clear(slotKey);
        } else {
          await notifier.set(slotKey, tone);
        }
      },
    );
  }
}
