#!/usr/bin/env python3
"""生成 AI_clock 音频资产（仅需 Python 标准库，无 ffmpeg 依赖）。

生成文件（均在 assets/audio/ 下）：
  silence.wav    2 分钟静音（8kHz，真机反馈 R2 由 1 秒加长：1 秒循环会
                 每秒触发播放器状态事件，导致通知整窗每秒重绘闪烁），
                 FocusAudioHandler 循环播放保持 MediaSession active
  tone_start.wav 开始/继续：上行双音（“出发”感）
  tone_pause.wav 暂停：低沉单音
  tone_end.wav   结束并保存：下行双音（“收尾”感）
  tone_skip.wav  跳过阶段：短促扫频上行
  tone_mark.wav  正计时打点：极短高频“咔哒”
  tone_phase.wav 阶段切换提醒（专注→休息等）：较长的双音提醒

所有提示音均为 44.1kHz 16-bit 单声道 WAV，带 5ms 淡入淡出防爆音。
重新生成：python tool/generate_audio.py
"""

import math
import os
import struct
import wave

SAMPLE_RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")


def _envelope(samples: list[float], fade_ms: float = 5.0) -> list[int]:
    """应用淡入淡出并转为 16-bit PCM。"""
    fade = max(1, int(SAMPLE_RATE * fade_ms / 1000))
    out = []
    n = len(samples)
    for i, s in enumerate(samples):
        gain = 1.0
        if i < fade:
            gain = i / fade
        elif i > n - fade:
            gain = (n - i) / fade
        out.append(int(max(-1.0, min(1.0, s * gain)) * 32767))
    return out


def _tone(freq: float, ms: float, volume: float = 0.5) -> list[float]:
    n = int(SAMPLE_RATE * ms / 1000)
    return [volume * math.sin(2 * math.pi * freq * i / SAMPLE_RATE) for i in range(n)]


def _sweep(f0: float, f1: float, ms: float, volume: float = 0.5) -> list[float]:
    n = int(SAMPLE_RATE * ms / 1000)
    out = []
    for i in range(n):
        t = i / n
        freq = f0 + (f1 - f0) * t
        phase = 2 * math.pi * (f0 * t + (f1 - f0) * t * t / 2)
        out.append(volume * math.sin(phase))
    return out


def _silence(ms: float, rate: int = SAMPLE_RATE) -> list[float]:
    return [0.0] * int(rate * ms / 1000)


def _write(name: str, samples: list[float], sample_rate: int = SAMPLE_RATE) -> None:
    pcm = _envelope(samples)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    print(f"  {name}: {len(samples) / sample_rate * 1000:.0f}ms, {os.path.getsize(path)}B")


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"生成音频资产 → {os.path.abspath(OUT_DIR)}")

    # 静音 keep-alive：2 分钟 @ 8kHz（约 1.9MB），循环播放。
    # 真机反馈 R2：1 秒静音每秒循环一次，每次循环 ExoPlayer 都发状态事件，
    # audio_service 随之整窗重发通知 → 整个通知每秒闪烁；加长到 2 分钟后
    # 循环事件降到每 2 分钟一次，肉眼不可感。
    _write("silence.wav", _silence(120_000, rate=8000), sample_rate=8000)

    # 开始/继续：880 → 1174Hz 上行双音
    _write("tone_start.wav", _tone(880, 90) + _silence(30) + _tone(1174, 120))
    # 暂停：440Hz 低沉单音
    _write("tone_pause.wav", _tone(440, 140))
    # 结束并保存：660 → 330Hz 下行双音
    _write("tone_end.wav", _tone(660, 100) + _silence(30) + _tone(330, 180))
    # 跳过阶段：550 → 990Hz 短促扫频
    _write("tone_skip.wav", _sweep(550, 990, 120))
    # 打点：1320Hz 极短“咔哒”
    _write("tone_mark.wav", _tone(1320, 60, volume=0.4))
    # 阶段切换提醒：990 + 1320Hz 较长双音（熄屏可辨）
    _write("tone_phase.wav", _tone(990, 160) + _silence(60) + _tone(1320, 240))
    # 四轮完成进长休庆祝（看板 #47）：C5-E5-G5-C6 上行琶音，明亮收尾
    _write(
        "tone_celebrate.wav",
        _tone(523, 100) + _silence(20) + _tone(659, 100) + _silence(20)
        + _tone(784, 100) + _silence(20) + _tone(1047, 260),
    )


if __name__ == "__main__":
    main()
