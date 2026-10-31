# AGENT.md — AI_clock「按键番茄」实施上下文

> 供后续会话快速接续的进度与经验记录。每次完成一个实施步骤后更新「进度看板」与「经验与坑」。
> 产品/技术结论以 docs/ 为准，本文件不重复论证，只记「做到哪、怎么做、踩过什么坑」。

## 1. 项目一句话

运行在 M500 音乐播放器（Android 14 定制 ROM）上的零触屏自律时钟：用机身实体媒体键（播放/暂停=85、下一曲=87、上一曲=88）控制番茄倒计时 + 正计时，全程不触屏，每次按键有声震即时反馈（<100ms）。

## 2. 文档地图（权威顺序）

| 文档 | 用途 |
| --- | --- |
| `docs/02-PRD-产品需求文档.md` | 功能边界（V1.2 已收敛：两种计时模式、极简按键映射） |
| `docs/03-技术架构设计.md` | 四层架构、计时引擎/按键链路/数据层设计、风险登记册 |
| `docs/adr/0001~0006` | 6 条不可推翻决策：audio_service 霸占会话 / drift / Feature-first+Riverpod+Command 映射 / UsageStats / 简洁体验第一 / AI 功能范围（安静原则，ADR-0006） |
| `docs/05~08`（AI 功能） | 调研 / PRD / 技术方案 / 优化建议；**09 是跨程序记忆日志的对外规范**（外部程序对接只读 09） |
| `CONTEXT.md` | 领域词汇表（命名必须与其对齐） |

## 3. 架构速查

- 四层：`app/`（装配）→ `features/*`（功能插件）→ `core/*`（纯 Dart，可 `dart test`）→ `platform/*`（系统能力抽象，真机/fake 双实现）。下层不依赖上层。
- **当前 platform/ 实体**（双轴审查后迁移归位，勿再放回 core/features）：`platform/media_session/focus_audio_handler.dart`（含 Flutter 依赖，唯一非纯 Dart 的按键链路文件）、`platform/db/app_database.dart(+g.dart)`（drift 实现 + appDatabaseProvider）、`platform/feedback/key_feedback_service.dart`、`platform/prefs/prefs_provider.dart`（sharedPreferencesProvider 全局唯一入口）、`platform/files/memory_log_store.dart`（记忆日志文件的唯一读写点，原子写 tmp+rename；格式与编解码在 core/ai/memory_log.dart）。
- 计时铁律：**时间戳差值，禁止每秒累加/轮询计时**；引擎不自建 Timer，由 FocusController 每 500ms `tick()`；Clock 可注入 fake。
- 按键链路：实体键 → audio_service(MediaSession) → `ClickGrouper`(300ms 窗，未绑定多击手势时单按绕过窗口直发) → `MediaKeyEvent` → `CommandBus`(KeyMapConfig 映射 + onDispatch 日志点) → `AppCommand` → `resolveForMode`（按模式改写）→ FocusController。
- 会话仲裁：计时开启 `acquireKeys()` 霸占（静音保活+FGS mediaPlayback）；结束/暂停超阈值 `releaseKeys()` 归还音乐 App。**`keysAcquired` 与 `sessionActive` 是两个状态**：暂停超时释放后 keysAcquired=false 但 sessionActive=true，通知按钮保持可用（一键重新接管）。
- 通知显示归属：**只由 FocusController 驱动**（`_pushNotificationDisplay` 按秒节流）；handler 只提供 `updateTimerDisplay`/`showIdleDisplay` 两个被动接口，绝不在 acquire/release 里自作主张改显示。
- 持久化：drift（platform/db，schema v5）+ shared_preferences（配置/引擎状态/按键映射）。
- 状态管理：Riverpod；跨层依赖全部 Provider 注入，测试用 override 换 fake。
- 中文标签统一在 core 枚举扩展上（`TimerPhaseX.label` / `CountUpPhaseX.label` / `MediaKeyEventX.label` / `AppCommandX.label` / `TimerModeX.label`），页面禁止再写本地化 switch。

## 4. 环境与常用命令

- Flutter 3.41.0 stable（`/c/flutter/flutter`），Python 3.12 可用（无 ffmpeg，音频资产用 Python `wave` 生成 WAV）。
- `flutter test` — 全量单测；`flutter analyze` — 静态检查。
- `flutter build apk --debug` — 出包到 `build/app/outputs/flutter-apk/`；直接调 `./gradlew` 须先 `export JAVA_HOME="E:\\IDL\\b\\jbr"`（见 §6-15）。
- drift 代码生成（改表结构后必跑）：`dart run build_runner build`（2.15 已移除 `--delete-conflicting-outputs`；状态异常先 `dart run build_runner clean`）
- **当前基线（2026-10-06）**：`flutter analyze` 存量 4 条告警（app_command/timer_engine 2 条 info + tone_settings 未用 import + settings_page sliderMax 未用参数，均在竖屏轮未触碰的文件；`test/custom_tone_test.dart` 有 digit-separators 实验语法存量 error，与主工程无关）；竖屏轮全部改动零新增告警。构建：`flutter build apk --release`（~100-120s，产物 82.6MB）。
- 测试数演进：34（接手 07-19）→ 66（V0.1）→ 80（R3）→ 82（R4）→ 84（R6）→ 144（R9）→ 401（10-02）。
- 接手时脚手架含：TimerEngine / CountUpTimer / CommandBus / ClickGrouper / FocusAudioHandler / FocusController(仅番茄) / 三个页面 / drift 库。

## 5. 进度看板

| # | 步骤 | 对应需求 | 状态 |
| --- | --- | --- | --- |
| 0 | AGENT.md 建立 | — | ✅ 2026-07-19 |
| 1 | 音频资产（silence + 确认音 WAV） | 静音保活 / US-A06 | ✅ 2026-07-19 |
| 2 | core_feedback 声震反馈模块 | US-A06 / US-F01 / US-G03 | ✅ 2026-07-19 |
| 3 | 正计时模式接入（控制器+UI+打点分发） | US-B02 / US-A05 | ✅ 2026-07-19 |
| 4 | 暂停超阈值自动释放按键（默认 10min 可配） | US-C02 | ✅ 2026-07-19 |
| 5 | 会话落库 drift + 统计页真实数据 | US-D01 | ✅ 2026-07-19 |
| 6 | 按键自检工具页 | US-G02 | ✅ 2026-07-19 |
| 7 | 首次引导（≤3 屏）+ 权限引导 | US-G01 / US-H01 | ✅ 2026-07-19 |
| 8 | 通知栏完善（阶段显示+暂停/结束按钮） | US-F02 / US-F03 | ✅ 2026-07-19 |
| 9 | 收尾：全量测试 + analyze + 双轴 code-review | PRD-Testing | ✅ 2026-07-23 |
| 10 | Android debug APK 构建验证（脱糖修复+镜像链路诊断） | PRD-Testing §4 前置 | ✅ 2026-07-23 |
| 11 | 真机反馈 R1 修复：跳过计轮诚实统计 + 通知双发闪烁 | US-D01 / US-F02 | ✅ 2026-07-23 |
| 12 | 真机反馈 R2 修复：通知整窗闪烁根治（长静音+分钟级文本） | US-F02 | ✅ 2026-07-24 |
| 13 | 真机反馈 R3：实时结算入账 + 每轮结束待继续 + 电池优化 MethodChannel | US-D01 / US-B01 / US-H01 | ✅ 2026-07-24 |
| 14 | 真机反馈 R4：轮语义修正（专注结束自动进休息、轮结束才待继续）+ 结算串行防双插 + 统计秒级显示 | US-D01 / US-B01 | ✅ 2026-07-24 |
| 15 | 真机反馈 R5：统计为零排查 + 每 10s 周期结算（近实时统计） | US-D01 | ✅ 2026-07-26 |
| 16 | 真机反馈 R6：跨天僵尸会话守卫（清数据才恢复的根因修复） | US-D01 | ✅ 2026-07-26 |
| 17 | 横屏 UI：manifest 锁 sensorLandscape + 专注页左右双栏自适应布局 | 真机体验反馈（M500 横向机身） | ✅ 2026-07-26 |
| 18 | 真机反馈 R7：不活跃 60min 自动结束会话（幽灵 resume 假统计兜底） | US-D01 / US-C02 | ✅ 2026-07-27 |
| 19 | 详细时间统计子页：指定日期 + 24h 时间轴可视化 + 会话明细（幽灵排查工具） | US-D01 扩展 | ✅ 2026-07-30 |
| 20 | 性能优化 P0-P2：idle 停 tick + 秒级去重 + 正计时静态环 + 结算/后台降频 | 性能清单 §6-27 | ✅ 2026-07-30 |
| 21 | 真机反馈 R8：_finish 结算竞态（翻倍+幽灵行）修复 + 启动自愈 + 时间轴按段渲染 | US-D01 | ✅ 2026-07-30 |
| 22 | 初音联名主题系统：三方案四色（经典葱色/樱未来/雪未来）+ 设置页切换持久化 | 用户体验反馈（M500 初音联名机身） | ✅ 2026-07-30 |
| 23 | 性能 P3 + 低优先项：反馈音启动异步化 + release 出包流程 + weekFocus 合并查询 | 性能清单 §6-27 | ✅ 2026-08-01 |
| 24 | 性能 P4（用户定稿）：移除 Wakelock——跟随系统息屏，息屏照计时，不做开关 | 性能清单 §6-27 | ✅ 2026-08-01 |
| 25 | 专注页横屏「余光」重设计：全屏阶段染色 + 220sp 巨字 + 通栏进度条 + 呼吸求人提示 | 用户场景反馈（桌角余光使用） | ✅ 2026-08-01 |
| 26 | P0：四元素配色自定义 + 经典去橘黄（休息红主蓝辅）+ 改名 MikuFocus + 启动图标 | 用户验收反馈 | ✅ 2026-08-03 |
| 27 | V0.2：50/10 深度工作预设 + 按键映射编辑器（热生效+持久化） | US-B03 / US-A08 | ✅ 2026-08-03 |
| 28 | V0.3 数据闭环首切：统计页权限一键引导 + 设置页数据管理（收集说明/一键删除/关闭收集） | US-E01 / US-E02 | ✅ 2026-08-03 |
| 29 | V0.3：中断统计——引擎/正计时记录专注内暂停区间，详细页时间轴细条+次数+时刻 | US-D02 | ✅ 2026-08-04 |
| 30 | V0.3：任务/标签——当前标签 SP 持久化、会话开始烙印 drift（schema v5）、详细页展示 | US-B05 | ✅ 2026-08-04 |
| 31 | V0.4：弹性连续（每周 2 天缓冲、断签不清零，纯函数+护栏测试） | US-D03 | ✅ 2026-08-04 |
| 32 | V0.4：每周报告（本周/上周环比 + 最专注时段四桶） | US-D04 | ✅ 2026-08-04 |
| 33 | 真机反馈：双按=音乐下一首（释放→原生 dispatch→重霸占）+ 多击窗口 800→300ms；FN 键识别失败备案 | 用户体验反馈（两 App 同控） | ✅ 2026-08-04 |
| 34 | 余光 2.0：阶段字标 kicker + 阶段切换脉冲 + 进度条流光 + 轮次豆点亮弹出 + 统计页 12 周热力图 | UI 自由发挥（余光三原则边界内） | ✅ 2026-08-04 |
| 35 | 余光 2.0 强化：辉光巨钟 + 暂停空心描边字 + 每秒 odometer 滚动 + 开屏入场编排 + 字标装饰线；热力图铺满 + 点按查当天 | 用户反馈（变化不可见/热力图未铺满） | ✅ 2026-08-04 |
| 36 | 辉光硬边界修复（独立霓虹底层三层影）+ 通知栏优化（改名残留 MikuFocus + 轮次/打点信息） | 用户反馈（辉光受裁切） | ✅ 2026-08-04 |
| 37 | odometer 放缓 400ms + 辉光归位字形（消残影）+ 字号 240 + 辉光亮度可调；热力图 ratio 模型（用户及格线 + 二次方差距） | 用户反馈（残影/太快/要自定义） | ✅ 2026-08-04 |
| 38 | 双按转发硬路径：通知监听权限 + MediaSessionManager 直控 skipToNext（软路径真机实测无效）+ 设置页授权引导 | 真机反馈（双按转发无效） | ✅ 2026-08-11 |
| 39 | 真机反馈 R9：统计以计时为主——段开始时间戳真值源（addTime 不吞/暂停不计）+ _pausedAtMillis 持久化（自动暂停关软件不再加关闭时间） | US-D01 | ✅ 2026-08-26 |
| 40 | V0.5 AI 周报解读：本地洞察引擎 + OpenAI 兼容三预设（DeepSeek/Kimi/通义）+ 同意门控 + 同周缓存 + 降级矩阵 + 设置页 AI 区 + 统计页解读卡 | US-AI-A01~A05 / D01~D04（ADR-0006 安静原则） | ✅ 2026-09-08 |
| 41 | 引导页重写：修正长按误导（M500 不上报）+ 补双按/AI 告知 + 横屏双栏自适应 + 设置页「使用指南」随时重看入口 | US-G01 | ✅ 2026-09-08 |
| 42 | US-C01 开机恢复引导：BootReceiver 检测未完成会话发通知，点按回 App 由时间戳恢复接管 | US-C01 | ✅ 2026-09-08 |
| 43 | 真机反馈：AI 连通失败排查——读超时 15→60s（非流式整段生成）+ 402 余额不足正确归类 + 显式 Content-Length + 失败附原始摘要 | US-AI-A03 | ✅ 2026-09-09 |
| 44 | AI 主动触发与交互增强：轮次完成自动到期检查（每周首次真请求，安静短路）+ force 重新解读 + 入口按钮升级 | 用户反馈（推荐任务完成时触发） | ✅ 2026-09-10 |
| 45 | 数据导出/导入备份：drift 全量 ↔ JSON（版本校验中文报错），应用专属外存固定路径零依赖，导入前自动留存 | 用户新需求（实用向） | ✅ 2026-09-12 |
| 46 | 每日小结卡（详细页顶部）+ AI 当日一句话点评（按日缓存、轮次完成及时自动触发、可「换一句」） | 用户新需求（实用+交互） | ✅ 2026-09-12 |
| 47 | 彩蛋可达化：39 系列（3/9 ミクの日、连续 39 天、今日 39 分钟）+ 四轮进长休庆祝琶音（可关） | 用户新需求（趣味向） | ✅ 2026-09-12 |
| 48 | M500 旋钮取证引导：自检页提示转旋钮看键码（有则下轮做旋钮映射，无则归档死结） | 用户新需求（硬件向，取证先行） | ✅ 2026-09-12 |
| 49 | 详细页小结卡「说人话」重构：大字总时长 + 分 N 段/最长一段 + 起止时刻，废弃番茄/中断 jargon | 用户反馈（统计口径开发者都看不懂） | ✅ 2026-09-13 |
| 50 | AI 预设问答 chips：点选式「问 AI 一句」三题，按（周，题）缓存，AI 开即显、仅手动 | 用户反馈（AI 加交互性，M500 打字困难） | ✅ 2026-09-13 |
| 51 | AI 问答泛化双场景：详细页当日问答（任意查看日可问，按日缓存）+ 共享 AiAskChips 组件 + 答案「换一句」force 重问 | 用户反馈（再增加 AI 交互性） | ✅ 2026-09-13 |
| 52 | AI 优化（提示词为主轴）：环比改「上周同期」口径 + system/user 分消息 + 事实块单源 + token 分档 + 解析加固 + 数据指纹缓存 + 数据量门槛 | docs/08 评审（提示词重构） | ✅ 2026-09-25 |
| 53 | AI 调性轮（解「枯燥」）：洞察扩 8 字段（08-B3）+ 硬约束拆「禁空洞/要具体」+ 角色改「复盘搭档」+ 温度 0.6 + 问答题目 3→5 / 3→4 + 缓存指纹并入提示词版本 | 用户反馈（AI 太枯燥） | ✅ 2026-09-26 |
| 54 | **AI 记忆日志**（跨程序联动）：一天一条 JSONL + 字段级所有权（外部 memory 永不被冲）+ 近 7 日注入（不含当日，900 字上限）+ 设置页路径/预览/清空 + 同意文案 v2；顺带修正当日事实块含钟点与「起止明细永不外发」承诺的矛盾 | 用户需求（通过日志传递记忆，与其它程序联动） | ✅ 2026-09-26 |
| 55 | **三页背景图库**（看板 #55）：图库预处理进 `assets/backgrounds/`（75MB→5.6MB，26 张 WebP）+ 两条适配规则（≥16:9 高铺满固定 / <16:9 宽铺满随滚动，顶置）+ 三页独立异步随机（5min~5h，计时页 55% 纯色）+ 统计页今日专注缩 80% 并补四处细节 + 原生 `aiclock/backgrounds` 通道（选图/投放目录双入口、EXIF 旋转、内容哈希去重）+ 设置页背景区（预览/换一张/导入/清空）+ `docs/10` 登记表；**真机反馈三轮调参**：① 图片 40/30%→50/40%、卡片 55%→25%、计时页池改**只用规则 1**（页面不滚动，规则 2 的下半截永远看不见）；② 详细页改**按纵向溢出深度加权抽取**（规则 2 池里 7 张溢出仅 28~185px 的浅横构图观感同规则 1，均匀抽取占 32% 概率 → 加权后压到约 4%，权重全 0 回退均匀）；③ **计时页池收紧为绝不回退**（规则 1 池空→纯色，堵死「首选池空回退全池」这个规则 2 唯一漏点）+ 图片 50/40%→60/50%、卡片 25%→15% 且掺 8% 白 + 设置页每页显示候选池构成 + 版本升 0.1.1+2（真机疑似装旧包，用版本号区分）；④ **分类阈值 16/9→1.3 并重跑预处理**（规则 1 池 4→11 张、规则 2 池 22→15 张，6.0MB）+ 三页概率改为绝对比例（详细页 95/5、计时页 80/18/2、统计页全池均匀，一次掷骰子定结局）+ **「抽完下一次抽完即放回」口径落进单测** + 计时页图片 45% 且掺白 8%（`Image.color`+`srcATop`） | 用户需求（背景图 + 图库可增长） | ✅ 2026-09-30 ~ 10-01 |
| 56 | **非 M500 设备适配**：用户拿普通手机（约 2.1:1）实测后要求比例自适应——① `core/platform/device_profile.dart` 双信号识别「是不是 M500」（比例 ≈16:9 ±3% **或** Build.MODEL/DEVICE/PRODUCT 含 m500，新原生通道 `aiclock/device` 零依赖上报）；② **两个信号都不满足**才在计时页横屏左右两侧挂触屏圆按钮（左「+5分钟/正计时下=打点」，走与实体键同一条命令总线；右「暂停/继续」随状态换图标），白色 2D 微立体（白渐变+顶缘高光+底部落影，`Semantics` 无障碍标签）；③ 余光布局全部装饰尺寸乘 `uiScaleFor`（视口逻辑高 ÷ M500 基准 392.5，夹 0.85~1.8）——M500 上系数恰为 1.0 与历史调参零偏差，其它设备整体等比缩放 | 用户需求（换设备后比例不适 + 无实体键没法操作） | ✅ 2026-10-01 |
| 57 | **计时页 SafeArea 黑边修复**：非 M500 手机上「初始正常、从设置页返回后背景图上/左两侧出黑边」——根因是计时页 `Scaffold.body` 用 `SafeArea` 包了**含背景层在内的整页**，冷启动 insets=0 时正常，设置页返回后系统重新下发状态栏/刘海 insets，整页被缩进、背景不贴边（M500 恒 insets=0 从未暴露）。修法：去掉 body 层 SafeArea，背景恒 edge-to-edge；insets 手动加到**内容**上（顶栏 top、进度条 bottom、侧键 left/right）；竖屏回退布局无背景层，自己包 SafeArea | 真机反馈（非 M500 背景黑边） | ✅ 2026-10-01 |
| 58 | **图库扩充 + 配色扩展 + 配置扩展**：① 背景图库 26→**51 张**（新增 25 张 illust_*，重跑 `tool/miku_bg_prepare.py`，剔除 1 张重复，登记表自动更新；用户直接拷进 `assets/backgrounds/` 的原始 jpg/png 已清理）；② 显示配色：调色板 5→**13 色**（新 8 色从背景图库高频主色提取：亮青/深海蓝/天蓝/樱粉/玫红/珊瑚/橄榄/浅青，**追加在尾部不移动旧下标**）+ 元素改存 **ARGB**（支持 HSV 自定义拾色器：色相/饱和度/明度三滑杆+实时预览+渐变轨道）+ **配色按主题方案独立存储**（键 `glance2_<scheme>_<element>`，切换方案即切各自配色；旧全局下标键迁移进经典方案，老数据兼容）；③ 番茄钟：三档时长预设扩列（专注 14 档/短休 9 档/长休 8 档）+ 选择弹层底部**自定义分钟滑杆**（1~240）+ 新暴露「长休间隔轮数」（2/3/4/5/6/8，字段本就存在只是没 UI）；④ 每日及格线 max 480→**600 分钟（10h）** | 用户需求（图库/配色/配置/及格线四项） | ✅ 2026-10-03（构建见 §6-61） |
| 59 | **更新内容浮窗**：升级安装后首次打开弹一次「更新内容 · v0.1.x」圆角卡片，**弹出瞬间即写号**（`update_changelog_seen_code`，进程被杀也不重弹）；全新安装（引导未完成）不弹只静默记号；文案按 build 号存 `lib/app/update_changelog.dart`（发版随 pubspec 手动同步，不引 package_info） | 用户需求（更新后告知改了什么） | ✅ 2026-10-04 |
| 60 | **图库管理 + 自定义提示音**：① **图库管理页**（设置页背景区一行入口）：进入即网格预览（内置+用户合并，禁用图压暗+角标），单图大图预览含尺寸/规则/来源信息；**禁用/启用**（prefs stringList `bg_disabled_ids`，候选池自动剔除、三页背景重抽；内置图 APK 内删不掉故只有禁用）、**删除**（仅用户图：清单去条目+删 `u_*.webp`，同步清禁用集）、**加图**（AppBar 按钮走系统选图器复用既有导入链路；投放目录扫描与清空作次要操作收进页尾）；② **自定义提示音**：7 个音槽（开始/继续、暂停、结束、跳过、打点、阶段提醒、庆祝）各自可绑用户音频片段（最长 **5s**）——原生新通道 `aiclock/audio`（`AudioToolsPlugin.kt`：SAF 选音频拷入 `tones/t_<hash8>.<ext>` + MediaMetadataRetriever 探时长 + MediaExtractor/MediaCodec 解码 PCM 按时间桶取峰值降采样波形，后台线程解码主线程回投）；编辑浮窗三层：**波形可视化**（选中段高亮）+ **音乐进度轴**（可拖音符标记起点，拖波形/点按均可）+ **0~5000ms 时长轴**（Slider）；试听从起点播够时长即停（与真实反馈行为一致）；片段越界钳制「保长度挪起点」；存储 `custom_tones_v1` 单键 JSON，单条损坏隔离；`KeyFeedbackService` 加单实例 clip 播放器（换源仅路径变化时发生），focus_controller 两处调用点按槽位键传配置 | 用户需求（图库管理四操作 + 自定义提示音多音轨编辑器） | ✅ 2026-10-05 |
| 61 | **图库管理收口 + 选图「未选择」修复**：① 根因修复——选图 intent 原先包了 `Intent.createChooser`，chooser 转发让部分文件管理器返回的 URI 带不上读权限，原生探测 `SecurityException` 被静默吞 → Dart 收空列表显示「没有选到图片」；两个 intent（OPEN_DOCUMENT/PICK）改为**直接拉起不包 chooser**（`AudioToolsPlugin` 选音频同款问题一并修）；② **加图来源二选一**（2026-10-05 用户需求）：底部弹层「从相册选择（推荐，`ACTION_PICK`+MediaStore）」/「从文件管理器选择」，通道 `pickImages` 加 `source` 参数；探测加**流兜底**（fd 读不了退 `openInputStream`，EXIF 流构造需 API 24 有版本守卫）；探测失败条目 `width=0` 回报而非静默丢，提示语区分「没选」与「N 张读不出来」；③ **删除次要功能**：投放目录扫描（`scanInbox`/`inboxDir`/`kBgInboxDirName`/`probeImages` 通道全链路移除）与「清空我添加的图片」（`BgLibraryStore.clear` 移除），通道模型去掉 `isUri`（选图只有 content URI 一种来源）；管理页禁用数 > 0 时顶部加提示行；测试对齐（`bg_import_test.dart` 重写 fake 通道 + 新增 remove 用例） | 真机反馈（选图失败显示未选择 + 去掉无用功能 + 相册入口） | ✅ 2026-10-05（待构建验证） |
| 62 | **轮次转场动画（横屏先行）**：把「阶段/轮次/模式变化」的过渡从**各元素齐飞**改成**三段式时间轴编排**（1200ms，退场 260ms → 换场 480ms → 落定 520~1200ms，任何时刻只有一层在动）。新增 `presentation/round_transition.dart`：**单** `AnimationController` + 各元素按不同 `Interval` 取值（`RoundTransitionScope` 下发），旧内容以换 key 的副本走退场（并行退场/进场，不串行等待）；四处接入：① 阶段 kicker 由**硬切**改为换位落位；② 巨钟按 PD 定调做「**数字快速回滚（反向自上方滚入 300ms）+ 阶段色交叉淡入淡出**」（`_GlanceClock` 升 Stateful 记旧色，`_OdometerDigit` 加 `rollFromAbove`）；③ 轮次豆改**按序点亮**（每颗 80ms 错峰，长休四颗同时亮的「无过程感」被去掉）；④ ~~进度条加「满→空」回零**白色闪边** 200ms~~（**已回退**，PD 定：底部进度条不该动）。设置页加**三档强度**（完整/精简/关闭，`transition_intensity` prefs，纯函数解析带坏值回退 + 单测）。竖屏「余光」布局暂不动（PD 定：先横板） | 用户需求（轮次变化过渡动画，先做横板） | ✅ 2026-10-07（待构建验证） |
| 63 | **暂停改色修复 + 进度条闪边回退**（PD 真机反馈「暂停时颜色由计时蓝变成休息红再变回蓝」）：根因两层——① `paused` 在 UI 层被当成**独立阶段**取色（`_phaseColor`/`_clockColor`/`_barColor` 的 `paused => accentColor` 分支），而引擎里本来就有 `phaseBeforePause`（暂停前的阶段）却从未被 UI 使用；② 时钟交叉淡化的起点色 `_prevColor` **只在颜色变化时写、从不清理**，上一次转场留下的旧色（例如很久前某休息段的红色）一直留在字段里，下次转场（暂停/继续这类颜色并未变化的转场）就拿它当淡化起点。修法：`FocusViewState` 透出 `phaseBeforePause` 并新增 `colorPhase`（paused 时取暂停前阶段），**暂停 = 冻结不是换段**，六处颜色映射（横屏 3 + 竖屏 3）改走 `colorPhase`，进度环顺带修掉「休息阶段暂停闪成专注色」的历史硬编码；淡化起点改名 `_swapFromColor` 并**在非转场时作废**、起止色相同则不播淡化；`_PhasePulse`/`RoundTransition` 的 phaseKey 改用 `colorPhase`，暂停不再触发整屏脉冲与换段编排。进度条回零闪边按 PD 要求**完全回退** | 用户反馈（暂停颜色闪错 + 进度条不该动） | ✅ 2026-10-07（待构建验证） |
| 62 | **竖屏「余光」布局**（2026-10-05 ~ 10-06，普通手机竖持场景，多轮快速迭代定稿）：① 结构：辉光管竖排（分钟上/句读中/秒下，逐管 odometer 与横屏同语义）Stack 居中 + 左轨七控件（设置→统计→番茄/正计时→FOCUS→暂停→加时→终止）+ 右轨（阶段词 + 歌词竖排单列）+ **L 形进度带**（右缘竖条 + 底条 = 同一条带圆角拐角的路径描边，填充从左到右再向上，流光跟随）+ 右下「下一阶段」方块（与左下终止对称，画在歌词层下、右轨 IgnorePointer 保证遮挡可点）；② 歌词：本地 `files/lyrics/` + SAF 目录 → 网易云 → LRCLIB 三源（**在线 URI 必须用 `Uri.https(host, path, queryParams)`**——path 里拼 `?&` 会被编码成 %3F %26，这是两源此前一直 404 的真根因；网易云另加浏览器 UA/Referer/X-Real-IP）；位置外推（快照重锚 + 200ms 节拍）让换行不等 2s 轮询；横向 odometer 换行动画；字体/颜色/大小三项可调 + **同步辉光管**（跟随阶段色，与自定义色互斥、单入口对话框）；③ 设置：竖屏组（开关常显、组内项仅开启显示）、歌词颜色+同步合并单入口；④ 辉光亮度上限扩到 150%（存储 clamp 同步放开）；⑤ 竖屏三页独立背景 BgPage（focusPortrait/statsPortrait/statsDetailPortrait，竖屏统计页全用规则 2 池+溢出深度加权）；⑥ 六键统一样式 #dcf4ff@60%（幽灵按钮加 color/opacity 参数，横屏默认纯白不受影响）；⑦ 中文句读模式时钟缩 95%、阿拉伯模式 97% 封顶、冒号横放（RotatedBox）；⑧ 纯色背景减蓝（dark surface 0xFF141414）；⑨ 提示词/轮次圈固定 40*s 槽消除布局跳动；内容区左右对称 padding 保证辉光管严格居中；⑩ 自身 MediaSession 屏蔽双保险（原生包名前缀 + 会话标题=MikuFocus） | 用户需求（竖屏整体设计 + 八轮迭代调优） | ✅ 2026-10-06 |

图例：⬜ 未开始 / 🔶 进行中 / ✅ 完成（附日期）

## 6. 经验与坑（持续追加）

1. **`assets/audio/silence.mp3` 原本不存在**（目录里只有 README.md），FocusAudioHandler 运行时会加载失败 → 改用 Python 生成 `silence.wav` 并同步改引用；WAV 走 ExoPlayer 无兼容问题。重新生成：`python tool/generate_audio.py`（纯标准库，无 ffmpeg 依赖）。

2. **audio_service 断言限制**：`androidNotificationOngoing` 不能与 `androidStopForegroundOnPause=false` 同开（main.dart 已有注释），暂停时通知可滑走但服务常驻。

3. **长按判定无法在 Dart 侧完成**：audio_service 只透传语义回调不透传 key down/up，需原生 MethodChannel 上报 `reportLongPress()`（handler 已留入口，V0.2 补原生侧）。通知栏「结束」按钮（MediaControl.stop）已映射为同语义兜底。

4. **上一曲键语义双态**：番茄模式=+5 分钟，正计时模式=打点（tickMark），由 `core/commands/mode_dispatch.dart` 纯函数分发，映射表本身不变（ADR-0005）；正计时下 skipPhase 降级 ignored（无效果也不给反馈，防误导）。

5. **TDD 接缝约定**：只测纯 Dart 公开行为（引擎/CommandBus/反馈策略/模式分发/暂停释放/会话折算/自检日志），平台包装（振动、音频播放、通知）不进单测，靠 analyze + 真机验收。

6. **技能使用记录**：本次实施加载了 `tdd`（红绿循环、接缝测试）、`code-review`（标准+规格双轴终审）、`executing-plans`（计划批判执行）；备用 `diagnosing-bugs`（疑难 bug）、`codebase-design`（模块深化）。后续加载：`diagnosing-bugs`（§6-17 APK 构建诊断）、`ui-ux-pro-max`（横屏 UI 设计指导，看板 #17）。

7. **800ms 多击窗口与 <100ms 反馈的天然矛盾**：默认极简映射不绑定双/三按时，单按绕过 ClickGrouper 窗口立即下发（`KeyMapConfig.bindsMultiTap` 判定）；V0.2 用户绑定多击手势后自动回退窗口判定。

8. **drift 表结构变更**：focus_session 加 `mode` 列后 schemaVersion 1→2 + `migrator.addColumn`，必须跑 `dart run build_runner build --delete-conflicting-outputs` 重生成 g.dart，否则编译失败。

9. **暂停超时释放的冷启动边界**：恢复到暂停态时 `_pausedAtMillis` ~~不持久化~~ **已持久化（R9，2026-08-26）**——旧版每次重启重发 60min 宽限窗是幽灵 resume 的统计泄漏口（见经验 43）；`_sessionStartAtMillis` 持久化（杀后台后落库的开始时刻仍准确）。

10. **跳过专注阶段的统计偏差（已知简化）**：引擎把 skip 专注也计为一轮完成，actualFocus 按整轮折算偏高；phase_event 事件流落地后按迁移精确累计修正（session_record.dart 头注释已声明）。

11. **Riverpod unawaited lint**：页面里调 notifier 的 Future 方法要 await 或显式 unawaited，否则 `unawaited_futures` info。

12. **双轴 code-review（Standards+Spec）很值得**：抓到 3 处分层硬违规（handler 错放 core、platform 反依赖 feature、focus 跨 feature 直依赖 stats db）与 2 个真 bug（超时释放后通知停在「待开始」、释放后通知按钮失效无法一键恢复）。修复要点已并入 §3 架构速查。

13. **通知显示必须单一驱动源**：handler 的 acquire/release 若顺手改通知内容，必与控制器节流逻辑打架（出现错误「待开始」）。原则：平台层只提供被动接口，显示由控制器统一驱动。

14. **build_runner 挂死的两层根因（2026-07-23 实测）**：(a) 超时被杀后 dart.exe/dartaotruntime.exe 残留并持有 `.dart_tool/build/lock/`，后续进程死等——杀残留进程（用 `Get-CimInstance Win32_Process` 查 CommandLine 区分，别误杀 IDE 的 language-server/devtools）+ `rm -rf .dart_tool/build/lock`；(b) 更隐蔽的是**陈旧 asset_graph.json**（分层迁移移动过 db/handler 文件后未 clean），表现为每次跑 ~15s、产出 1 output 后 CPU 归零永久冻结、无任何报错——`dart run build_runner clean` 后 52s 全量重建成功。另：build_runner 2.15 已移除 `--delete-conflicting-outputs`（警告可忽略），改表后重生命令直接用 `dart run build_runner build`。

15. **Git Bash 里直接跑 `./gradlew` 会踩系统 Java 8**（环境说明文档坑#1）：必须 `export JAVA_HOME="E:\\IDL\\b\\jbr"`（JBR 21），否则报 "Dependency requires at least JVM runtime version 11"。`flutter build apk` 自动注入 JBR 无此问题——诊断换环时别让新故障掩盖原症状。

16. **flutter_local_notifications 17.x 强制 coreLibraryDesugaring**（AAR metadata 检查直接 fail）：app/build.gradle.kts 加 `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`（AGP 8.11 配 2.1.x，插件 README 最低 1.2.2）。

17. **flutter_tools included build 不走项目镜像**：`settings.gradle.kts` 的 `includeBuild(flutter_sdk/packages/flutter_tools/gradle)` 用其自身 repositories 直连 mavenCentral，国内间歇性超时（项目侧无镜像杠杆）。对策就是**重试+gradle 缓存增量推进**（首次 23min 挂、重试跑完 1h 成功，缓存热后 185s）；包装进程超时被杀不代表 gradle daemon 死了——判成败看日志里的 BUILD SUCCESSFUL/FAILED 和 APK 产物，不看任务状态。技能记录：本轮加载第 4 个技能 `diagnosing-bugs`（诊断环纪律），用于 APK 构建失败的系统化排查。

18. **真机反馈 R1 两处根因（2026-07-23）**：(a) 通知闪烁 = `updateTimerDisplay` 每次同时 `mediaItem.add` + `playbackState.add`，双流各触发一次系统 notify()，2Hz 重绘；修为 playbackState 仅在 running 变化时重发（`_lastNotifiedRunning` 跟踪，showIdleDisplay 复位），若仍闪下一杠杆是通知文本去秒级。(b) 跳过计轮偏差 = `skipPhase` 与自然结束共用 `_advanceToNextPhase`；拆出 `natural` 参数时注意 **`0 % N == 0` 陷阱**——轮数未涨时直接取模会误判长休，必须 `rounds > 0 &&` 守卫。旧库已落的偏高记录不迁移（finish-only 落库语义下成本不值）。

19. **真机反馈 R2：整窗闪烁的两个叠加源头（2026-07-24 根治）**：R1 的双发修复不够——用户实测标题+阶段+时间整个通知都在闪。源头一：**1 秒 silence.wav 每秒循环**，ExoPlayer 每次循环发状态事件，audio_service 随之整窗重发通知（与文本节流完全无关）；修为 2 分钟 @ 8kHz 静音（1.9MB，`tool/generate_audio.py` 已参数化采样率，需重新运行脚本生成）。源头二：**通知文本本身秒级变化**，M500 ROM 对每次 notify() 整窗重绘；修为通知时间改分钟级（`formatRemainingMinutes` 向上取整 / `formatElapsedMinutes` 向下取整，App 内大屏仍 mm:ss 不变）。教训：**平台包装层的事件源（播放器循环、流重发）也要计入通知刷新率预算**，只盯自己代码的节流会漏。

20. **真机反馈 R3（2026-07-24）三个根因与对策**：(a) 「学一天统计为零」= finish-only 落库 + 自动续轮 = 会话永不结束永不落库——改**实时结算 upsert**（`_settle`：每轮自然完成/跳过/暂停增量入账同一行，`_activeSessionId` + `_lastSettledFocusMillis` 游标随 prefs 持久化防杀后台重复计数；进行中结算 endAt=null/completed=false 保持表语义）。(b) 自动续轮改 `PomodoroConfig.autoContinue`（默认 false「待继续」）：**复用暂停态语义**（phaseBeforePause=下一阶段、剩余冻结为全长、resume 即开始），零新状态机；注意待继续态要手动挂 `_onSessionPause()` 纳入超时释放。(c) **脚手架坑：设置页番茄配置从未下发引擎**（引擎只在创建时读一次 provider）——构造时 `_engine.config = provider` 同步一次 + `ref.listen` 实时下发，顺带修复。(d) 原生 MethodChannel 落地姿势：MainActivity 继承 `AudioServiceActivity`（媒体键路由不变）挂 `aiclock/permissions`，manifest 指向全限定类名；电池优化走 `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` 名单页（直接请求授权权限上架审核敏感）。

21. **真机反馈 R4（2026-07-24）轮语义定案与三个新坑**：(a) **语义定案**：一轮 = 专注+休息完整循环。专注结束**永远自动进休息**（休息是被动的，不需用户在场承诺）；休息结束才按 autoContinue 决定（false 默认 = 待继续，暂停在下一段专注起点等按键；true = 全部自动）。关键理由：若休息结束自动开始专注，人不在设备旁时专注空跑会记出**假专注**，直接毒害用户最在意的诚实统计；且每循环只需按一次键。跳过任何阶段（含休息）遵循同一规则，行为统一可预期。**替代方案备查**：若用户其实想要「专注结束就暂停、按键才开始休息」（B 模型），只需对调 `_advanceToNextPhase` 两个分支的语义。(b) **结算必须串行**：裸 `unawaited(_settle())` 时两个并发 settle 会同时读到 `_activeSessionId==null` 各插一行 → 统计翻倍；加 `_settleQueue`（Future 链 + `_queueSettle` 入队）后后一次必读到前一次写入的 id。教训：**fire-and-forget 的 upsert 竞态不会在单测里暴露**（单测不并发），只能靠不变量推理（"读 id→写库"不是原子的）。(c) **「0m」显示层假失效**：统计页 `_formatDuration` 只显示到分钟，短测试会话明明落了库却显示「0m」+ 番茄 0 个 = 用户视角"统计完全失效"。修为精确到秒。教训：**用户报"完全失效"时先分层排查**——落库层（旧包 finish-only）、显示层（精度截断）、数据层（时间统计本就纯秒累计、与轮次无耦合），三层根因完全不同。(d) 时间统计自 R1 起就是纯秒累计（accumulatedFocusMillis），与轮次零耦合——用户怀疑"轮次没变导致统计失效"不成立，但怀疑方向（轮次是脆弱信号）本身值得保留。

22. **真机反馈 R5（2026-07-26）"含一次跳过统计仍为零"排查与周期结算**：逐行排查落库链路（`_settle` → `insertOnConflictUpdate` → 统计页按 `startAt` 当日求和、**不过滤 endAt/completed**）未找到必然为零的逻辑 bug；两个最可能成因：(a) 跳过按诚实设计 rounds=0（番茄数 0 是对的），时长只有跳过前部分——若装的仍是 R3 旧包（分钟级显示），短部分显示「0m」叠加番茄 0 = 看起来全零；(b) 真机上 `_settle` 若抛异常只会 debugPrint 到 logcat 静默吞掉（`adb logcat | grep flutter` 可见 "settle failed:"）。**真实设计缺口**：结算只在轮完成/跳过/暂停/结束四个事件点触发，专注进行中从不入账——一轮 25 分钟里前 24 分钟统计页都是零。修为 `_maybePeriodicSettle`：会话运行中（番茄含休息/正计时）每 10s 经同一串行队列 upsert 一次（进行中专注由 fromPomodoro 按已做部分折算），节流游标 `_lastPeriodicSettleAtMillis` 随 `_onSessionEnter`/`_finish` 复位。注意周期结算会把 `_lastSettledFocusMillis` 推高到含进行中折算的值，使 `_settleIfAccumulated` 的事件点门槛偶尔跳过——无害，周期结算 10s 内补齐，不会丢数据。**诊断价值**：R5 包开始专注 10 秒内统计页必出数字，一眼区分「没写库」与「显示问题」。

23. **真机反馈 R6（2026-07-26）"清数据后才恢复记秒"= 跨天僵尸会话，根因定案**：用户实测清用户数据后统计立即正常——锁定根因**不在写库，在持久化状态**：升级安装不清数据时，R3/R4 时代持久化的「待继续」暂停会话（startAt=几天前）被恢复，用户按键"开始"实为 resume 旧会话；之后所有结算（含 R5 周期结算）都 upsert 到 startAt 属旧日期的同一行，统计页按当日 startAt 过滤 → **今天永远为零**。R4 待继续语义使此坑成高频路径（暂停过夜 → 次日 resume → 全天统计归昨天）。修为构造期 `_discardStaleDaySession` 守卫：恢复后会话 startAt 非同本地日 → 先 `_buildSessionRecord` 捕获快照+行 id，再复位引擎/游标，最后快照异步入账旧行（`_flushSnapshot`，同一行覆盖不双计不丢历史）。**两个实现陷阱**：(a) 异步 settle 读的是执行时的活引擎状态——先排队再 reset 会拿到 0（冲洗失败），必须先快照后复位；(b) 快照写库若读复位后的 `_activeSessionId`（已置 null）会双插新行——行 id 也要随快照捕获。companion 构建抽出 `_companionOf` 共用。辅助函数 `isSameLocalDay` 放 time_format.dart（纯 Dart，2 用例）。教训：**"清数据后就好了"是持久化状态污染的指纹**，排查优先级应高于业务逻辑；杀后台恢复类功能要把「恢复出的状态跨版本/跨天是否还有效」列为设计 checklist 项。另：会话运行中自然跨零点（未杀进程）仍归开始日——§7 已记录的归因限制，概率低成本高，维持不修。**热修（同日）**：守卫在构造函数中早于 `_mode` 赋值执行，`_buildSessionRecord` 读 late `_mode` 抛 LateInitializationError（恰好只在有跨天旧会话的设备上触发，测试无覆盖——控制器不在单测接缝内）；修为把 `_mode = ref.read(timerModeProvider)` 提到守卫调用之前。教训：**构造函数里 late 字段的赋值顺序是真实契约**，新增前置调用时先核查它（间接）读了哪些 late 字段。

24. **横屏适配（2026-07-26，M500 横向机身实测驱动）**：设备按横向放置设计（侧边键，右朝上左朝下），原专注页是竖屏单列——横屏下 720p 画布仅 640×360dp，240 环 + 单列必然溢出。方案（技能 `ui-ux-pro-max` 指导）：(a) manifest `android:screenOrientation="sensorLandscape"` 锁定——"推荐横屏"落地为"始终横屏"，两方向 180° 自适应；(b) 专注页 OrientationBuilder 双分支：横屏左右双栏（左 flex11 计时环主视觉，直径随高度自适应上限 300、字号按 0.35×环径缩放 56~96sp；右 flex9 四段：阶段行/模式切换/按键提示卡/主按钮+入口，SingleChildScrollView 兜底小窗口），竖屏保留原单列作回退保险。子组件（_PhaseHeader/_ModeSwitcher/_CountdownRing/_KeyHintCard/_BottomBar）两布局共用，`_CountdownRing` 加 `size` 参数。教训：**小屏设备适配先算逻辑像素画布**（5 寸 720p ≈ 横屏 640×360dp），布局方案由画布高度反推，别从竖屏移植。

25. **真机反馈 R7（2026-07-27）"没碰它却多出 2 小时统计"= 幽灵 resume，双触发保留项的统计侧兜底**：机制链——「待继续」会话无限期等待按键（设计如此）+ FGS 保活进程不死 + M500 ROM 媒体键双触发（保留项）把下午听音乐的按键漏进本 App → 每漏一次播放键就 resume 一轮 25 分钟专注 → 如实入账，漏 5 次 ≈ 2h 假统计。autoContinue=false 无辜——不是自动续轮，是幽灵按键在续。**修法不是区分按键来源**（audio_service 里物理键与通知按钮走同一 onPlay 回调，不可区分），而是**不活跃超时自动结束**：`PauseReleasePolicy.shouldAutoFinish`（默认 60min，纯函数 4 用例）+ 控制器 `_onTick` 里 `_checkAutoFinish`（paused 含待继续/正计时暂停 超阈值 → `_finish()` 最终结算+复位+释放+通知回 idle）。效果：单次不活跃期幽灵累积 ≤ 1 轮；真实用户离开数小时后回来看到干净的全新开始（语义也更好——午休后的「待继续」本就该作废）。**残余风险**：自动结束后 phase=completed，幽灵播放键仍会 start 新会话（idle/completed 按键开始是零触屏核心流程，不能禁）——每 ~85min 周期最多 1 轮幽灵，根治仍依赖双触发取证（logcat）后从媒体会话仲裁层解决，见 §7。**用户侧清理**：已入库的假统计（2h）无迁移工具，介意则清一次应用数据归零重记。教训：**"无限期等待用户输入"的状态在按键不可信的环境里必须有 TTL**；设计会话类状态时把「输入通道可能收到幽灵事件」列为对抗性假设。

26. **详细时间统计子页（2026-07-30，看板 #19）**：为幽灵排查与日常复盘做的会话级可视化。实现要点：(a) 数据零新增——复用 `sessionsOfDay` + `daySessionsProvider`（FutureProvider.family，入参任意时刻内部归一本地零点；family 参数是 DateTime 时**每天实例独立缓存**，翻日期不串数据）；(b) 时间轴用 LayoutBuilder+Stack+Positioned 手绘（底槽/网格线/会话块/现在竖线），不引 fl_chart——fl_chart 的时间轴 API 对这种「24h 固定域 + 任意起止块」反而是重锤；(c) 会话块宽下限 3px（极短会话仍可见）、left/width 双重 clamp 防跨天溢出；(d) 进行中会话块半透明并延伸到 now（仅今天；历史日防御性延伸到当日末）；(e) `_formatDuration` 从 stats_page 提取为 time_format 的 `formatDurationText` 两处共用——**显示格式化函数一旦有两处需求就立即入 core 共用**，这是继通知时间格式后的第二次格式漂移预防。入口：统计页 AppBar 时间轴图标，路由 `/stats/detail`。

27. **性能优化清单（2026-07-30 评审定档，待按序实施）**：用户提了 6 项（心跳降频/秒级去重/SP 防抖/停静音实验/自绘环+RepaintBoundary/暗屏/后台降频），评审结论 + 补充项按收益排序：**P0** = A【无会话 idle 完全停 tick——当前 ticker 从启动跑到退出永久空转，收益最大】+ 秒级去重 `_emit`（remaining/elapsed 秒数不变不刷新，比降 tick 频率更关键，500ms tick 保留可让阶段提醒延迟 ≤0.5s）；**P1** = 正计时 `value:null` 无限旋转改静态弧（唯一持续烧 GPU 的点；determinate 进度条只是 500ms 补间，非持续重绘）+ 状态分片（remaining/elapsed 走独立 ValueNotifier，静态区不感知心跳）；**P2** = 周期结算的 `_persist` 降频到 60s（崩溃恢复精度损失 1min 可接受）+ 后台 lifecycle 降频；**P3** = release 出包流程（**当前一切性能感受来自 debug 包=JIT 噪声，性能结论必须以 release 为准**，别为 debug 卡顿做优化）+ 启动路径延迟初始化（反馈音预加载异步化）；**P4 产品决策** = 息屏计时开关（时间戳计时免疫息屏，WakelockPlus 全程常亮是最大单一耗电项，做了它暗屏/亮度调节可不做）；**P5 真机灰度** = 停静音播放实验（标准 Android setActive+MediaButtonReceiver 可收键，但 M500 定制 ROM 有双触发前科，必须开关化灰度试，不能直接换）。低优先：weekFocus 7 次串行 DAO 查询合并（仅统计页打开时发生）。**P0-P2 已实施（2026-07-30，看板 #20）**：`_syncTicker` 幂等管理心跳（无会话停表/前台 500ms/后台 5s，WidgetsBindingObserver 驱动 lifecycle 降频，构造/命令/tick 尾部同步）；`_onTick` 秒级去重（显示秒数未变且无阶段轮转/按键释放不 `_emit`，运行中 ~1Hz、暂停态零刷新）；正计时环 running 画静态满环；`_persistThrottled`（60s）专供周期结算。两处**有意的取舍**：(a) 状态分片降级为 RepaintBoundary 包环——秒级去重后 rebuild 已降到 1Hz 且子树极小（几个 Text），拆 provider 的收益/回归风险不成比例，真机若仍掉帧再做；(b) 正计时满环=「进行中」指示而非进度，语义需在真机确认是否误读。**P0 的连带影响**：ticker 停止期间 `_checkAutoFinish`/`_maybePeriodicSettle` 不运行——二者本就只在有会话时有意义（有会话 ticker 必在），已推理确认无回归。

28. **真机反馈 R8（2026-07-30）"彻底关闭再打开：轮次清空+统计翻倍+4 条会话"= `_finish` 结算竞态，快照模式第三次救场**：症状链——性能版装机后彻底关闭再打开，详细页出现 2 条「进行中」悬空行（15 轮/5 轮）+ 1 条 0 时长却背 15 轮的幽灵行 + 1 条 0 轮进行中行，统计翻倍。**根因定案（三个确定性缺陷）**：(a) **`_finish` 先 `_queueSettle(isFinal:true)` 再同步清游标**——队列化 settle 在微任务执行，读到的是**清零后**的游标：startAt 退化为 now（0 时长幽灵行）、sessionId 为 null（新插行而非更新同一行）、真行 endAt 永远 null（保持「进行中」）；真行+幽灵行同时计入求和 = 翻倍。这与 R6 跨天守卫踩过的是**同一个时序陷阱**（"先排队后清游标"），修法复用同一快照模式：`_buildSessionRecord` 捕获 record + sessionId → finish 引擎/清游标 → `_flushSnapshot` 异步入账。教训升级：**凡是"先排队异步、后同步清状态"的写法都天然竞态**，快照必须发生在任何状态变更之前——第三次出现后应视为本控制器写库路径的铁律。(b) **R7 自动结束路径漏 `_persist()`**：自动结束不经 `_onCommand`，游标清理不落盘，杀后台后恢复出过期 sessionId。(c) **历史遗留悬空行无修复机制**：旧包产的 endAt=null 行会永远留在库里污染统计。**启动自愈**：`_repairSessions`（构造期 fire-and-forget）= `closeOrphanOpenSessions`（endAt 回填 startAt+actualFocus，诚实口径）+ `deleteImpossibleSessions`（**物理不可能行判据：actualFocusMillis > (endAt-startAt) + 65s**——0 时长幽灵行的指纹）。**时间轴按段渲染**：引擎新增 `focusSegments`（自然完成记 [endsAt-整轮, endsAt]、跳过记 [now-已做, now]，随 JSON 持久化，finish 保留供结算、start/reset 清空），schema v4 加 `intervalsJson`，详细页每段一块、段间空白即休息/暂停空隙——「断断续续完成」直接可见；老数据 intervalsJson=null 回退整段渲染。单测 +4（边界/跳过部分区间/JSON 往返/finish 保留语义），全量 92 绿。**遗留**：用户两条「8:24 起」行的精确成因未完全还原（多竞态叠加），三个确定缺陷已覆盖全部症状，真机复测验证。

29. **初音联名主题系统（2026-07-30，看板 #22）**：M500 是初音联名机身，原主题红/绿两色与联名无关。调研确认**初音官方代表色「苍绿」#39C5BB**（多源一致），三方案取自官方「季节系列」形态——经典葱色（默认）/樱未来（粉白暖调）/雪未来（冰蓝低饱和），区分度由 IP 自身保证。架构按 `design-system-patterns` skill 的 token 三层落地：primitive（各方案 hex 常量）→ semantic（`AppSkin` 四语义色：focusRing/breakRing/**accent（新增）**/danger）→ component（计时环/图例/正计时区分色）。要点：(a) **危险色跨方案稳定红系**——语义色（危险=红）不随方案漂移，避免用户认知成本；(b) accent 兼作 `ColorScheme.fromSeed` 种子，整页按钮/强调随方案联动；(c) 选择持久化走 `appThemeSchemeProvider`（照搬 keysTakeover 姿势），app.dart watch 即时换肤无需重启；(d) 详细页正计时色从 `colorScheme.tertiary` 改 `skin.accentColor`——fromSeed 生成的 tertiary 会随种子漂移，**区分色必须锚定语义 token 而非派生色**；(e) 测试加「区分度护栏」（三方案 focus/break 色两两不同的断言），防未来改色撞车——**配色类常量也要写回归断言**。Flutter 3.41 新坑：`RadioListTile` 的 groupValue/onChanged 已废弃，需外套 `RadioGroup`；`Color.value` 废弃改直接比色。skill 使用记录追加：`design-system-patterns`（第 6 个，token 分层与主题基础设施）。

30. **性能 P3 + 低优先项（2026-08-01，看板 #23）**：(a) **反馈音预加载异步化**——`main.dart` 的 `await feedbackService.init()` 阻塞首帧（多个 AudioPlayer.setAsset 串行加载），改 `unawaited`：`play()` 本有 `_initialized` 守卫，代价仅启动后 ~0.5s 内按键无声，按键功能不受影响；`audioHandler.init()` 保持 await（按键必须从第一刻可用，二者关键性不同——**启动路径上每个 await 都要过「首帧前没有它会怎样」的质询**）。(b) **weekFocus 合并查询**——原 7 次串行 `totalFocusMillisOfDay` 改 DAO 单方法 `dailyFocusMillisOfRange`（一次区间 select + Dart 按本地零点分桶），仅统计页打开时发生但消除串行往返。(c) **release 出包流程**——`flutter build apk --release`（无 signingConfig 时自动用 debug 签名，侧载够用；上架才需正式签名）。**此后性能结论一律以 release 包为准**，debug 包的 JIT 噪声不再作为优化依据（§6-27 P3 原则）。release 首坑：`:usage_stats:verifyReleaseResources` 报 `android:attr/lStar not found`——usage_stats 1.3.1 写死 `compileSdkVersion 30`，lStar 需 API 31+。**外部 Gradle 钩子三轮试错全部无解**：plugins.withId 在 apply 时触发、被模块自身脚本后写的值覆盖；裸 afterEvaluate 因模板自带 `evaluationDependsOn(":app")` 使部分子项目已评估而抛 "already evaluated"；`gradle.beforeProject` 里注册 afterEvaluate 合法但对 AGP 读 compileSdk 仍太晚（"It is too late to set compileSdk"）。**最终方案：third_party/usage_stats 内置插件源码（323K）打补丁 compileSdk 30→36 + pubspec `dependency_overrides` 指本地**——可复现、入版本控制；analysis_options 排除 third_party；上游修复后可移回托管版。教训：**老插件的硬编码 SDK 版本问题，vendor 补丁比构建脚本魔法可靠**；release 构建才会跑 verifyReleaseResources，debug 通过不代表 release 能过。

31. **P4 息屏计时的产品定稿（2026-08-01，看板 #24）**：用户拍板「跟随系统，默认息屏也计时，不做按钮」——不是加开关，而是**直接移除 wakelock_plus 全部 6 处调用 + 依赖**。依据：计时由时间戳差值保证（引擎 toJson 存 endsAtMillis 墙钟，息屏/杀后台恢复后时间差自动成立，§6 经验 9/23 已多次验证），常亮只是显示偏好而非功能必需；M500 室内使用场景用户自己会按电源键。连带清理：`_finish`/`_checkPauseTimeout` 的 disable 调用、相关注释、pubspec 依赖。**P5 停静音实验搁置**：用户未表态，维持静音 keep-alive 现状（M500 ROM 双触发前科下保守为上），开关化方案留在 §6-27 备查。

32. **专注页横屏「余光」重设计（2026-08-01，看板 #25）**：用户场景定稿——设备右上左下横放桌角、处于**余光范围**、后台音乐外放、交互靠提示音+实体键。由此推出与「手持近看」完全不同的设计三原则，可作为本 App UI 的第一性原理存档：(a) **颜色报状态**——全屏底色随阶段染色（AnimatedContainer 700ms 渐变，phaseColor alpha 0.14；「求人」时刻提亮到 0.26），阶段切换整屏变色是余光不需聚焦就能接收的第一信号；主题系统四色（看板 #22）正好是染色源，主题切换即整套氛围切换。(b) **大字报时间**——220sp + FittedBox 自适应收缩（约屏高 40%），一米外可读；`FontFeature.tabularFigures()` 等宽数字消除每秒宽度抖动；**细进度环在一米外不可读，降级为底部 6px 通栏进度条**（「本轮走了多远」的远距可读形态）。(c) **不求助时无杂物**——平时只有时间+阶段词+轮次豆（●●●○ 图形化长休节奏，替代「第 N 轮」文字）；唯一「屏幕求人」时刻是暂停/待继续：呼吸感 28sp 大字「按播放键，开始下一轮」（单行 FadeTransition 局部动画，GPU 可忽略）。触屏操作收敛右上角小组件（紧凑模式切换+统计+设置），横屏不再放大按钮——主操作是机身键。竖屏保留旧组件作回退保险。设计方法教训：**先定「用户看屏幕的距离和注意力预算」（1m/余光/<0.5s），再决定元素去留**——近看 UI 的「清晰层级」（环+卡片+按钮四段）在远距场景全部失效，远距场景的信号优先级是 颜色 > 巨大形状 > 文字。

33. **P0 配色自定义 + 品牌落地（2026-08-03，看板 #26）**：用户验收「余光」后提的 P0 修改，四个点：(a) **时钟色与进度条色分离**——原设计两者同取 phaseColor，用户要「葱色钟+红条」式强对比；落地为**四元素独立自定义**（专注/休息 × 时钟/进度条），`GlanceColors`（4 个调色板下标）+ `glanceColorsProvider` 持久化，调色板固定五色=蓝绿/红/紫/白/黑（用户定稿「经典葱色没有橘黄」），默认=专注葱钟红条、休息红钟葱条（红主蓝辅）。设置页新增「显示配色」区四个选色项。架构教训：**「用户要自定义」时给固定调色板+元素槽位，不给取色器**——五色板既满足个性化又守住视觉底线（不会出现撞色灾难），这正是看板 #22 计划里「不做自由取色器」的落地形态。(b) 经典葱色 skin 的 breakRingColor 暖橘→红（#E53935），休息氛围染色随之变红。(c) 改名 MikuFocus：AndroidManifest `android:label` + MaterialApp `title` 两处。(d) 启动图标：用户供稿 PNG（2048²，带「豆包AI生成」右下角水印）→ **先 PIL 裁剪**（中心 68% 正方形去水印+紧凑构图，存 `assets/icon/app_icon.png`）→ 前景版缩 64% 居中（自适应图标安全区）→ flutter_launcher_icons 生成全套 mipmap。水印类素材**裁掉比修掉干净**。改图标后重跑 `dart run flutter_launcher_icons` 即可。

34. **US-B03 预设 + US-A08 映射编辑器（2026-08-03，看板 #27）**：(a) **US-B03** 设置页番茄钟区顶部加「节奏预设」入口（经典番茄 25/5 / 深度工作 50/10 带推荐理由），选后 `copyWith(focus+shortBreak)` 一次更新；`_presetLabel()` 反推当前命中预设或显示「自定义」。教训：**预设=批量写已有字段+一个反推 label 函数就够，不要为预设单建存储**。(b) **US-A08 的关键缺口是 keyMap 没有持久化**——`KeyMapConfig.toJson/fromJson` 早就就绪、drift `key_map_preset` 表也建了，但 main.dart 一直 `CommandBus()` 无参构造走 defaults，重启必丢。这是「脚手架备好无人接线」第二例（第一例：R3 配置未下发引擎）。**排障顺序教训：做「编辑器」前先验证「读写闭环」是否存在，UI 是最浅的一层**。最终没走 drift DAO（多套预设是 V0.2+ 的事），照 TimerModeNotifier 姿势存 SP `key_map_custom`（`keyMapFromStorage()` 纯函数装载，FormatException 回退 defaults，可单测）。(c) **CommandBus 是纯 Dart 可变对象，ref.watch 感知不到 keyMap 变化**——新增 `KeyMapConfigNotifier`（focus_controller.dart 内、commandBusProvider 旁）作为编辑唯一入口：改 state 的同时写回 `_bus.keyMap`（handler 侧 bindsMultiTap 立即感知 800ms 窗口策略变化）+ 写 SP。映射编辑器的「立即生效」= Notifier 三行 `_apply`，不要在 UI 层直接摸 bus。(d) **tickMark 不可出现在可选命令列表**：它是上一曲键在正计时模式由 mode_dispatch 改写的语义，不是可绑命令；`ignored` 在编辑器里语义=「移除该键映射」（remap 里 remove 而非存 ignored）。(e) 双/三按绑定 → 单按回退 800ms 窗口结算的取舍 ADR-0005 已预见，编辑器底部一行小字说明即可，不做开关。测试补 fromJson 容错（未知事件/命令名丢弃）+ keyMapFromStorage 三条路径。装机验证点：改映射立即生效且重启保留；恢复默认=清 SP 回出厂；FN 键键码待用户在自检页实测上报（解锁 US-A07）。

35. **US-E01/E02 + 用户手改触屏按钮备案（2026-08-03，看板 #28）**：(a) **用户直接改码备案**：用户在 focus_page 自加 `_GlancePrimaryButton`（横屏 idle/暂停/完成态显示触屏主按钮，复用 `tapPrimaryButton`，运行中隐藏）——动机是**首启实体键偶发无效，触屏按一次后按键恢复**（疑似 MediaSession 首轮激活时序，未深究，用户明确放弃追查）。后续改 focus_page 横屏区必须保留此按钮；该现象若复发，排查方向：handler init 完成前首键被吞。(b) **真机备注**：用户报告一次「莫名 +1h 统计后自行纠正」——与 R8 启动自愈（`closeOrphanOpenSessions`/`deleteImpossibleSessions`）行为吻合，系自愈机制按设计工作，不立案。(c) **US-E01**：`usagePermissionProvider`（FutureProvider<bool>）+ `todayAppUsageProvider` 改为依赖权限状态（未授权直接返空表），统计页未授权时显示授权引导卡（说明+「去开启」按钮，返回后 `ref.invalidate(usagePermissionProvider)` 自动刷新）——**「一键引导」的重点是返回后状态自动续上，不只是跳设置页**。(d) **US-E02**：设置页新增「数据与隐私」区——收集说明（专注记录存本机 drift；应用使用时长系统接口实时查、不留存不上传——`usage_stat_daily` 表存在但无人写，第三例「脚手架备好无人接线」，本切片选择**不落库**而非补写入：US-D02 切出检测才需要历史，届时再建写入管线）、「删除全部专注数据」（confirm dialog → 新 DAO `deleteAllSessions()` → invalidate 四个统计 provider，family provider 直接 `ref.invalidate(daySessionsProvider)` 全组合失效）、「关闭应用使用统计」（跳系统页撤销权限）。(e) drift DAO 加手写方法（`delete(t).go()` 这类）**不需要 build_runner**，只有表结构/查询 API 变更才需要。

36. **V0.3/V0.4 四项一批（2026-08-04，看板 #29-32）**：(a) **US-D02 中断统计的关键认知：段区间（intervalsJson）看不见暂停**——番茄段按「计划结束时刻-整轮」折算，暂停被包在段内；正计时段是整段。所以中断必须**独立记录**：引擎/正计时各加 `_pauses: List<(int, int?)>`，专注中 pause 记开、resume/skip/finish 闭（`_closeOpenPause()` 带「无开放记录静默跳过」守卫——「待继续」合成暂停态 resume 时无对应记录）；休息阶段暂停不记（不是分心）。序列化 `[start, endOrNull]`，drift schema v5 `pauses_json`。详细页时间轴把中断画成危险色细条叠在专注块上（休息空隙是空白、中断是红条，语义分层）。(b) **US-B05 标签**：`CurrentTagNotifier`（当前标签+清单存 SP，清单上限 12 去重前移）；**烙印时机=会话开始（_onSessionEnter 捕获进 `_sessionTag`）**，之后改标签不回溯；`_sessionTag` 随 `_persist` 存 SP 防杀后台丢。**R8 同类坑再现**：`_companionOf` 不能读 `_sessionTag` 字段——快照冲刷（_finish/_discardStaleDaySession）是异步执行，读到的是清零后的值；tag 必须像 record/sessionId 一样**先捕获再传参**。(c) **US-D03 弹性连续的口径抉择**：缓冲日「算不算连续天数」？最终定稿**不算尾部**——连续天数=锚点到链条内最老专注日的跨度（中间缓冲日计入），链条尾部（最老专注日之后往回）的缓冲日不计入，bufferUsed 只计跨度内缺勤。否则 3 天专注+2 天缓冲被吹成「已连续 5 天」，违反诚实统计家风（R1 起的一贯原则）。**统计算法先把口径定义写成测试再实现**，这轮就是先写测试逼出了口径修正。(d) **US-D04 周报**：ISO 周（周一起），环比=上周无数据时 null 不误导；最专注时段按会话 startAt 小时四桶（跨时段会话整段归开始时段，与跨天归因同级的诚实简化，已注释）。(e) **环境坑：drift_dev 2.34.0 与 sqlparser 0.44.6 源码级不兼容**（`DartPlaceholder.when` 被移除，build_runner AOT 编译直接挂）——`dependency_overrides: sqlparser: 0.44.5` 钉版解决；**升级 drift 系时必须联动复核 sqlparser**。caret 约束在 0.x 包上不设防，transitive 破坏性更新会自己溜进来。(f) schema v5 一次迁移加两列（pausesJson+tag），`addColumn` 两次调用即可；DAO 新增 `sessionsOfRange` 手写方法无需 codegen。测试 104→120。

37. **双按=音乐下一首 + 多击窗口 300ms + FN 死结（2026-08-04，看板 #33）**：(a) **FN 键识别失败备案**：用户实测自检页按 FN 无任何事件——M500 的 FN 键不进标准媒体键通道（疑似主板组合键直接被 ROM 拦截），US-A07 判死结归档，不再尝试应用层接入；设置页预留 ListTile 保留（未来 ROM 开放键码再说）。(b) **多击窗口调研结论**：300ms 是行业事实标准——Android `ViewConfiguration.getDoubleTapTimeout()` 与 Flutter `kDoubleTapTimeout` 均为 300ms，Web 臭名昭著的 300ms click delay 本质就是同一个单/双击歧义窗口；**只要单按和多按共用一个键，等待窗口不可消除，只能压短**（更激进的「立即执行+撤回」对开始/暂停这类有副作用命令不适用）。故 ClickGrouper 800→300ms。ADR-0005 的「<100ms 反馈」目标在绑定多击时让位于功能——这是用户明确选择（双按功能 > 单按零延迟），编辑器解绑双/三按即可恢复立即下发。(c) **双按转发「音乐下一首」的链路**：`_forwardNextToMusic()`（controller）= 布防回环守卫（`ignoreNextUntilMillis=now+1500`，吞掉 ROM 可能路由回本 App 的回环 NEXT）→ `releaseKeys()`（停静音+AudioSession setActive(false)）→ MethodChannel `aiclock/media_forward`/`dispatchNext`（MainActivity: AudioManager.dispatchMediaKeyEvent DOWN+UP 成对——部分 ROM 只认成对事件）→ 700ms 后 sessionActive 且接管开关仍开则 `acquireKeys()` 重霸占。注意 **`releaseKeys` 停的是 AudioSession（音频焦点）不是 MediaSession**，ROM 是否把转发的 NEXT 给音乐 App 取决于其媒体会话仲裁——**必须真机验证**，失败模式=双按无效（守卫保证不会误触 skipPhase），届时再评估 `MediaSessionManager.getActiveSessions`+NotificationListener 的硬路径。(d) 默认映射变更：`doubleTap=forwardNext` → **bindsMultiTap 默认变 true，单按默认走 300ms 窗口**——command_mapping_test 的「默认不绑多击」断言翻转为「默认绑定+解绑后绕过」两个用例。(e) 按键未接管时（暂停超时归还）双按不可拦截——物理键直接到音乐 App 是两次 play/pause，等价无操作，属预期；编辑器提示文案已注明「仅在计时接管期间有效」。

38. **余光 2.0 的动画纪律（2026-08-04，看板 #34）**：(a) 余光场景只许两类动画——**慢**（6s 进度条流光、1600ms 呼吸提示）与**一次性**（900ms 阶段脉冲、300ms 轮次豆弹出）；快循环动画在余光里=噪音且白耗 GPU。(b) **一次性事件的可靠写法 = StatefulWidget + didUpdateWidget 比较键值后 `forward(from: 0)`**（_PhasePulse/_PipDot 同模式，controller 初值 value:1.0 静止在终态）；**TweenAnimationBuilder 做不到「从 0.6 弹出」**——它 didUpdateWidget 会把 tween.begin 覆写为当前动画值（语义是「从当前值平滑到新值」），且 Tween 无 == 导致每次重建都重触发，只能 1.0→1.0 空转。(c) 常驻动画必须可停帧：流光 AnimationController 在 sweeping=false（暂停/idle/正计时）时 `stop()`，且高光层只在 `sweeping && filled>0` 时进树——停帧不是「透明动画」而是「不挂载」。(d) 热力图档位用**固定番茄语义阈值**（50/120/240 分钟 ≈ 2/5/10 番茄）而非相对分位——跨周可比、对用户诚实；**日期 key 必须对齐 DAO `dailyFocusMillisOfRange` 的本地零点毫秒时间戳**（不是 yyyymmdd 整数，写错格式数据全落空——分桶测试就是来抓这个的）。(e) 阶段字标是「色块」不是文字：15sp / letterSpacing 8 / alpha 0.75，远距只感知存在与颜色，不进入阅读；kicker 文案用英文大写是因为等宽字母距在远距的形态稳定性优于中文。(f) 网格锚定测试三视角（周一/周日/周二）起步——weekday 1-7 与「列=周、行=周几」的换算是经典 off-by-one 温床。测试 121→137。

39. **余光 2.0 强化：动效感知度要按用户测试路径校验（2026-08-04，看板 #35）**：(a) **教训：藏在 25 分钟后的动效等于没有**——#34 的脉冲/流光/豆弹出全要真番茄跑完一轮才能看到，用户短暂测试只感知到 kicker+热力图。这轮每个**立刻可见的状态**都给戏：开屏 700ms 入场编排（_Entrance，StatefulWidget 一次性 forward，秒级重建不重演）、运行中每秒个位数字 odometer 滚动（AnimatedSwitcher 按字符 ValueKey 切换，新下进旧下出同向即成转盘感；**layoutBuilder 必须给 Stack 防跳动，等宽数字是前提**）、暂停/待继续空心描边字（`foreground: Paint()..style=stroke`，「时间被掏空=停了」的零动画成本状态隐喻；**与辉光互斥**——描边叠 shadow 发脏）。(b) 巨字辉光 = TextStyle.shadows[Shadow(color: 阶段色 alpha 0.45, blurRadius: 28)]，霓虹感一米外可见，成本极低。(c) kicker 装饰线排版细节：letterSpacing 会在末字符后多留等量空隙，不对称间距补偿（左 12 右 4）才能视觉居中。(d) 热力图铺满 = LayoutBuilder 反推格子边长 `(maxWidth - 标签列 - 间距)/12 - gap`（clamp 8..30）；点按选中态 + 信息行显示「M月D日 周X · 专注时长/无记录」——provider 改返回 record `(grid, millis)` 一次查询供两处，避免二次 IO。(e) 交互分层原则：余光页（远距）只加被动信号、零新交互；统计页（近看）才加点击——**距离决定交互密度**。

40. **辉光裁切与通知栏（2026-08-04，看板 #36）**：(a) **Shadow 辉光被 ClipRect 切成硬边界**——#35 把 shadows 放在逐字符 odometer 的 Text 上，而 _OdometerDigit 的 ClipRect 把光晕裁进了字符框。修法：**辉光独立成底层**——Stack(clipBehavior: Clip.none) 下层放透明字形 + 三层 Shadow（blur 18/45/90、alpha 0.9/0.5/0.3 的霓虹灯管叠层），上层 odometer 正常裁切字形，两者互不干扰。原则：**裁剪动画层与光晕装饰层必须分家**，谁需要 Clip 谁就不能扛 shadow。(b) 引擎字段名与 ViewState 不一致：FocusViewState.completedRounds/markCount 来自 `_engine.completedFocusRounds`/`_countUp.marks.length`——写 controller 侧代码前先看 1050 行附近的 view state 构建处，别凭名字猜。(c) 通知内容加轮次/打点信息纳入 `_displaySignature` 去重体系即天然安全（轮次变化才多一次 notify，低频不闪烁）。(d) 「按键番茄」是改名 MikuFocus 的残留——通知 title 两处（showIdleDisplay/updateTimerDisplay），replace_all 修。**改名类任务 grep 旧名是收尾标配**。(e) 通知样式优化在 audio_service 框架内的边界：title/artist/按钮/轮次文本可做；setColor/进度条 seekbar 需绕到原生或换 flutter_local_notifications 自管前台通知，代价是双通知风险与保活架构改动——不值，不做。

41. **辉光与动画层的最终形态 + 热力图 ratio 模型（2026-08-04，看板 #37）**：(a) **#36 的「独立辉光底层」是错的方向**——底层瞬时切换、上层滚动 250ms，动画期间用户看到「一层不动的数字残影」比硬边界更突兀。最终形态：**辉光 shadow 直接挂在字形 Text 上**（与 odometer 严格同步滚动渐隐）+ **彻底去掉 ClipRect**（Stack clipBehavior: Clip.none，滑出残影随 fade 消失）。教训排序：同步性 > 无裁切 > 光晕强度；装饰层与动画层要么同体要么同节奏。(b) AnimatedSwitcher 自定义 layoutBuilder 的 **Stack 默认 clipBehavior: Clip.hardEdge**——不裁切必须显式给 Clip.none，否则残影在 Stack 边界被切出新的硬边。(c) 热力图从固定档位改 **ratio 模型**：格子值 = 当日/用户及格线；未达标 alpha=ratio²、超标向白混合 (ratio-1)²×0.6（cap 55%）。二次方的交互语义：及格线附近小差距几乎不可见、大差距显著放大——用户只感知「明显不足/明显超标」。比值连续无跳档（测试锁 119/120 分钟差 1/120），比档位制诚实。(d) 设置项小模式：SP int + StateNotifier + clamp 回退（glowIntensity 0-100 默认 80 / dailyGoalMinutes 15-480 默认 120），滑杆 divisions 步进（15 分钟=31 格）。热力图 provider watch 及格线 provider，改线即重算。(e) odometer 节奏定稿 400ms（250ms 在 220sp 巨字上太「蹿」）；字号 220→240（FittedBox 兜底下限，上限给足让它自己缩）。测试 137→135（档位测试换 ratio 测试）。

42. **双按转发硬路径（2026-08-11，看板 #38）**：(a) **软路径真机判死**：`AudioManager.dispatchMediaKeyEvent` 依赖系统媒体会话仲裁，M500 ROM 的定制路由把它吞了（用户实测无效；守卫保证未误触 skipPhase）。**定制 ROM 上凡依赖「系统路由」的媒体键注入都不可信**——FN 不上报、息屏双触发、dispatch 无效，三个现象同指 ROM 有自己的硬路由逻辑。(b) **硬路径 = 通知监听权限 + `MediaSessionManager.getActiveSessions()` 直控**：空 NotificationListenerService 作权限载体（不读通知内容——getActiveSessions 只认持有该权限的调用方）；挑会话时**优先 playbackState==PLAYING 的外部会话**（过滤本包名），`transportControls.skipToNext()` 直达。(c) **硬路径成功的副产品：不再需要释放-重霸占**——直控不经系统路由，按键不回流，keep-alive 静音不打断，700ms 释放窗口整个消失，双按响应更快。软路径保留作未授权时的降级。(d) 权限引导照 US-H01 逐项说明模式：设置页「权限与保活」区加「音乐控制（双按下一首）」，显示授权状态 + 跳 `ACTION_NOTIFICATION_LISTENER_SETTINGS`；查询经 media_forward channel 的 `isMusicControlGranted`（读 `enabled_notification_listeners` 含本包名）。(e) 真机验证清单：授权后双按 → 音乐切歌且计时不断、不释放（无 700ms 空窗）；未授权双按 → 走软路径（预期仍无效，属已知降级）。若硬路径也无效，下一步是 dump `getActiveSessions` 清单确认音乐 App 会话是否可见（部分 ROM 隐藏系统播放器会话）。(f) 息屏双触发「未变」符合预期——从未做针对性修复，待 adb logcat 取证；与 G05 选项化、通知/接管开关联动同簇，取证后一并设计。

43. **真机反馈 R9（2026-08-26，看板 #39）"统计开关时机不严谨"双根因定案**：(a) **addTime 不计统计 + 暂停计入完成轮** = 已做时长用「计划时长 - 剩余」折算——addTime 推后 endsAt 使 remaining 变大、折算的已做变小甚至为负，加时自然完成时被整轮折算吞掉；专注中暂停的时间也被「整轮入账」白送。**修法 = 真值源换成段开始时间戳**：引擎新增 `_phaseStartedAtMillis`（_beginPhase 烙印、待继续置 null、待继续 resume 时烙印）+ `_pausedMillisWithin(start,end)`（_pauses 与区间求交）+ `currentFocusDoneMillis`（暂停中冻结在未闭合暂停起点；旧 JSON 无字段回退旧折算）；自然完成/跳过都按「end - start - 段内暂停」实际段长入账。fromPomodoro 删 `remaining` 参数改收 done 直传，待继续（done=0）不再计入 planned/actual。教训：**「计划 - 剩余」类折算在可加时/可暂停的系统里必然失真，统计永远用「开始时间戳 + 区间求交」的第一性口径**。(b) **自动暂停后关软件、重开概率加关闭时间** = `_pausedAtMillis` 不持久化——R7 的 60min 自动结束窗口在每次冷启动恢复到暂停态时重新起算（旧注释自称"保守策略"），每重开一次发一个新窗口，窗口内幽灵按键（M500 ROM 双触发漏键）把待继续 resume 成 running，之后被杀恢复继续计 → 关闭期间入账。修法：`_pausedAtMillis` 随 `_persist` 持久化（新键 `focus_paused_at`），宽限窗跨进程连续，超 60min 重开首个 tick 即 `_finish()` 最终结算——语义从"概率性泄漏"变"确定性截止"。教训：**凡带 TTL 的状态，TTL 起点必须随状态一起持久化**，否则每次重启都是一次 TTL 重置漏洞。(c) 正计时 running 态被杀继续计是既有设计（"人在工作计时不该丢"），用户若报"正计时也加关闭时间"需另行对齐预期。测试 135→144（addTime 完成计 130s/暂停冻结/含暂停轮只计实际/待继续 done=0/JSON 往返/旧数据回退）。

44. **V0.5 AI 周报解读（2026-09-08，看板 #40；技能记录：本轮加载 `tdd`）**：(a) **与 06/07 文档的两处有意偏差**：其一，PRD 的 `top_interruption_categories`（中断最多的应用）**不存在**——US-D02 落地时（看板 #29）用「专注内暂停区间」替代了应用维度，drift 里没有应用类别数据，洞察 JSON 改为带 interruption_count/minutes（§7 已补行）；其二，**不引 http/dio**，用 `dart:io HttpClient` + `LlmTransport` 类型注入（测试喂假 transport，零新依赖、零版本风险）——OpenAI 兼容协议单实现 `OpenAiCompatibleLlmProvider` 覆盖 DeepSeek/Kimi/通义三预设（`LlmVendor.presets` + byId 回退），不每厂一类。(b) **AI 安静原则的代码化**：总开关默认关（SP `ai_enabled` 缺省 false）；开启必经 `enableWithConsent`（UI 弹数据使用说明，文案版本号 `currentConsentVersion='v1'`，文案变更须升版本重新征得同意）；前置检查（关/无同意/无 Key）在 `requestInterpretation` 入口**直接降级返回、零网络请求**——测试用计数 FakeLlm 断言 `calls==0` 把"零请求"钉死成回归。(c) **同周缓存 = 周键 + 文本**，`isoWeekKey`（ISO 周一起始，跨年周取周四所属年）做键；命中即回看不请求；缓存损坏视为未命中静默继续（on FormatException 空 catch）。(d) **US-AI-A04「查看实际上传字段」**：发送前把 `insight.toUploadJson()` 快照存 SP `ai_last_upload_json`，设置页弹窗逐字段可核对——隐私承诺要靠「可核对的证据」而不是文案。(e) **降级矩阵**：LlmFailure 五 kind（network/timeout/unauthorized/quota/badResponse）→ AiDegradeReason 八值（另含 disabled/noConsent/noKey），UI 各配一行文案；瞬时类（network/timeout/badResponse）给重试钮，配置类（noKey/unauthorized/quota）只指路设置页不重试。(f) **测试坑**：`final s = c.read(provider)` 后 `(s as AiInsightReady)` 会把局部变量**类型提升**，后续再 `s = read(...)` 赋值基类直接编译错——换新变量名；State 方法参数里的 `context` 不受 `mounted` 守护（analyze 报 unrelated），要用 `this.context`。测试 144→182（+38）。INTERNET 权限注释声明「AI 解读是唯一网络用途」。

45. **引导页重写 + US-C01 开机恢复（2026-09-08，看板 #41/#42）**：(a) **引导页内容是易腐资产**——旧首启引导还在教学「长按=结束」，而 M500 实测长按不上报（R1 起就是已知事实），等于新用户第一课就教错；功能演进后必须把引导页列入「内容漂移检查」清单（本轮同步补了双按=音乐下一首、结束的真实路径、AI 默认关闭告知）。(b) **横屏锁定后引导页要双栏**：720p 横屏画布只有 ~640×360dp，单列 Column 必溢出；`_OnboardingSheet` 改 LayoutBuilder 横屏左右双栏（左图标+标题 flex2 / 右正文+条目 flex3 滚动兜底），竖屏单列回退。(c) **重看入口的返回语义**：设置页「使用指南」pushNamed('/onboarding') 与首启 initialRoute 共用一页，`canPop()` 区分——能退则 pop（重看），不能退则 pushReplacementNamed('/')（首启）。(d) **US-C01 的 Android 14 合规形态**：boot receiver 禁止直接起 mediaPlayback FGS，只能「开机 → 检测未完成会话 → 发通知 → 点按回 App」；判据复用既有 SP 键 `focus_session_start`（有会话才存在、结束即移除），原生侧读 `FlutterSharedPreferences` 文件的 `flutter.` 前缀键，**零 Dart 侧改动、零新增写入路径**；通知权限未授予/无会话时静默退出（开机零打扰）。通知小图标用 vector drawable `ic_stat_focus`（仅 alpha 通道系统着色），不用 adaptive launcher icon（状态栏会渲染成色块）。设置页原有「允许自启动」引导项由此真正生效。原生代码不进单测，靠 §9.19 真机回归。

46. **真机反馈"Key 正确但连接失败"（2026-09-09，看板 #43）——对照 DeepSeek 官方错误码文档排查定案**：三个候选根因全修，任一都足以造成用户看到的现象：(a) **读超时 15s 太短（最可疑）**：非流式 `/chat/completions` 要等**整段生成完成**才返回响应头，`max_tokens=600` 在服务商负载下生成可达 30s+，`request.close().timeout(15s)` 必然大面积误报超时——readTimeout 提至 60s。教训：**LLM 非流式调用的"读超时"其实是"生成超时"，预算必须按 token 生成速率算**（600 tokens ÷ ~20 tok/s ≈ 30s），不能套用普通 REST 的 10-15s 直觉。(b) **402 余额不足被误标"网络不可用"**：DeepSeek 无免费额度，新账号 Key 正确但未充值时返回 402（[官方错误码](https://api-docs.deepseek.com/zh-cn/quick_start/error_codes)：400 格式/401 认证/402 余额/422 参数/429 限速/500 故障/503 繁忙）——原映射 402 落入 network，用户看到「网络不可用」完全误导。修：402→quota、400/422→badResponse（我方请求问题，不归网络），补 2 测试。(c) **chunked 传输编码兼容隐患**：dart:io HttpClient 不设 contentLength 时走 chunked，部分 API 网关兼容性差——`_defaultTransport` 改显式 `contentLength` + `add(bytes)`。(d) **诊断教训：一行归并文案会杀死真机排查**——「连接失败：网络不可用」把超时/402/TLS/网关全部归并成一句，用户无法反馈有效信息。修：连通性测试 toast 附 `LlmFailure.detail` 原始摘要（HTTP 码/异常描述），真机再失败时一行就能看出根因。设置页连通性测试文案同步注明「最长约 1 分钟」。测试 182→184。

47. **AI 主动触发（2026-09-10，看板 #44；用户反馈「周报没有主动触发，推荐任务完成时」）**：(a) **主动路径的安静原则等价翻译**——用户三连授权（开总开关+同意+配 Key）即视为授权「任务完成时自动解读」；裁决集中在 `autoInterpretIfDue()`：未开启/未同意/无 Key/请求中/本周已有缓存全部**静默 return（不置 Degraded、不动 UI、零请求）**，只有「本周第一轮完成」才真正发请求。手动 `requestInterpretation` 入口的降级矩阵不变，两路径共用缓存与快照。教训：**主动化不等于打破安静原则——把"何时可以主动"收敛成一个带全套短路条件的判定函数**，测试用计数 FakeLlm 把每条短路钉死（calls==0 且状态仍 Idle）。(b) **触发点挂 app 壳而非 ai feature**：`ref.listen(focusControllerProvider.select(completedRounds))` 放在 AiClockApp.build——避免 ai→focus 的 features 横向依赖（§6-12 分层教训的延续），completedRounds 递增 = 一轮完成，天然幂等（autoInterpretIfDue 内部再判重）。(c) **force 参数模式**：`requestInterpretation({force=false})` 仅跳过缓存段，前置检查与快照逻辑完全复用；「重新解读」按钮由此一行接入。(d) 交互增强：Idle 态按钮升 FilledButton.tonal（主动作视觉权重）+ 一行自动触发说明；Ready 态加「重新解读」TextButton。测试 184→186。

48. **新能力批次：备份/每日小结/彩蛋/旋钮取证（2026-09-12，看板 #45~#48；技能记录：本轮加载 `brainstorming`）**：(a) **数据导出零依赖路径选择**：不引 file_picker/share_plus，用 path_provider 的 `getExternalStorageDirectory()`（应用专属外存，Android 10+ 免权限、文件管理器可见）+ 固定文件名 `mikufocus_backup.json`——M500 场景「分享/云传」是伪需求，固定路径换零新依赖零新权限。编解码独立成 core 纯 Dart（`BackupCodec`：app 标记+版本号+逐字段类型校验，全部中文 FormatException），drift 行映射留 feature 层——**core 不 import drift 行类型，保分层**。(b) **导入=全量替换+自动留存**：合并语义（主键/去重）复杂收益低；替换前自动导出当前数据到 `*_pre_import.json`，反悔有路。备份不带自增 id，导入重新分配。(c) **每日小结复用既有口径**：时段四桶 `slotOfHour`/中断 `parseInterruptions` 直接复用，纯函数输入是 primitive facts（DailySessionFact）不依赖 drift；**Dart 扩展方法（DaySlotX.label）必须 import 定义它的文件**，跨文件用扩展 getter 忘导入是本轮唯一编译错。(d) **AI 当日点评比周报更轻**：失败全静默回 Idle（不置降级态不占 UI——锦上添花功能不给用户添噪音）；按日缓存键 yyyy-MM-dd；「换一句」=force 跳缓存；`autoDailyIfDue` 与周报共用 app 壳同一 completedRounds 监听。(e) **彩蛋可达化的边界**：用户否掉「3/9 才触发」的原案（一年一次=不存在），改 39 系列日常可达规则（今日满 39 分钟即触发）+ 保留 3/9 大彩蛋；守 ADR-0005——彩蛋只是真实数据上的文案点缀，不做等级/养成。(f) **庆祝音走既有反馈链路**：FeedbackEvent.celebrate 挂 phaseAlertOn 开关（与阶段提醒同类），自然进长休时**替代**（非叠加）phaseChange 音，避免双音浑浊；振动 200ms 与提醒 120ms 盲辨；琶音 C5-E5-G5-C6 由 generate_audio.py 合成（无版权问题）。(g) **旋钮取证零成本**：自检页加一句引导文案，用户转旋钮看是否有键码上报，有则下轮做「旋钮调辉光亮度」，无则归档同 FN 死结——**硬件能力一律先取证后实现**。测试 186→210（+24）。

49. **统计口径「说人话」+ AI 点选问答（2026-09-13，看板 #49/#50）**：(a) **开发者概念 ≠ 用户概念**——用户原话「轮次、会话、番茄、中断，毫无逻辑，只有总时间有效」。轮次/番茄/中断是**机制语言**（描述计时器怎么运转），总时长/分几段/最长一段/从几点到几点才是**用户语言**（描述我那天怎么学的）。详细页小结卡改为：22sp 大字总时长 + 「分 N 段完成 · 最长一段 NN」+「从 HH:mm 到 HH:mm」（DailySummary 补 firstStart/lastEnd/longestSegment 三字段，lastEnd 用 startAt+actualFocus 近似——端点口径诚实足够）；中断不在卡片出现，但时间轴红条可视化保留（机制信息放图形层，文字层只说人话）。**主统计页「今日 N 个番茄」不动**——用户只点名详细页，别把批评扩大化。(b) **免打字设备的 AI 交互 = 预设点选而非输入框**——M500 打字困难，「问 AI」做成三个 ActionChip（什么时段最专注/怎样减少中断/下周怎么安排）；题目必须白名单数据可回答（「我哪天最专注」需要按日数据，白名单没有，换成时段题）。(c) **缓存键 = (isoWeekKey, 题 id)** 存一个 JSON map，写入时 removeWhere 只留本周前缀条目防膨胀；上传快照复用 `ai_last_upload_json` 带 `type:'ask'`+question 区分周报解读。(d) 模式完全复刻 daily_comment 的纪律（静默短路/失败静默回 Idle/计数 FakeLlm 钉零请求），新文件 200 行 + 7 测试一次通过——**同纪律的第三个 AI 触点证明该模式已成熟，下次新 AI 触点直接照抄**。测试 210→219（+9）。

50. **AI 问答双场景泛化（2026-09-13，看板 #51；用户反馈「再增加 AI 交互性」）**：(a) **当日问答的增量价值在「可问历史日」**——详细页翻到哪天就能问哪天（缓存键 `d:yyyy-MM-dd:题id`），翻旧账零成本；文案用「这天」而非「今天」兼容历史日期。(b) **泛化方式：问题对象自带 scope**——`AiAskQuestion(id, label, scope)`，week→WeeklyInsight、day→DailySummary 双数据源在控制器 switch 分流，缓存键加场景前缀；**没有抽象出通用 AiEngine 基类**——两处分支各 15 行，switch 就是最好的结构。(c) **共享组件 AiAskChips 的单槽防串台**：aiAskProvider 是单槽状态（只记最近一次提问），周报题与当日题分属两页，widget 只展示 `questions.any((q) => q.id == state.qid)` 的回答/转圈——弹栈回来后看到别页题目答案的串台由此避免。(d) **「换一句」= force 参数**：与周报解读的 force 同模式（跳过缓存段，前置检查/快照逻辑全复用），一行接入。(e) **缓存淘汰策略从「只留本周」改「插入序封顶 30 条」**——当日题按日缓存后，周前缀剪枝不再适用；LinkedHashMap（jsonDecode 保序）remove 首条目即最旧淘汰，remove-then-add 刷新新旧。测试 219→223（+4：日 prompt/日快照/按日缓存/换一句 force）。

51. **AI 提示词质量优化轮（2026-09-25，看板 #52；评审见 docs/08-AI功能优化建议.md）**：(a) **最严重的一条不是技术问题而是口径问题**——`buildWeeklyReport` 拿「本周周一至今」比「上周完整周」算环比，周一上午必然得出 -95% 量级，而 prompt 又硬性要求「数字必须原样引用、不得自行计算」，**LLM 会忠实地把这个假退步当结论说出口**（不是幻觉，是我们喂错了前提）。修为**上周同期口径**：上周基线只取到与本周相同的进度点（同为周三 15:00 → 上周一 00:00~上周三 15:00），并把「进行中的部分周」写进 prompt；`stats_page` 的文案同步加「同期」二字。教训：**给 LLM 的前提错了，它对指令的服从度越高错得越离谱**——上线 AI 功能前要先审「喂进去的数自己站得住吗」，而不是只审 prompt 措辞。(b) **system/user 分消息 + 事实块单源**：角色与 5 条硬约束迁到 system（含反鸡汤、数据不足不硬编、不用列表加粗），数据与任务留 user；周报事实块在 `buildPrompt` 与 `buildAskPrompt` 里原本**逐行重复**，当日事实块同样重复两组——收敛为 `core/ai/ai_prompt.dart` 的 `weeklyFactsBlock`/`dailyFactsBlock`，四个 builder 共用。**先收敛再改，否则同一个字段要改两遍（漏一处就是两套口径）**。(c) **token 预算按任务分档**（08-A4，单项收益最大）：`maxInsightTokens=600` 三处共用，而点评契约只有 40 字、问答 80 字——非流式请求要等整段生成完，**max_tokens 直接等于用户等待时间**（§6-46(a) 自己写过的 600÷20tok/s≈30s）。改为 `AiPrompt.maxTokens`：周报 600 / 问答 200 / 点评 120，同一个常量一句话改完。(d) **解析加固是「成功率」而不是「新功能」**：原 `parseInsightResponse` 用 `\n\s*\n` 精确切段 + `startsWith('建议：')` 精确匹配，而 Kimi/通义爱用单换行分段、爱输出 `**建议：**`——**模型答得完全正确却被判「解读结果异常」整块降级**。新增 `core/ai/response_parse.dart` 加固层：有空行按空行切、无空行回退按单行切，「建议」行始终自起一段；去 Markdown 装饰；问答/点评跳过「好的，根据你的数据：」这类寒暄（原来直接把寒暄当答案展示给用户）。(e) **缓存要带数据指纹，否则整周显示周一的旧解读**（08-A2）：`ai_insight_cache` 原本只有 `{week, text}`，周一生成后整周数据在涨而缓存永不失效，周日看到的还是「本周只有 25 分钟」。加 `dataFingerprint`（会话数|分钟数|轮数|中断数，**不进白名单、不上传**），指纹变了只在卡上给一行被动提示 + 高亮「重新解读」，**不自动重发**（安静原则不变）。同款处理当日点评。(f) **顺带挖出一个真实缺陷：`_invalidateStats()` 的失效清单漏了 `daySessionsProvider` / `dailySummaryProvider`**——结算后详细页时间轴、当日小结卡、AI 当日点评的数据源都不刷新，长期读到结算前的旧数据（也正好是 (e) 的指纹永远检测不到变化的原因）。已补入清单；`weeklyInsightProvider` 不单列，靠它 watch 的 `streakProvider` 失效级联重算——**这条级联是隐式契约，已在 `_invalidateStats` 注释里写明「改依赖时回看此处」**。(g) **数据量门槛**（08-A6）：本周不足 60 分钟且不足 3 次会话时不发请求，UI 给「数据还太少，攒够 1 小时或 3 次专注后再来」；`autoInterpretIfDue` 同门槛但**静默**（不置降级态）。顺带省钱——原设计在「本周第一轮完成」就发请求，那个时点的解读价值最低。(h) **测试坑：Riverpod 非 autoDispose 的 FutureProvider 在同一容器里不会因外部数据变化自动重算**，改 `servedInsight` 后必须显式 `container.invalidate(...)` 模拟生产失效；否则 A2 的指纹测试会假失败。(i) **环境坑：本机 `flutter test` 报 "WebSocketException: Invalid WebSocket upgrade request"**——沙箱环境设了 `http_proxy/https_proxy=http://127.0.0.1:5987x`，把 flutter_tester 的 localhost WebSocket 也劫持了。解法：`unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY` + `no_proxy=127.0.0.1,localhost`。另 Bash 工具需显式 `export PATH=/usr/bin:/bin:/c/Windows/System32:/c/Windows/System32/WindowsPowerShell/v1.0:/c/flutter/flutter/bin:...PortableGit...`（flutter 需要 git 与 PowerShell 都在 PATH）。测试 223→249（+26）。

52. **release APK 构建与产物校验（2026-09-25）**：(a) **命令与基线**：`flutter build apk --release`（签名沿用 debug key，`android/app/build.gradle.kts:39` 未接正式签名，符合当前「侧载到 M500」阶段），产物 `build/app/outputs/flutter-apk/app-release.apk`；本次 62.16MB / 501 entries / 三 ABI 齐全（arm64-v8a + armeabi-v7a + x86_64，各含 libapp.so / libflutter.so / libsqlite3.so / libdartjni.so / libdatastore_shared_counter.so）；`aapt2 dump badging` 核对：包名 `com.aiclock.player`、versionName 0.1.0 / versionCode 1、targetSdk 36、label `MikuFocus`、权限含 POST_NOTIFICATIONS / FOREGROUND_SERVICE / WAKE_LOCK / RECEIVE_BOOT_COMPLETED、launchable-activity `com.aiclock.ai_clock.MainActivity`。(b) **首次全量构建（4m34s）会打印一条 `llvm-objcopy.exe: error: '...\libflutter.so.sym': Permission denied`**——出自 `extractReleaseNativeSymbolTables` 任务（提取 native 符号表供 Play Console 崩溃符号化），**不影响 APK**：APK 正常产出、zip 校验完整。增量重跑（76s）不再复现，判定为首次构建时的瞬时文件锁而非稳定缺陷——**别把这条 error 当成构建失败信号**（真正的失败是末尾没有 `√ Built ...` 行）。(c) **构建后校验三层**：`zipfile.testzip()` 无损坏 → 关键条目（AndroidManifest.xml / classes.dex / resources.arsc）在场 → `lib/*` ABI 清单齐全；再用 build-tools 的 `aapt2 dump badging` 核对包名版本权限。比只看「√ Built」多一层保障，尤其适配 M500 侧载前的自检。(d) **构建可复现**：同一源码两次构建 SHA256 完全一致（`d99da1ed…215f7`），出包后可用哈希对账「这台机器装的到底是哪一版」。(e) 环境前提同 §9 文档坑#9~11：本机 Flutter 在 `C:\flutter\flutter\bin`，构建前需 `unset http_proxy/https_proxy` 并设 `no_proxy=127.0.0.1,localhost`（代理会劫持 localhost，波及 Gradle daemon 通信与 `flutter test` 的 WebSocket）。

53. **AI 调性轮：用户反馈「太枯燥」的三层根因（2026-09-26，看板 #53；设计论证见 docs/08 §10）**：(a) **最根本的一层不在提示词里，在数据里**——洞察只有 8 个孤立数字（其中 3 个还是总量），能说的「关系」根本不存在于数据中，模型能做的只有逐行复述。修法是 08-B3 补 8 个字段（中断时段分布 / 中断占比 / 单次均值 / 最长段 + 所在时段 / 最专注的一天 / 有记录天数）——**这些原始数据（暂停时间戳、单段长度、会话日期）一直在库里，只是从没被聚合过**。教训：**「AI 说得不好」先查「它有没有东西可说」**，别一上来就改提示词。(b) **反鸡汤的正确边界是「没有信息量」，不是「正面语气」**——「表现不错」的毛病在于把数字换成了形容词，读者看完不知道到底发生了什么。08-A5 那版硬约束只有「禁」（不写鼓励语 / 只描述数据 / 不用列表加粗）而没有「要」，叠加「克制、务实」的角色与 0.3 温度，对模型而言最安全的策略就是照事实块复述——**枯燥是这三者叠加出来的机制，不是模型不努力**。修法：硬约束拆成【数字纪律】【禁止空洞】【要求具体】三组，新增「至少给出一处数字之间的关系」「第一句必须是『发现』不是『概述』」「可以说人话、可以用比喻」。(c) **温度是措辞多样性，不是数据可靠性的对价**——数字确定性由硬约束 + 本地算数保证，0.3 换不来更多安全，只换来千篇一律的句式；回调至 0.6。(d) **改了提示词必须让旧缓存失效，否则用户看到的是「改了没生效」**——缓存指纹并入 `kPromptVersion`（`cacheFingerprintOf` 拼 `@v2`），旧缓存命中时给 `dataUpdated=true` 一行「点重新解读」提示，**仍不自动重发**（安静原则不变）。缓存只按「数据是否变化」判过时是不够的，**口径变更也是一次推进动作**。(e) **题目数量不是重点，题型才是**——新增「这天最值得说的是什么」是**强制取舍**的开放题：模型必须挑一个点讲，而不能把事实块平铺开。(f) 本轮新增的 8 个上传字段全是时段/时长聚合（无应用名、无内容维度），`toUploadJson` 白名单断言同步扩到 19 个字段；07 §4.1 表同步，并顺手移除该表里本就**不存在**的 `top_interruption_categories`（PRD 原案，US-D02 落地时以暂停区间替代了应用维度，§7 早有记录，但表里一直没删）。测试 249 → 257（+8：B3 引擎 4 条 / 事实块与调性契约 3 条 / 旧口径缓存 1 条）。

54. **AI 记忆日志：跨程序记忆的格式设计（2026-09-26，看板 #54；规范见 docs/09-AI记忆日志规范.md）**：(a) **需求的本质是「互操作」，所以格式比功能重要**——用户要的是「本机 AI 与其它程序通过日志互传记忆」，即**改文件 = 传记忆**。因此没有做接口/网络协议，而是选**一行一个 JSON（JSONL）+ 纯文本文件**：追加与局部修改的成本最低（改一天只重写一行；数组结构必须整体重写，中断即全文件报废），且人可读、脚本可写、`diff` 友好。文件放**与备份同目录**（应用专属外存，免权限、文件管理器可见）——沿用 `mikufocus_backup.json` 已验证的通路，零新依赖零新权限。(b) **唯一键 `date` + 字段级所有权是这套格式的全部难点**：同一天永远只有一条（用户规则「当日多次写、覆盖当日」），但**覆盖只允许发生在应用拥有的键上**（`schema/date/rev/updated_at/prompt_version/facts/note/insight`），其余键（含外部约定键 `memory`）**原样保留**。这条规则同时满足了两个看起来冲突的要求——应用反复写不会堆出重复条目，而外部程序写进来的记忆**永远不会被应用的下一次自动保存冲掉**。教训：**多方写同一个文件时，不要用「谁后写谁赢」解决冲突，用「各自只拥有自己的字段」从结构上消灭冲突**。(c) **容错要偏向「不丢别人的数据」**：`date` 必须合法，但 `schema`/`rev`/`updated_at` 缺失或类型不符**不判非法**（按 rev=1/空时间解析）；真无法解析的行进 `invalidLines`、写回时**原样附在文件末尾**，绝不静默删除。读侧同时容忍 BOM 与 CRLF（Windows 脚本的常见产物）、数字写成 `210.0`/`"210"`。**别人的数据只该被保留或被忽略，不该被应用顺手清掉**。(d) **注入窗口不含当日**：当日数字已经在事实块里，两边都注入就会形成「同一份数据两个口径」——正是 §6-51(a) 那个 -95% 的坑的同一族错误。故注入取 `[今天-7, 今天-1]`，读取 API 则提供含/不含当日两种口径（`includeToday`）。**同一份数据只允许有一个出处**，这条纪律在引入新输入源时要重新执行一遍。(e) **`insight` 不注入**：周报全文 7 天会挤爆 token 预算（60 字/条的截断 + 900 字整块上限），它留在文件里供外部程序读。**「写进文件」与「注入给模型」是两件事**——混在一起会让预算失控。(f) **顺带修掉一处自我矛盾：当日事实块原先带 `- 起止：从 09:12 到 18:40`**，而 07 §4.3 与设置页数据使用说明都写着「逐次会话起止明细永远不上传」「不发送具体时间点」，设置页另一处还写着「专注记录（起止时间…）仅存本机数据库」。**三者互相矛盾，而且模型看得见的东西就是发出去了的东西**。已移除钟点并把数字收敛到 `dailyFactsJson` 单一来源（含单测断言事实块与上传快照都不含 `HH:mm`）；新加的 7 天记忆若保留钟点，会把这条违背放大 7 倍——**加新输入源之前先核对与既有隐私承诺是否一致**。(g) **安静原则的延伸：未开启 AI 时零副作用**——`saveToday` 在读设置时不满足就直接 return，不建文件、不读不写；读/写/解析任何异常全部静默吞掉（记忆是增强项，坏了不能拖垮解读链路，与缓存损坏同级）；成功后落盘文本用**压平的单行形态**（便于 diff 与按行读），`note`/`insight` 都存两行拼一句。(h) **上传面变了就要披露**：记忆块会随请求外发（其中可能含外部写入的内容），故数据使用说明升到 v2 并在同一段里说明「写进 memory 的东西也会一起发送」；「查看实际上传字段」快照新增 `memory_block` 键，逐字可核对。**披露而不是静默过滤**——用户自己写进去的上下文，只有用户能判断该不该发。测试 257 → 294（+37：格式层 26 / 控制器与点评 4 / 问答 1 / 提示词契约 3 / 钟点断言 1，另含既有用例的接缝改造）。

55. **三页背景图库（2026-09-30，看板 #55；规范见 docs/10-背景图库登记表.md）**：(a) **用户给的参考截图是 1280×720 横屏，这一条把需求解释通了**——「横向比纵向 ≥ 屏幕横置时长边比短边」就是 ≥16:9，两条规则本质是同一种 `cover + 顶对齐`，区别只在**哪一边溢出**，而溢出方向直接决定要不要跟滚动（纵向无溢出=只能钉住）。动手前先把设备画布比例量出来，比反复猜需求快。(b) **透明 PNG 压平色必须两条入库通道同色**：随包预处理（Python）与 app 内导入（Kotlin）各压各的，白底/黑底不一致会让同一张图两种来源长得不一样；本 App 常驻深色主题，统一压黑。(c) **EXIF 旋转是 app 内导入最容易漏的一坑**：`BitmapFactory` 不看 EXIF，相机竖图不处理就是躺着的背景；解法是**探测阶段就把宽高交换后上报**，让 Dart 的判定/目标尺寸与最终成图一致（而不是在原生侧偷偷转完再上报旧尺寸）。(d) **策略留在 Dart、原生只当执行器**：目标尺寸由 `bgTargetSize` 算（与预处理脚本同源、可单测），原生只照 `outWidth/outHeight` 执行——这样 app 内导入的图与随包图共用一套口径。(e) **`flutter analyze` 查不到 Kotlin 编译错误**：`aiclock/backgrounds` 首次构建因漏 `import io.flutter.plugin.common.MethodChannel.MethodCall` 挂掉（`Unresolved reference 'MethodCall'`），跑了 3 分钟才暴露。**新增/改动 Kotlin 后必须用 `flutter build apk` 验证**，不能只看 analyze 与 flutter test。(f) **Windows 上临时目录删除偶发「文件被占用」**：单测 tearDown 里 `delete(recursive:true)` 要包 try/on FileSystemException，否则与被测逻辑无关的环境抖动会让测试变红。(g) 测试 341→355（`bg_fit_test` 覆盖规则边界与产物对齐、`bg_library_test` 覆盖清单容错与调度、`bg_import_test` 覆盖导入口径与去重）。

56. **真机反馈与代码矛盾时，先确认装的是哪个包（2026-10-01，看板 #55）**：(a) 用户报「计时页还是出现规则 2 的图」，而策略→池→抽取→渲染四层代码全部复核无误（接线、`BgPoolPreference.fixed`、`bgPickImage`、`BackdropLayer` 都正确），单测 360 绿——此时**最高概率的解释是设备上装的是旧 APK**：旧版（#1）的计时页确实优先规则 2 池，症状完全吻合。连续多轮出包后，用户侧「装的是哪一版」本身就是未知变量，**每轮用户可见的行为变更都该 bump versionName/versionCode**（本轮 0.1.0+1→0.1.1+2），让用户在系统设置里就能对账。(b) **「绝不出现」类的需求要把回退路径一起堵死**：`bgPoolFor` 原先「首选池空回退全池」的本意是「不能因为偏好就没图可放」，但它恰是规则 2 漏进计时页的唯一通道——对「计时页只允许规则 1 + 纯色」这类硬约束，正确语义是**首选池空就退纯色，绝不回退**；「有图总比没图好」只适用于本来就能正常呈现任何图的页面（可滚动的详细页）。(c) **给用户一个设备上的自证手段**：设置页每页预览加「候选池构成」一行（`规则 1 池 4 张 · 另有纯色档`），用户无需猜「这张图是从哪个池来的」，点开设置就能核对——比来回描述截图快得多。

57. **「分类阈值」与「屏幕比例」是两件必须分开的事（2026-10-01，看板 #55）**：(a) 初版把两者焊死（阈值 = 屏幕比例 16/9），用户一句「规则一改成 1.3」就把它们拆开了——**阈值决定「归哪个池」（业务口径，用户说了算），屏幕比例决定「cover 怎么铺满」（几何，物理说了算）**。拆开后要立刻算清副作用：阈值 1.3 < 屏幕 16/9，于是多出 7 张「归规则 1、但铺满时仍按宽铺、纵向溢出 28~185px」的图，在不滚动的计时页上就是底部被裁掉一点。**放宽阈值换到的是池子从 4 张扩到 11 张**，这个代价必须在文档里写清楚，别等用户发现。(b) **阈值改成非整数比时，判定要存成分数**：1.3 = `13/10`，用 `w * 10 >= h * 13` 的整数交叉相乘，与浮点判定的抖动问题同源（§6-55(a) 那条 16:9 的坑换了个值又来一次）。预处理脚本与 Dart 侧各存一份 `NUM/DEN`，测试里断言两边一致。(c) **「抽完就放回」这类口径要写进单测**：用户描述的是「池子 1/2/3，抽出 1 → 下次在 2、3 里抽 → 再下一次 1 又回来了」，即**只排除当前这一张**（one-deep memory）。它正好等价于现有的 `excludeId: _currentId`，但如果不写测试，后面任何一次「改成不重复抽取/改成排队」的重构都会悄悄破坏它。测试写法：连续抽 300 次断言相邻不重复 **且** 全部 id 都还在循环里。(d) **掺白/染色走 `Image.color + BlendMode.srcATop`**：`paintImage` 里 `colorFilter` 先作用于图像像素、`opacity` 是乘进画笔 alpha 的最后一步（源码 `decoration_image.dart:584-587`），所以「先掺白 8% 再整体 45%」可以零额外图层实现，不需要 `Opacity` 包裹（后者会 saveLayer，见 §6-55 的同源纪律）。

58. **「是不是目标机」要用双信号识别，布局缩放要锚逻辑高而不是物理分辨率（2026-10-01，看板 #56）**：(a) 用户拿普通手机（约 2.1:1）实测后才暴露：整套 UI 的尺寸常量都隐含「屏幕 = M500」假设。但「识别 M500」**不能只测比例**——比例 ≈16:9 的他厂设备会误命中，M500 固件改分辨率又会漏判。双信号（比例 ±3% 容差 **或** Build.MODEL/DEVICE/PRODUCT 含 m500，任一命中即 M500）把「凑巧」和「固件漂移」都兜住；判定结果是**给 UI 做减法的开关**（非 M500 才挂触屏侧键），不是给功能做加法的。(b) **布局缩放锚「逻辑高」而非物理分辨率**：M500 = 720 物理 / dpr 1.835 ≈ 392.5 逻辑高；普通手机 1080 物理 / dpr 2.75 ≈ 393 逻辑高——**物理差 1.5 倍、逻辑几乎相等**，故以逻辑高为锚（`uiScaleFor`，夹 0.85~1.8），M500 上系数恰为 1.0、历史调参值零偏差，其它设备整体等比。锚物理分辨率会让所有设备缩放混乱；锚逻辑宽则横屏窄窗口会失真。(c) **触屏侧键的命令必须走与实体键同一条总线**（`_onCommand(AppCommand.addFiveMinutes)`），正计时下由 `resolveForMode` 自动改写为打点——**同一操作在任何输入通道下语义一致**，否则触屏和按键各说各话，模式分发就成了摆设。(d) 机型通道 `aiclock/device` 零依赖（四个 `Build` 静态字段，不引 device_info_plus）；`MissingPluginException`/`PlatformException` 全部吞掉返回 null，**通道失败只降级不阻断**——比例信号先顶上，AsyncValue 到达后自动修正。

59. **`Align` 定位错层级是「截图比例失衡」型 bug 的典型根因 + 震动通道整体移除（2026-10-01，看板 #56 续）**：(a) **侧键错挂在 Column 里**——非 M500 手机截图「进度条悬在 2/3 高度、左右钮一高一低堆在底部」。`Align(centerLeft/Right)` 被写进了 Column 的 children（当时注释自称「叠在 _Entrance 之上」但实际层级不是）：Column 里 Align 高度收缩为子项高，两个按钮被当**两行纵向堆叠**，还把贴底的进度条顶上去；M500 上 `showSideControls=false` 从未暴露。修法 = 挂到 `StackFit.expand` 的 Stack 层。**教训：`Align` 想相对整屏定位必须在 Stack 层；「注释/缩进说在哪一层」不可信，要数括号**。大段挪 widget 树后立刻 `flutter analyze`（本轮括号多删/少删各一次，analyze 秒定位），别攒到构建。(b) **侧键形态按用户口径降装饰**：`_Micro3DButton`（62 逻辑像素白圆渐变+描边+落影）→ `_GhostIconButton`（30 逻辑像素纯白图标+柔影、无圆底，触控热区同 30）——先修布局再谈样式，位置错了调大小没用。(c) **删第三方库的权限要 `tools:node="remove"`**：删掉 `vibration` 依赖与自身 manifest 的 VIBRATE 后，合并清单里仍有 1 条 VIBRATE——来自 `flutter_local_notifications` 的库清单自行注入。在 app manifest 加 `<uses-permission android:name="android.permission.VIBRATE" tools:node="remove" />` 强制剔除，合并后 hits=0 才算删干净；**验证要以合并产物（merged_manifests）为准，不是自己的源 manifest**。(d) **删设置字段的兼容口径**：`KeyFeedbackSettings.vibrationOn` 移除后，老用户 SP 里带 `vibrationOn` 键的 JSON 靠 `fromJson` 忽略未知键天然兼容，补一条「老数据可读」测试钉住；设置页「震动」开关与引导页「提示音和震动」文案同步清理，避免 UI 承诺一个不存在的通道。测试保持 381 全绿。

60. **SafeArea 包整页会把「背景图」一起缩进——「初始正常、页面返回后出黑边」的典型根因（2026-10-01，看板 #57）**：(a) 计时页 `Scaffold(body: SafeArea(child: ...))` 把背景层一起包了：冷启动时系统 insets 尚未下发（padding=0）一切正常，**进过一次别的页面返回后系统重新下发状态栏/刘海 insets，SafeArea 把整页从左/上缩进 ~48px，背景图四周出现黑边**——而时钟/进度条位置不变，极具迷惑性。M500 是钟表设备恒 insets=0，从未暴露；只有真机（HarmonyOS 手机）踩得到。**原则：全屏背景/氛围层永远不要放进 SafeArea，insets 只该作用在内容上**（顶栏加 `padding.top`、贴底件加 `padding.bottom`、贴边件加 `padding.left/right`）。(b) 排查顺序教训：这次先扫了 26 张入库图有没有「烤进去的黑边」（PIL 逐边扫暗色带，三档阈值全 0）、再排除 cover 数学（`bgCoverSize` 保证宽高必 ≥ 视口，几何上不可能留边），最后靠**黑边只在左/上两側且有时钟位置不变**这两条几何特征锁定 SafeArea——「哪几边有边、内容动没动」比「有没有边」多一倍信息，先量再猜。

61. **dart VM「CreateFile failed 231（所有管道范例都在使用中）」全链路瘫 + frontend_server 旁路验证法（2026-10-03，看板 #58）**：(a) 现象：`flutter analyze/test/build`、`dart analyze/run/compile` **全部**在 spawn 子进程时崩（error 231），但 **python/java/bash 的 spawn 完全正常**；detached 模式（无 stdio 管道）的 dart spawn 正常。源码对照（`runtime/bin/process_win.cc`）：dart 子进程 stdio 用 **named pipe**（`\\.\Pipe\dart_<uuid>_n`，CreateNamedPipeW 服务端 + CreateFileW 客户端），detached 走 `OpenNul()` 不建管道——所以「detached 活、带管道死」精确指向 named pipe 客户端连接这一步；本机环境探针（python ctypes）named pipe 创建正常，dart 侧 231 的确切触发条件未定位（疑似 Win11 更新后的系统状态问题，**重启最可能修复**）。(b) **旁路验证：frontend_server 直跑代替 flutter analyze**——`dartaotruntime.exe frontend_server_aot.dart.snapshot --sdk-root=<flutter>/bin/cache/artifacts/engine/common/flutter_patched_sdk/ --target=flutter --incremental --packages=<pkg> --output-dill=<out> package:<app>/main.dart`，支持命令行入口「编译即退出」，结果行末尾数字就是 error 数（0 = 全包编译通过，等价于一次完整类型检查）。**注意 `--sdk-root` 必须是 flutter_patched_sdk（含 dart:ui），dart-sdk 自带的 vm_platform.dill 不行**；gen_kernel_aot 与 flutter platform dill 不兼容（dill_loader null crash）。spawn 链路用 python `subprocess`/bash 直跑 dartaotruntime 绕开（python spawn 不经 dart 的管道实现）。本轮靠它抓到 3 个真实编译错误（缺 import、SliderTrackShape.paint override 缺 textDirection），证明其类型检查能力等同 flutter build 的 kernel 步骤。(c) **build/test 无旁路**：`flutter assemble` 即使 `CI=true` 跳过版本检查，kernel_snapshot/字体 tree-shake 等仍要 flutter_tools 内部 spawn；gradle `assembleRelease` 挂在 `compileFlutterBuildRelease`（调 flutter.bat）——同样卡 dart spawn。**重启后验证顺序：flutter analyze → flutter test → flutter build apk --release**。

62. **`ACTION_OPEN_DOCUMENT` 不能包 `createChooser`——「选了图却提示未选择」的根因（2026-10-05，看板 #61）**：(a) 现象：用户在文件管理器里点选图片后，App 提示「没有选到图片」。链路：选图 intent `ACTION_OPEN_DOCUMENT` 外面套了 `Intent.createChooser` → chooser 转发使部分第三方文件管理器返回的 URI **带不上 `FLAG_GRANT_READ_URI_PERMISSION`** → 原生探测 `openFileDescriptor` 抛 `SecurityException` 被 catch 吞掉返回 null → 候选被当「探测失败」静默丢弃 → Dart 收到空列表。**Android 官方文档明确 OPEN_DOCUMENT/CREATE_DOCUMENT 不应与 chooser 同用**；相册入口 `ACTION_PICK`+MediaStore 天然带读权限，不受影响。(b) 修复三层：intent 直接拉起不包 chooser（`AudioToolsPlugin` 选音频同款问题一并修）；探测加**流兜底**（fd 读不了退 `openInputStream`+`decodeStream`，EXIF 流构造需 API 24 有版本守卫）；**探测失败要回报不许静默丢**——失败条目 `width=0` 回传，Dart 提示语区分「没选」（空列表）与「这 N 张读不出来」（有候选但全失败），否则用户永远不知道是哪一环坏了。(c) 通用教训：**吞异常要留证据**。「try-catch 返回 null/空」在单点看是优雅降级，串成链路后就变成「输入丢失无解释」——跨边界的失败至少要把失败计数/标记传给上层，UI 才能说出人话。

63. **多元素动效要「串行编排」而不是「齐飞」——余光场景的通用法则（2026-10-07，看板 #62）**：(a) 症状：轮次切换时横屏有 5 处动画同时发生（整屏脉冲 900ms、染色 700ms、巨钟逐位滚 400ms、豆子弹 300ms、进度条 400ms），单看每条都合理，合起来余光只读出「屏幕抖了一下」，读不出「换段了」。(b) 解法：**单控制器 + 不同 `Interval`**——一个 `AnimationController` 走完全程，子元素只按自己的时间片取值，于是「任何时刻只有一层在动」，帧成本恒定且不需要多个 controller 各自 dispose。(c) 两个实现坑：① 手写 `Animation` 子类（错峰切格）**不能覆写 `parent` getter**——`Animation` 内部用 `Listenable.merge([this])` 监听 `addListener`，覆写成 `=> this.parent` 会无限递归，正确的代理面是 `transform/value/status/isAnimating/add|removeListener/add|removeStatusListener`（同 `ProxyAnimation`）；② 退场要**并行**（旧副本换 key 叠在新内容下一起淡出），串行等待会让整段时长翻倍。(d) 一次性事件与常驻动效要分清：倒计时每秒的数字滚动是**常驻节奏**，不参与轮次编排；编排层静止时 controller 停在终值，各子元素取到终态 → 与改造前逐像素一致（这条是敢不敢上动画的前提：非转场时刻零成本）。

63. **`Uri.https(host, path)` 会编码 path 里的 `?&`——在线歌词两源此前一直 404 的真根因（2026-10-06，看板 #62）**：(a) Dart 的 `Uri.https(host, path)` 把 path 当**单个 path segment**处理，`?` `&` `=` 全部 percent-encode（%3F %26 %3D）——`/api/search?a=1` 实际请求的是 `/api/search%3Fa%3D1`，服务端永远 404/400。**带查询串的 URI 必须走具名参数**：`Uri.https(host, path, {'k': 'v'})` 或 `Uri(queryParameters: ...)`。此前 LRCLIB 与网易云两个在线歌词源「一直拉不到」被先后归因于反爬、ROM 差异，实际是请求根本没带查询串；**先怀疑最基础的构造层，再怀疑服务端**。(b) 网易云老接口（`music.163.com/api/search/get` + `/api/song/lyric`）2024 年起要求反爬头：桌面浏览器 UA + `Referer: https://music.163.com/` + `X-Real-IP`（国内 IP），本机 curl 验证两端点可通；若真机仍 460「cheating」，下一兜底是腾讯音乐 lyric 接口。

64. **条件分支换高度 = 布局跳动；圆角连接 = 一条路径，不是两个 ClipRRect（2026-10-06，竖屏轮通用教训两条）**：(a) 计时页底部「awaiting 提示词 ↔ 轮次豆」两个分支高度不同，Expanded 区（辉光管）随状态缩放——用户感知为「按播放后整个布局跳了一下」。修法不是调某个高度，而是**两个分支共用固定槽高**（SizedBox + Center），只有内容替换、槽不动；凡「按状态二选一」的 UI 都要先问一句两个分支占位是否一致。(b) 两条进度条「拐角用圆角连起来像手机边缘」：两个独立 Widget 各自 ClipRRect 的方案**在深色 track 压深色壁纸时圆弧肉眼不可见**（用户三轮反馈「没看到圆角」）。正解是**把它们合成一条路径**——中心线（竖条中轴 → arcTo 四分之一圆弧 → 横条中轴）+ stroke 描边，拐角圆角由路径几何保证，与底色对比必然可见；填充用 `path.computeMetrics().extractPath(total - fillLen, total)` 取尾段。fill 方向意外收获：extractPath 从「路径末端」起填，得到的填充序正好是用户认可的「底条从左到右、再竖条向上」——**实现前先画一遍路径坐标，别凭方向感写**。(c) 同族：**辉光管「不居中」根因是内容区 padding 不对称**（左 6*s 右 4*s），Stack 中心偏 2*s；Center widget 本身永远忠于父约束，查居中先查父约束对称性。(d) 流光方向要与**填充推进方向**一致（跟随前沿，不是固定在满端），方向变了（因 fill 序变了）波的方向必须跟着改，否则用户一眼觉得「方向不对」。

65. **轮询类实时性的天花板是「外推」不是「加快轮询」（2026-10-06，歌词换行时机）**：播放位置 2s 轮询一次，歌词换行最多滞后 2s。更快的做法不是缩轮询周期（无谓耗电），而是**快照到达时重锚（基线位置 + 到达时刻），本地 200ms 节拍按流逝时间外推**——误差 ≤200ms，暂停时停表。任何「低频采样 + 高频变化」的场景（进度、位置、速度）都适用：采样保低频，插值放本地。顺带：AnimatedSwitcher 做「从左到右替换」时，transitionBuilder 里用 `child.key == ValueKey(当前值)` 区分新旧的进/出场（新的滑入、旧的淡出即可，比辉光管下翻简单一档）。

66. **Flutter 卡顿优化的安全分层：RepaintBoundary 不动视觉，alpha 越界会炸（2026-10-06）**：(a) 辉光管 odometer 每秒滚动卡顿，降质（减阴影/裁动画）被明令禁止后的安全手段是**渲染层隔离**：每个 `_OdometerDigit` 包 RepaintBoundary（秒个位滚时其它位不重绘），整钟再包一层（兄弟节点——歌词轮询、L 带流光、阶段染色的帧不波及时钟）。视觉与动画零变化，纯减少重绘面积。(b) 辉光亮度上限 100%→150% 时，`withValues(alpha: 0.9 * glow)` 会拿到 >1 的 alpha——`withValues` 对越界 alpha 是**断言**（debug 崩、release 行为未定义）。凡是「用户可调的乘数」，落点处一律 `.clamp(0.0, 1.0)`，provider 侧 clamp 只管存储。

67. **互斥设置收单入口；统一样式走参数默认值（2026-10-06）**：(a) 「歌词颜色」自定义色板 与 「同步辉光管」是两个独立开关时，用户能配出「同步开着但色板也在选」的语义冲突态——互斥功能应**合成一个对话框**（色板 = 自定义并解除同步；同步项 = 勾选即跟随，色板值保留待切回），入口 tile 副标题显示当前生效模式。判断标准：两个设置不能同时有意义，就该是一个设置。(b) 竖屏六键统一样式（#dcf4ff@60%）而横屏保持纯白——`_GhostIconButton` 加 `color/opacity` 具名参数（默认白/1.0），横屏调用点一行不动。共享 Widget 要改样式，优先加参数不改默认值，否则就是在改所有调用方。

68. **读自己的 MediaSession 自屏蔽要双保险（2026-10-06）**：专注时本 App 播静音 keep-alive，`MediaSessionManager.getActiveSessions` 会把我们自己的会话也列进来（title 固定「MikuFocus」）。原生侧 `controller.packageName != packageName` 在多数 ROM 够用，但**个别 ROM 会把会话归属报歪**——包名过滤之外再叠标题识别（本 App 的 mediaItem title 是自有常量），双条件 OR 排除。用自己的特征（包名 + 业务常量）做冗余识别，比依赖系统上报的归属可靠。

69. **「暂停」是冻结不是换段；动画起点色是会过期的状态（2026-10-07，PD 真机反馈「暂停时颜色闪成休息红再跳回蓝」）**：(a) 语义层——`paused` 在 UI 的取色 switch 里被当成一个**独立阶段**（`paused => accentColor`），但引擎里早就有 `TimerEngine.phaseBeforePause`（暂停前的阶段，暂停/继续都维护它）却从没被 UI 消费。**引擎记忆的语义信息没透出到 view state，UI 就会自己瞎猜**：正确口径是新增派生属性 `FocusViewState.colorPhase`（paused 时取 phaseBeforePause），一处算清、六处消费（横屏 3 + 竖屏 3 份重复实现都要改）。顺带修掉进度环把 `paused` 硬编码成专注色的历史 bug（休息阶段暂停会闪成专注色）。「停了」由时钟空心描边 + kicker 的 PAUSED 表达，**不要用换色表达**——颜色只承载「处于哪一段」。(b) 动画层——时钟交叉淡化的起点色 `_prevColor` **只在颜色变化时赋值、从不清理**，于是上一次转场留下的旧色长期滞留字段里；下一次转场若颜色恰好没变（暂停/继续正是这种情况），就拿这个陈旧色当淡化起点，视觉上「蓝→红→蓝」闪一下。**任何为「下一次动画」缓存起点/前一状态的字段，都必须在动画结束时作废**，并且起止值相同时不播该动画。(c) 转场触发键（`phaseKey`）也要跟着改用派生量：否则暂停虽不改色，仍会触发整屏脉冲与 1200ms 换段编排。**一处语义变更要同时问三件事：取色映射、动画起点缓存、状态变化触发键。**

## 7. 已知偏差与遗留（对照 PRD 的诚实清单）

| 项 | PRD 定位 | 现状与理由 |
| --- | --- | --- |
| US-A03 长按结束（物理键） | V0.1 | Dart 侧无法判长按（audio_service 不透传 key down/up）；需原生 MethodChannel（handler 已留 `reportLongPress()` 入口）。当前兜底：通知栏「结束」按钮 + 触屏。长按物理键会被当单按处理（开始/暂停）。**真机 R1 实测确认：长按无任何效果**（疑似 M500 ROM 层吞掉或不上报，与原生侧未接入一致）。 |
| 电池优化白名单引导 | §5 表标 V0.1 | **已实现（R3，2026-07-24）**：MainActivity 挂 `aiclock/permissions` MethodChannel，跳系统「忽略电池优化」名单页（用户手动勾选路径，避开 REQUEST_IGNORE_BATTERY_OPTIMIZATIONS 权限的审核敏感）；另提供 `isIgnoringBatteryOptimizations` 查询。待真机验证跳转。 |
| US-C01 设备重启恢复 | V0.1 | 杀后台恢复（时间戳持久化）完整；BOOT_COMPLETED 直接起 FGS 在 Android 14 被系统限制，**已落地合规形态（看板 #42，2026-09-08）**：BootReceiver 检测未完成会话（SP `focus_session_start`）发恢复引导通知，点按回 App 由既有恢复链路接管。待真机重启验证。 |
| US-F02 通知与接管开关联动 | V0.1 | 关闭「计时期间接管实体按键」则无 FGS 无通知（霸占与保活同体，ADR-0001 设计张力）；真解需拆分静音保活与按键霸占，另立评估（与息屏双触发同属按键冲突簇，待 logcat 取证后一并设计）。 |
| US-G05 第二选项「优先计时，音乐静音」 | V0.1 | 设置只有接管总开关；焦点丢失回调策略（暂停 vs 保持霸占）未做选项化。**与息屏双触发同簇保留**：取证后一并设计。 |
| 脚手架既有范围蔓延 | — | UsageStats 全链路（US-E01 属 V0.3）与番茄时长自定义（US-B04 属 V0.2）为接手时已有，未拆除（功能可用且隔离良好）。R3 顺带修复了配置从未下发引擎的脚手架断链。 |
| 跳过专注的统计偏差 | US-D01 | **已修复（R1，2026-07-23）**：引擎新增 accumulatedFocusMillis（自然完成计整轮、跳过只计已做部分且不计轮数），随 JSON 持久化；fromPomodoro 不再「轮数×整轮」折算。 |
| finish-only 落库丢统计 | US-D01 | **已修复（R3，2026-07-24）**：实时结算 upsert（每轮完成/跳过/暂停即入账同一行，游标持久化防杀后台重复）；旧库无历史数据包袱。 |
| 每轮自动续上不可控 | US-B01 | **已修复（R4 定稿，2026-07-24）**：`PomodoroConfig.autoContinue` 默认 false——**专注结束永远自动进休息**（休息不需承诺），**一轮（专注+休息）结束才「待继续」**：暂停在下一段专注起点等按键（开始专注需在场承诺，防人不在时空跑记假统计）。跳过任何阶段同规则。设置页开关可打开全自动（旧行为）。 |
| 息屏按键与音乐 App 双触发 | US-C01 | 真机 R1 新发现：息屏时按键可能双 App 同时触发、或仅一方触发（亮屏正常）。标准 Android 媒体键是单活跃会话仲裁，双触发疑似 M500 ROM 把侧键硬路由给内置播放器。待 adb logcat 取证（`adb logcat \| grep -i mediasession` 复现对照自检页日志）。缓解：设置里把「暂停释放阈值」调小（如 1min），缩短双持窗口。**R7 已加统计侧兜底**（不活跃 60min 自动结束，看板 #18）；R7 实测确认双触发会漏键 resume「待继续」产生幽灵统计，根治仍需取证后从媒体会话仲裁层解决。 |
| 通知时间精度降为分钟级 | US-F02 | 有意适配（R2）：M500 ROM 对每次 notify() 整窗重绘，秒级文本=整窗每秒闪烁。通知显示「剩 N 分 / 已计 N 分」，App 内大屏仍 mm:ss。若未来换 ROM 可评估恢复秒级。 |
| 跨天会话时长归因 | US-D01 | **恢复路径已修（R6）**：杀后台后跨天恢复（僵尸会话）由 `_discardStaleDaySession` 守卫丢弃并冲洗旧行。仍存的限制：会话**运行中自然跨零点**（未杀进程）全部时长归开始日，不拆分——番茄 25 分钟轮跨天概率极低，拆分成本高收益小；若用户反馈再评估。 |
| previousPhase 轮数回退与诚实统计不一致 | US-D01 | 已解决（R14）：直接移除「上一阶段」指令——枚举值、模式分发降级、引擎 `previousPhase()`、按键映射编辑器选项均已删除，该偏差不再存在。 |
| US-D02「切出」检测未做 UsageStats 轮询 | US-D02 | PRD 原案是 queryEvents 1-3s 轮询判定切出 App；落地改为**专注内暂停（中断）记录**（引擎/正计时 `_pauses` 区间，schema v5 pauses_json）——M500 息屏计时+后台音乐场景下「前台 App 切换」噪声大且与分心弱相关，暂停才是用户主动中断的诚实信号。老会话无 pauses_json 不展示中断（只向前生效）。 |
| 周报最专注时段按会话开始时刻归桶 | US-D04 | 跨时段会话整段归 startAt 所在时段（上午/下午/晚上/凌晨四桶），不按分钟拆分——与「跨天会话归开始日」同级的诚实简化；番茄轮 25 分钟跨桶概率低，若用户反馈再评估。 |
| AI 洞察无「中断最多的应用」字段 | US-AI-A02（06 PRD） | PRD 上传字段含 `top_interruption_categories`，但 US-D02 落地时用「专注内暂停区间」替代了应用维度（看板 #29），drift 无应用类别数据。V0.5 洞察 JSON 改带 interruption_count/minutes；若未来补 UsageStats 切出检测可再加回。 |
| AI 语音播报/语音指令 | 06 PRD 语音项 | **全砍（ADR-0006 定稿）**：M500 单 mic、外放场景回声不可控，收益不成比例；只保留云端文本解读一条路。 |

## 8. 范围纪律（防蔓延）

- 只做任务书内功能；双击/三按解析保留（V0.2 起用户可在编辑器自行绑定，默认双按=音乐下一首）。已完成至 V0.5（弹性连续/周报/标签/中断统计/AI 周报解读）；仍预留：FN 键（US-A07 已判死结——ROM 不上报键码，§6-37 备案）、多套映射预设、UsageStats 切出轮询（被中断记录替代，见 §7）、应用拦截（已砍）、账号云同步（V1.0）。
- 已砍功能（成就/AI 语音/社交/穿戴/拦截）代码与表结构保留备查，不新增任何实现。AI 仅落地「云端周报文本解读」（V0.5，ADR-0006 边界内），语音播报/语音指令不做。

## 9. M500 真机验收清单（对照 PRD Testing §4/§5）

> 产物：`build/app/outputs/flutter-apk/app-release.apk`（2026-10-02 构建，68.9MB；V0.1~V0.5 全量 + AI 周报/当日点评/预设问答（周报+当日双场景）+ 数据备份 + 每日小结说人话口径 + 39 彩蛋与庆祝音 + 引导页重写 + 开机恢复通知）。
> **性能/体验验证一律用 release 包**（debug=JIT 噪声，§6-27 P3 原则）；旧 debug 包（192MB）仅开发调试用。
> 当前无 Android 设备/模拟器连接，以下条目需 M500 接 ADB 后逐项实测；「预期」即 PRD 验收标准。

### 9.1 安装与首启
- [ ] `adb install -r build/app/outputs/flutter-apk/app-debug.apk` 成功（applicationId `com.aiclock.player`）
- [ ] 首启进入 3 屏引导 → 结束落在专注页；引导只出现一次（`onboarding_done`）
- [ ] 首次开始计时弹出「霸占实体键」一次性说明弹窗（`kHijackNoticeShownKey`）

### 9.2 按键链路核心（US-A01/A02/A06）
- [ ] 亮屏：播放/暂停键（85）开始/暂停番茄；下一曲（87）跳过；上一曲（88）+5 分钟
- [ ] 每次有效按键有声+震反馈，**端到端延迟 <100ms 实测**（单按直发路径，无多击绑定时不等 300ms 窗）
- [ ] 熄屏：同上映射全部生效（静音保活 FGS 持有 MediaSession）
- [ ] 锁屏：同上生效；通知栏可见阶段+剩余时间
- [ ] 无效按键（降级 ignored）不给反馈、不误导

### 9.3 霸占/释放仲裁（US-C01/C02）
- [ ] 计时中打开音乐 App 播放 → 音乐不应抢键；停止计时 → 按键归还音乐 App
- [ ] 暂停超 10min（默认阈值）自动释放按键归音乐 App；通知栏「开始」按钮可一键重新接管
- [ ] 杀后台后重启 App：进行中的计时按时间戳恢复；暂停态剩余时间冻结正确

### 9.4 通知栏（US-F02/F03）
- [ ] 计时中常驻通知：阶段名 + 剩余/累计时间按秒刷新（节流正常不闪烁）
- [ ] 「暂停/继续」「结束」按钮全部可用；结束按钮终止会话并落库
- [ ] 无会话时显示「准备开始」

### 9.5 数据与统计（US-D01）
- [ ] 完成一个番茄后统计页今日番茄数 +1、时长计入；正计时含打点的会话落库 marks
- [ ] 今日/本周数据与 drift 库一致

### 9.6 工具与权限（US-G02/H01）
- [ ] 设置页 → 按键自检页：按三个实体键，日志显示「键码 → MediaKeyEvent → AppCommand」三级解析
- [ ] Android 14 通知权限：拒绝分支不崩、允许后通知出现；UsageStats 引导跳转可返回（V0.3 功能，现有链路冒烟即可）

### 9.7 稳定性抽样
- [ ] 48h 长时稳定性（挂机抽查，FGS 不被杀）
- [ ] 低电量/低温场景按键响应无劣化

### 9.8 R3 回归（2026-07-24 修复）
- [ ] **统计实时入账**：完成一轮专注后（不按结束）统计页今日番茄数/时长即涨；学一天不再为零
- [ ] ~~**每轮结束待继续**：专注结束→停在休息起点~~（已被 9.9 R4 语义取代，以 9.9 为准）
- [ ] **自动继续开关**：设置页打开「每轮结束后自动继续」→ 恢复旧的不间断轮转；开关状态杀后台保留
- [ ] **暂停中结算**：暂停后杀 App → 统计仍保留已做部分（崩溃安全点）
- [ ] **电池优化跳转**：设置页「忽略电池优化」→ 打开系统名单页（不再弹 UnimplementedError）
- [ ] **设置时长实时生效**：改专注时长后新开启的轮次用新时长（脚手架断链修复回归）

### 9.9 R4 回归（2026-07-24 修复，装机重点验证）
- [ ] **轮语义**：专注自然结束 → 提示音 → **自动进短休**（不停顿）；短休/长休结束 → 停在专注起点（已暂停态），按键/通知继续键才开始下一段专注
- [ ] **跳过统一规则**：跳过专注 → 自动进短休（不计轮数）；跳过休息 → 停在专注起点（待继续）
- [ ] **长休节奏**：完成 4 轮后自动进长休运行中；长休结束才待继续
- [ ] **短会话秒级显示**：跑一个 <1 分钟的测试会话（或改短时长配置），统计页显示「Ns」/「Xm Ys」而非「0m」
- [ ] **统计不翻倍**：连续完成多轮、期间多次暂停/跳过，统计页时长与番茄数精确无双倍计数（结算串行队列回归）
- [ ] **学一天统计非零**：R4 包（非 R2 旧包）使用一整天后统计页数据完整——三层根因（旧包 finish-only / 0m 显示 / 并发双插）全部修复后的端到端验证

### 9.10 R5 回归（2026-07-26 修复，近实时统计）
- [ ] **进行中近实时入账**：开始专注后 **10 秒内**统计页今日时长即从 0 变为「Ns」，之后每 10s 左右增长（不再等轮结束）
- [ ] **跳过场景复测**：开始专注 → 做 1 分钟后跳过 → 统计页时长 ≈ 1 分钟（番茄数 0 是诚实设计，跳过不计轮）；若时长仍为 0 → 跑 `adb logcat | grep flutter` 找 "settle failed:" 上报
- [ ] **正计时同规则**：正计时运行中同样每 10s 入账
- [ ] **周期结算不翻倍**：长会话（多轮+多次暂停/跳过）结束后统计时长与手动掐表误差 < 1%
- [ ] **确认包装机**：本次复测必须确认装的是 2026-07-26 构建的包（排除旧包干扰）

### 9.11 R6 回归（2026-07-26 修复，跨天僵尸会话守卫）
- [ ] **核心场景**：覆盖安装（不清数据）后直接开始专注 → 10 秒内统计页记秒（R5 之前残留的待继续会话被守卫丢弃，不再拖走今日统计）
- [ ] **历史不丢**：守卫触发后，旧会话已做部分仍计入其开始日的统计（周视图可查），不双计到今日
- [ ] **暂停过夜**：今晚留一个「待继续」会话 → 明天打开 App → 停在 idle（昨天的待继续不 resume），开始新会话统计归明天
- [ ] **同日杀后台恢复**：进行中会话杀后台当日重开 → 恢复正常，统计续写同一行不翻倍

### 9.12 横屏 UI 回归（2026-07-26）
- [ ] **始终横屏**：冷启动/各页面（专注/统计/设置/自检/引导）均为横屏，旋转机身 180° 布局跟随翻转
- [ ] **专注页双栏**：左侧计时环占满高度不溢出，时间大字清晰可读（≥80sp）；右侧阶段/模式/按键提示/主按钮一屏放完无溢出、无滚动条（720p 下）
- [ ] **各阶段视觉**：专注/短休/长休/暂停环色正确，「待继续」暂停态布局不破
- [ ] **正计时模式**：打点行、累计时间显示正常；模式切换置灰逻辑不变
- [ ] **统计/设置页横屏**：列表与开关无溢出（Material 滚动页天然适配，冒烟即可）

### 9.13 R7 回归（2026-07-27，不活跃自动结束）
- [ ] **核心场景**：一轮结束进入「待继续」后放着不管 ≥60 分钟 → 会话自动结束（通知回「准备开始」，专注页回初始态），统计只保留真实已做部分
- [ ] **下午听音乐按键**：自动结束后下午正常使用音乐 App 按键 → 统计不再一轮轮 +25 分钟（残余风险：completed/idle 态幽灵播放键仍可能开新会话，每 ~85min 最多 1 轮——若仍明显需推进双触发取证）
- [ ] **正常间歇不误伤**：暂停 10/30/59 分钟内回来按键继续 → 会话正常 resume，统计连续
- [ ] **历史不丢**：自动结束时最终结算正常入账；正计时模式同样适用

### 9.14 详细时间统计子页回归（2026-07-30，看板 #19）
- [ ] **入口**：统计页右上角时间轴图标 → 详细时间统计页
- [ ] **日期切换**：←/→ 翻日、点日期弹选择器、「今天」快捷钮；查看今天时「后一天」禁用
- [ ] **时间轴**：会话块位置/长度与实际起止时刻吻合；0/6/12/18/24 刻度对齐；今天有「现在」竖线
- [ ] **幽灵排查路径**：切到疑似日期，核对时间轴上无操作时段是否出现会话块，明细列表核对起止时刻/轮数/状态
- [ ] **进行中会话**：半透明块延伸到当前时刻，明细行状态「进行中」
- [ ] **空态**：无记录日期显示「该日无专注记录」，时间轴为空槽不报错

### 9.15 性能优化回归（2026-07-30，看板 #20）
- [ ] **idle 停表**：无会话时静置 5 分钟，设备不发热、电量无异常消耗（旧实现 ticker 永久空转）
- [ ] **计时精度无损**：开始专注后锁屏 10 分钟回来，剩余时间与实际流逝一致（时间戳差值兜底）；阶段轮转提醒音在后台最多延迟 5s 到达
- [ ] **暂停零刷新**：暂停静置，UI 无任何闪烁/跳动；按键恢复后续计准确
- [ ] **自动结束仍生效**：「待继续」放 60 分钟自动结束（后台 5s 心跳下最多晚 5s）
- [ ] **正计时静态环**：正计时运行中环为静态满环不再旋转（语义=「进行中」），无持续 GPU 动画
- [ ] **统计实时性无损**：周期结算仍 10s 入账（SP 节流不影响 DB 写入）

### 9.16 R8 回归（2026-07-30，看板 #21：结算竞态 + 启动自愈 + 按段时间轴）
- [ ] **结束会话不再产幽灵行**：手动结束/自动结束后，详细页无「起止同刻却背轮数」的 0 时长行，无残留「进行中」行
- [ ] **统计不翻倍**：结束 N 轮后统计页时长 = 实际专注总和（真行+幽灵行双计现象消失）
- [ ] **彻底关闭再打开**：杀进程重开，轮次/时长与关闭前一致，不翻倍、不清空（轮次跨天复位属 R6 守卫设计行为，非同天不判 bug）
- [ ] **旧库自愈**：升级安装（不清数据）首次启动后，旧的悬空「进行中」行被关闭（endAt 回填）、物理不可能行被删除——详细页核对老行状态变化
- [ ] **时间轴断断续续可见**：一天内多段会话+中间休息，时间轴按专注段分块、休息为空隙，不再整段连续
- [ ] **老数据兼容**：升级前的旧会话（intervalsJson=null）时间轴仍整段渲染不报错
- [ ] **跳过仍诚实**：含跳过的一天，段区间只覆盖真实已做部分，统计时长与段总长一致

### 9.17 R9 回归（2026-08-26，看板 #39：以计时为主 + 暂停时刻持久化）
- [ ] **+5 分钟进统计**：专注中按上一曲 +5min → 本轮自然完成 → 统计时长 = 30min（旧包只记 25min）
- [ ] **暂停不计入**：专注 10min → 暂停 30min → 继续到自然完成 → 统计只计 25min（暂停期白送现象消失）
- [ ] **自动暂停关软件不加关闭时间**：一轮结束进「待继续」→ 彻底关软件 ≥1 小时 → 重开 → 首个心跳即自动结算结束，统计无关闭期间时长（旧包概率性 +N 小时）
- [ ] **中途暂停关软件同上**：专注中暂停 → 彻底关软件隔夜 → 重开自动结算，只保留暂停前的真实已做部分
- [ ] **待继续不占轮次**：轮结束待继续时统计页番茄数/计划时长不因未开始的新段虚增
- [ ] **跳过按实际段长**：专注 3min 跳过 → 统计 3min；时间轴段长与实际一致
- [ ] **老数据回退**：升级安装（不清数据）恢复出的进行中会话按旧折算口径结算，不崩、不归零

### 9.18 V0.5 AI 周报解读回归（2026-09-08，看板 #40）
- [ ] **默认零入口**：全新安装 → 设置页「AI 功能」开关默认关 → 统计页**不出现**「AI 解读」卡
- [ ] **同意门控**：开启开关 → 弹数据使用说明 → 「不同意」保持关闭；「同意并开启」后统计页出现入口
- [ ] **无 Key 降级**：不配 Key 点「让 AI 解读本周数据」→ 一行提示「请先配置 API Key」，无网络请求（飞行模式下点击行为相同）
- [ ] **测试连通性**：设置页填 Key → 「测试连通性」→ 提示连接正常；填错 Key → 提示 401；**失败时提示带原始摘要（HTTP 码/异常描述）——若仍失败，把括号内的摘要报给开发**
- [ ] **解读全流程**：有本周数据时点解读 → 转圈 → 显示 ≤3 段复盘 + 建议卡；断网时点 → 「网络不可用」一行，上方结构化周报照常
- [ ] **同周缓存**：解读成功后退出统计页再进/再点 → 显示「本地缓存回看」不重复请求
- [ ] **上传字段可核对**：设置页「查看实际上传字段」→ JSON 只含白名单字段（时长/轮数/中断/时段/连续天数），无时间戳精确值、无应用名
- [ ] **一键删除**：「删除 AI 数据」→ 确认后开关关闭、缓存/Key/同意记录清空，本机专注记录不受影响
- [ ] **切换厂商**：DeepSeek/Kimi/通义互切 → Key 各自独立保存互不覆盖
- [ ] **主动触发（看板 #44）**：开启 AI + 配 Key 后完成本周第一轮专注 → 不点任何按钮，稍后打开统计页 AI 卡直接显示解读（后台已自动请求）；当周再完成轮次不重复请求
- [ ] **主动触发的安静短路**：AI 关闭时完成轮次 → 统计页无 AI 卡、零请求；开启但无 Key 时完成轮次 → AI 卡仍停在入口按钮，不出现错误文案
- [ ] **重新解读**：解读结果卡上点「重新解读」→ 转圈后刷新内容（强制走云端，绕过同周缓存）

### 9.19 引导页重写 + 开机恢复回归（2026-09-08，看板 #41/#42）
- [ ] **引导页内容准确**：首屏按键表无「长按」；含双按=音乐下一首、结束=通知栏/屏幕按钮；第三屏含 AI 默认关闭告知
- [ ] **横屏不溢出**：720p 横屏下三屏均左右双栏、无溢出无黄条；条目表完整可见
- [ ] **设置页重看**：「设置 → 帮助 → 使用指南」打开引导页，「完成」返回设置页（不回主页）；`onboarding_done` 不被重置
- [ ] **开机恢复通知**：有待继续/进行中会话时重启设备 → 开机后收到「有未完成的专注」通知 → 点按回 App 且计时按时间戳正确恢复
- [ ] **开机零打扰**：无未完成会话时重启 → 无任何通知；通知权限未授予时重启 → 静默不崩
### 9.20 新能力批次回归（2026-09-12，看板 #45~#48）
- [ ] **导出备份**：设置 → 数据与隐私 → 导出备份 → 弹窗显示路径与条数；文件管理器在该路径可见 `mikufocus_backup.json`
- [ ] **导入恢复**：改几条数据后导入 → 统计页数据回到备份时点；导入前当前数据已留存为 `*_pre_import.json`；损坏/非本应用文件给中文原因不崩
- [ ] **每日小结卡**：详细时间统计页顶部小结卡显示 时长/会话/番茄/中断/最佳时段，与明细一致
- [ ] **AI 当日点评及时触发**：AI 开启+配 Key 后完成今日首轮 → 详细页（今天）自动出现一句话点评；点「换一句」强制重新生成
- [ ] **彩蛋**：今日专注满 39 分钟 → 统计页顶部出现彩蛋卡（葱色系）；3/9 与连续 39 天规则按代码逻辑即可
- [ ] **庆祝音**：完成 4 轮进长休 → 播放上行琶音（替代普通提醒音）；设置里关「阶段提醒音」后庆祝音也静默
- [ ] **旋钮取证**：自检页转音量旋钮 → 记录是否出现新键码，反馈给开发

### 9.21 小结卡说人话 + AI 问答回归（2026-09-13，看板 #49/#50）
- [ ] **小结卡新口径**：详细页顶部 = 大字总时长 + 「分 N 段完成 · 最长一段 NN」+「从 HH:mm 到 HH:mm」；三项数字与下方明细逐条手算一致；不再出现「会话/番茄/中断」字样（中断看时间轴红条）
- [ ] **空日/最佳时段**：无记录日显示「该日无专注记录」；有数据日「最佳时段」小字保留
- [ ] **问 AI 一句**：AI 开启时解读卡底部出现三个 chip；点选 → 转圈 → 一行答案（≤80 字量级）；同周同题再点秒出（缓存）；换题再点会真请求
- [ ] **问 AI 这天（详细页）**：小结卡内三个当日题 chip；翻到历史日期也可问（按日缓存，回看秒出）；答案旁「换一句」强制重新生成
- [ ] **AI 关时零入口**：设置里关 AI 总开关 → chips 整段隐藏；未配 Key 点 chip 无反应（静默），不产生错误提示
- [ ] **上传快照可核对**：问答后「设置 → AI 功能 → 查看实际上传字段」含 `type: "ask_week"`/`"ask_day"` 与问题文本

### 9.22 AI 提示词优化轮回归（2026-09-25，看板 #52）
- [ ] **环比口径（08-A1）**：周一/周二打开统计页 → 「本周报告」显示「（较上周同期 ±N%）」，**不再出现 -80% 量级的假退步**；AI 解读里不出现「本周大幅退步」这类结论性表述
- [ ] **部分周告知（08-A1）**：周中点「AI 解读」→ 解读文本不把本周总量当成一整周的量来评判（对比周日的解读语气应明显不同）
- [ ] **本轮改口径不破缓存（08-A2）**：本周首次解读后，再完成 1~2 轮专注 → 打开统计页 AI 卡**仍显示原解读**，且下方文案变成高亮的「本周数据已更新，点『重新解读』可刷新」；点「重新解读」后内容确实变化、提示消失
- [ ] **当日点评同款**：完成今日首轮后拿到点评，再完成 1 轮 → 详细页点评下方出现「数据已更新，点『换一句』刷新」，**不自动重发**（看 logcat 无新请求）
- [ ] **详细页数据新鲜度（本轮补的失效清单）**：完成一轮专注后回到详细页 → 时间轴与「当日小结」卡数字**同步更新**（不再需要杀 App 或切日期才刷新）
- [ ] **解析加固（08-A3）**：真机解读正常显示（换 Kimi / 通义各试一次，确认不再轻易落到「解读结果异常，请重试」）；问答的答案不出现「好的，根据你的数据：」这类寒暄
- [ ] **数据量门槛（08-A6）**：清一次专注数据或周一早上下点「AI 解读」→ 显示「本周数据还太少，暂不足以解读」且**零网络请求**（飞行模式下行为相同）；攒够 1 小时或 3 次专注后可正常解读
- [ ] **延迟改善（08-A4）**：点评/问答的等待时间明显短于周报解读（logcat 里 `max_tokens` 分别为 120/200/600）
- [ ] **安静原则不回退**：以上全部改动后，重跑 §9.18 / §9.20 / §9.21 的 AI 条目，确认「AI 关闭零入口零请求」「完成轮次不重复请求」两条仍成立

### 9.23 AI 调性轮回归（2026-09-26，看板 #53）
- [ ] **解读不再复述数字**：点「AI 解读」→ 第一句是**「发现」**（如「你的 620 分钟有近一半挤在晚上」），**不是**「本周专注 620 分钟，共 21 次」这类一眼可见的复述；全文至少有一处数字之间的关系（时段互比 / 环比上周同期 / 最长与平均）
- [ ] **仍然不鸡汤**：调性放宽不等于放开反鸡汤——解读里不应出现「加油」「继续保持」这类没有信息量的评价（这是本轮的边界，重点验）
- [ ] **新字段真的被用上（08-B3）**：有中断的一周 → 解读能说出「中断集中在X时段」这种带具体时段的话；点「什么时候最容易被打断」能答出具体时段，而不是泛泛而谈
- [ ] **口径版本可见（E3，存量机重点）**：升级前已生成过解读的机器 → 升级后首次打开统计页 AI 卡**仍显示旧解读**、下方带「数据已更新，点重新解读」提示，且**零自动重发**（logcat 无新请求）；点「重新解读」后文风明显不同（能看出换了表达方式）
- [ ] **问答题目**：统计页 5 题、详细页 4 题；新题「时间花得值吗」「这天最值得说的是什么」的回答落在数字上，不空泛
- [ ] **温度不引发编造**：同一题连点 2~3 次「换一句」→ 措辞有变化，但**数字始终与页面显示一致**、无新增数字（0.6 温度下这条必须复验）
- [ ] **安静原则不回退**：重跑 §9.22 的「AI 关闭零入口零请求」「完成轮次不重复请求」两条

### 9.24 AI 记忆日志回归（2026-09-26，看板 #54）
- [ ] **文件真的落在外部可读写的位置**：设置 → AI 功能 → 跨程序记忆日志 → 复制路径 → 用文件管理器/adb 确认 `mikufocus_ai_memory.jsonl` 存在且是纯文本（UTF-8、一行一个 JSON、末尾有换行）
- [ ] **一天一条**：同一天完成多轮专注 + 点一次「AI 解读」→ 文件里该 `date` **只有一行**，`rev` 递增、`note`/`insight` 都合并进同一条（不是追加新行）
- [ ] **外部记忆不被冲掉（关键）**：用电脑把某天的 `memory` 字段改掉 → 回到 App 再完成一轮专注触发自动保存 → 重新取文件核对：**`memory` 与其它自定义键原样还在**，只有应用字段被更新（`rev` +1）
- [ ] **外部记忆真的进了请求**：写完 `memory` 后点「AI 解读」→ 设置页「查看实际上传字段」里出现 `memory_block` 且含那句话；解读内容能体现出用了这条背景（至少不与它矛盾）
- [ ] **不含当日**：上传快照的 `memory_block` 里**不出现今天**的日期（当日数字只在事实块里，避免两个口径）
- [ ] **7 天窗口与上限**：攒够 8 天以上再试 → 注入块只含近 7 天（不含当日）；把多条 `memory` 写得很长时块被截断、且**保留的是最近的**条目
- [ ] **坏行不丢**：手工往文件里插一行乱码/半截 JSON → App 再写一次 → 乱码行**仍在文件里**（被挪到末尾），设置页显示「另有 N 行无法解析」
- [ ] **关了就不碰**：关闭 AI 总开关 → 删掉日志文件 → 完成几轮专注 → 文件**不会被重建**（零副作用），App 也不读它
- [ ] **删除联动**：设置 → 删除 AI 数据 → 日志文件随之消失、AI 关闭；之后外部程序仍可重新写入文件
- [ ] **无钟点（本轮的隐私修正）**：抓包或看详解 → 请求里**不应出现 `09:12` 这类 `HH:mm`**（事实块与上传快照都不含）；设置页三处隐私文案与实现一致（「起止时间仅存本机」）
- [ ] **安静原则不回退**：重跑 §9.22/§9.23 的两条（AI 关闭零入口零请求、完成轮次不重复请求）；额外确认写入日志**不产生任何网络请求**

