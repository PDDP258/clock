/// 提示音编辑浮窗（2026-10-05 用户定稿的三层结构）：
///
/// ```
/// ┌──────────────────────────────────────┐
/// │  波形可视化（整条音频，选中段高亮）      │
/// │  ♪————————●—————————————  ← 音符标记（可拖）= 起点 │
/// │  0:00 ———————————————— 2:00   ← 音乐进度轴 │
/// ├──────────────────────────────────────┤
/// │  提示音长度  ●———————— 3.2 s          │
/// │  0 ms —————————————— 5000 ms  ← 时长轴 │
/// └──────────────────────────────────────┘
/// ```
///
/// 交互口径：
/// - **音符标记拖动 = 改起点**：在波形区横向拖动/点按即可，松手不弹回；
/// - **时长轴拖动 = 改长度**（100ms~5000ms）；长度加大时若起点越界
///   （`start + duration` 超过音频末尾），起点自动左移钳制；
/// - 试听从起点播够时长即停（与实际反馈行为一致）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/feedback/custom_tone.dart';
import '../../../platform/audio/audio_tools_channel.dart';

/// 打开编辑浮窗。`onSave(null)` 表示恢复内置音；`onSave(tone)` 保存自定义。
Future<void> showToneEditorSheet(
  BuildContext context, {
  required String slotLabel,
  required AudioToolsChannel channel,
  required ToneCustom? initial,
  required Future<void> Function(ToneCustom? tone) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ToneEditorSheet(
      slotLabel: slotLabel,
      channel: channel,
      initial: initial,
      onSave: onSave,
    ),
  );
}

class _ToneEditorSheet extends StatefulWidget {
  const _ToneEditorSheet({
    required this.slotLabel,
    required this.channel,
    required this.initial,
    required this.onSave,
  });

  final String slotLabel;
  final AudioToolsChannel channel;
  final ToneCustom? initial;
  final Future<void> Function(ToneCustom? tone) onSave;

  @override
  State<_ToneEditorSheet> createState() => _ToneEditorSheetState();
}

class _ToneEditorSheetState extends State<_ToneEditorSheet> {
  ToneCustom? _tone;
  List<double> _bars = const <double>[];
  bool _loadingWave = false;
  bool _playing = false;
  AudioPlayer? _player;
  Timer? _stopTimer;

  @override
  void initState() {
    super.initState();
    _tone = widget.initial;
    if (_tone != null) _loadWaveform(_tone!.path);
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _loadWaveform(String path) async {
    setState(() => _loadingWave = true);
    final bars = await widget.channel.extractWaveform(path, bars: 140);
    if (!mounted) return;
    setState(() {
      _bars = bars;
      _loadingWave = false;
    });
  }

  /// 选一条音频（无自定义配置时的第一步）。
  Future<void> _pickAudio() async {
    final pick = await widget.channel.pick();
    if (!mounted) return;
    if (pick == null) {
      Navigator.of(context).pop();
      return;
    }
    final duration = toneClampDuration(pick.durationMs);
    setState(() {
      _tone = ToneCustom(
        path: pick.path,
        name: pick.name,
        startMs: 0,
        durationMs: duration,
        trackMs: pick.durationMs,
      );
      _bars = const <double>[];
    });
    await _loadWaveform(pick.path);
  }

  void _updateStart(int startMs) {
    final tone = _tone;
    if (tone == null) return;
    setState(() {
      _tone = tone.copyWith(startMs: toneClampStart(startMs, tone.durationMs, tone.trackMs));
    });
  }

  void _updateDuration(int durationMs) {
    final tone = _tone;
    if (tone == null) return;
    final duration = toneClampDuration(durationMs);
    setState(() {
      _tone = tone.copyWith(
        durationMs: duration,
        // 长度加大可能把起点挤出音频末尾：按规则左移钳制
        startMs: toneClampStart(tone.startMs, duration, tone.trackMs),
      );
    });
  }

  /// 试听：从起点播够时长即停（与真实反馈行为一致）。
  Future<void> _preview() async {
    final tone = _tone;
    if (tone == null) return;
    if (_playing) {
      _stopTimer?.cancel();
      await _player?.pause();
      setState(() => _playing = false);
      return;
    }
    final player = _player ??= AudioPlayer();
    if (_loadedPath != tone.path) {
      await player.setFilePath(tone.path);
      _loadedPath = tone.path;
    }
    await player.seek(Duration(milliseconds: tone.startMs));
    await player.play();
    setState(() => _playing = true);
    _stopTimer = Timer(Duration(milliseconds: tone.durationMs), () {
      if (mounted) setState(() => _playing = false);
      unawaited(player.pause());
    });
  }

  String? _loadedPath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = _tone;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('提示音 · ${widget.slotLabel}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (tone == null) ...[
              // ------------------------------------------------ 无配置：先选音频
              Text('从音乐、录音或任何音频文件里截一段当提示音。',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.icon(
                  icon: const Icon(Icons.library_music_outlined),
                  label: const Text('选择音频文件'),
                  onPressed: _pickAudio,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
            ] else ...[
              // ------------------------------------------------ 编辑器
              Text(
                '${tone.name} · 全长 ${_clock(tone.trackMs)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),

              // 第一层：波形 + 音符标记（拖动改起点）
              _WaveformStrip(
                bars: _bars,
                loading: _loadingWave,
                startFraction: tone.trackMs <= 0
                    ? 0.0
                    : (tone.startMs / tone.trackMs).clamp(0.0, 1.0),
                windowFraction: tone.trackMs <= 0
                    ? 0.0
                    : (tone.durationMs / tone.trackMs).clamp(0.0, 1.0),
                accent: scheme.primary,
                onSeek: (fraction) => _updateStart(
                    (fraction * tone.trackMs).round()),
              ),
              const SizedBox(height: 4),
              // 音乐进度轴（刻度提示，与波形同宽）
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_clock(tone.startMs),
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  Text('拖动波形或音符改起点',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  Text(_clock(tone.trackMs),
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
              const Divider(height: 20),

              // 第二层：时长轴（0~5000ms）
              Text('提示音长度 · ${_seconds(tone.durationMs)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                value: tone.durationMs.toDouble(),
                min: kToneMinMs.toDouble(),
                max: kToneMaxMs.toDouble(),
                divisions: (kToneMaxMs - kToneMinMs) ~/ 50,
                label: '${tone.durationMs} ms',
                onChanged: (v) => _updateDuration(v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0 ms',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  Text('5000 ms',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 12),

              // 操作行
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: Icon(
                        _playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
                    label: Text(_playing ? '停止' : '试听'),
                    onPressed: _preview,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      _stopTimer?.cancel();
                      Navigator.of(context).pop();
                      widget.onSave(null);
                    },
                    child: const Text('恢复内置音'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: () {
                      _stopTimer?.cancel();
                      Navigator.of(context).pop();
                      widget.onSave(_tone);
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _clock(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  static String _seconds(int ms) {
    final v = ms / 1000;
    return v == v.roundToDouble()
        ? '${v.toStringAsFixed(0)} s'
        : '${v.toStringAsFixed(1)} s';
  }
}

/// 波形条：背景柱状波形 + 选中段高亮 + 可拖动音符标记。
class _WaveformStrip extends StatelessWidget {
  const _WaveformStrip({
    required this.bars,
    required this.loading,
    required this.startFraction,
    required this.windowFraction,
    required this.accent,
    required this.onSeek,
  });

  final List<double> bars;
  final bool loading;
  final double startFraction;
  final double windowFraction;
  final Color accent;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) =>
          onSeek((d.localPosition.dx / _widthOf(context)).clamp(0.0, 1.0)),
      onHorizontalDragUpdate: (d) =>
          onSeek((d.localPosition.dx / _widthOf(context)).clamp(0.0, 1.0)),
      child: SizedBox(
        height: 96,
        width: double.infinity,
        child: CustomPaint(
          painter: _WaveformPainter(
            bars: bars,
            loading: loading,
            startFraction: startFraction,
            windowFraction: windowFraction,
            dim: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            accent: accent,
            marker: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  double _widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width - 40; // 减去浮窗左右 padding
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.bars,
    required this.loading,
    required this.startFraction,
    required this.windowFraction,
    required this.dim,
    required this.accent,
    required this.marker,
  });

  final List<double> bars;
  final bool loading;
  final double startFraction;
  final double windowFraction;
  final Color dim;
  final Color accent;
  final Color marker;

  @override
  void paint(Canvas canvas, Size size) {
    // 底轴
    final axisPaint = Paint()
      ..color = dim.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, size.height - 8), Offset(size.width, size.height - 8), axisPaint);

    if (loading) {
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), axisPaint);
      return;
    }
    if (bars.isEmpty) {
      // 无波形（解码失败）：画平线，进度交互仍可用
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), axisPaint);
    } else {
      final n = bars.length;
      final barWidth = size.width / n;
      final mid = size.height * 0.55;
      final selectedFrom = startFraction * size.width;
      final selectedTo = (startFraction + windowFraction) * size.width;
      for (var i = 0; i < n; i++) {
        final x = i * barWidth + barWidth / 2;
        final h = bars[i] * size.height * 0.8;
        final inWindow = x >= selectedFrom && x <= selectedTo;
        final paint = Paint()
          ..color = inWindow ? accent : dim
          ..strokeWidth = barWidth * 0.7
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
      }
    }

    // 音符标记：竖线 + 顶部圆点
    final mx = startFraction * size.width;
    final linePaint = Paint()
      ..color = marker
      ..strokeWidth = 2;
    canvas.drawLine(Offset(mx, 6), Offset(mx, size.height - 8), linePaint);
    canvas.drawCircle(Offset(mx, 8), 5, Paint()..color = marker);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.bars != bars ||
      old.loading != loading ||
      old.startFraction != startFraction ||
      old.windowFraction != windowFraction;
}
