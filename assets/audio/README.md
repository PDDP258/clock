# assets/audio

本目录音频资产由 `tool/generate_audio.py` 生成（仅需 Python 标准库，无 ffmpeg 依赖）：

```bash
python tool/generate_audio.py
```

## 文件清单

| 文件 | 用途 |
| --- | --- |
| `silence.wav` | 1 秒静音。`FocusAudioHandler` 用 just_audio 循环播放它，让本 App 的 MediaSession 保持 playing 态，从而持续霸占 M500 实体媒体键（上一曲 88 / 播放暂停 85 / 下一曲 87），避免按键落回系统音乐 App。 |
| `tone_start.wav` | 按键确认音：开始/继续（上行双音） |
| `tone_pause.wav` | 按键确认音：暂停（低沉单音） |
| `tone_end.wav` | 按键确认音：结束并保存（下行双音） |
| `tone_skip.wav` | 按键确认音：跳过阶段（短促扫频） |
| `tone_mark.wav` | 按键确认音：正计时打点（极短高频） |
| `tone_phase.wav` | 阶段切换提醒音（专注→休息等，较长双音，熄屏可辨） |

确认音型设计见技术架构设计 §5.5：开始/暂停/结束/跳过使用可区分音型，
盲操作时凭声音即可确认语义。音、振在设置页可分别开关（US-G03）。

> 注意：仓库中不直接提交二进制音频，请每台开发机本地执行一次生成脚本。
