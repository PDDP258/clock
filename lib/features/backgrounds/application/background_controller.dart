/// 背景调度（application 层）：三页各自独立、异步随机。
///
/// 规则（`docs/10-背景图库登记表.md` §6）：
/// - **三页互相独立**：每个页面一个 [BackdropNotifier]，各自抽各自换；
/// - **间隔在 [5 分钟, 5 小时] 内均匀随机**，换完重新抽下一次间隔；
/// - **抽完下一次抽完就放回**（只排除当前这一张）：池里有 1/2/3，抽出 1 后
///   只能在 2、3 里抽；再抽一次之后 1 立刻回到池里——不会「越抽池子越小」，
///   也不会连续两次抽到同一张（用户 2026-10-01 明确的口径）；
/// - **各页抽图比例**（2026-10-01 用户调参，分类器阈值同时改为 1.3）：
///   - 使用统计：**全池均匀**（26 张里随机，两类都可能）；
///   - 详细时间统计：**95% 规则 1 池 / 5% 规则 2 池**；
///   - 计时页：**80% 规则 1 池 / 18% 纯色 / 2% 规则 2 池**；
/// - 详细页在规则 2 池内**按纵向溢出深度加权**（溢出越深，「随滚动」的观感越强）。
///   这条只在命中那 5% 时起作用。
///
/// 生命周期用 `autoDispose`：页面关掉就停表、下次进来重新抽一张。
/// 背景是装饰，不值得为它常驻一个定时器。
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/background/bg_fit.dart';
import '../../../core/background/bg_image.dart';
import '../../../platform/files/background_import_channel.dart';
import '../../../platform/files/background_store.dart';
import '../../../platform/prefs/prefs_provider.dart';

// ------------------------------------------------------------------ 常量

/// 换背景的最短间隔（分钟）。
const int kBgMinIntervalMinutes = 5;

/// 换背景的最长间隔（分钟）= 5 小时。
const int kBgMaxIntervalMinutes = 5 * 60;

// ------------------------------------------------------------------ 模型

/// 三张需要背景的页面（各自独立随机）。
enum BgPage {
  /// 使用统计（全池均匀随机）
  stats,

  /// 详细时间统计（95% 规则 1 / 5% 规则 2）
  statsDetail,

  /// 计时/余光·横屏（80% 规则 1 / 18% 纯色 / 2% 规则 2；图片最淡且掺白）
  focus,

  /// 计时/余光·竖屏（2026-10-05 用户口径：竖屏以规则 2 池为主——
  /// 竖构图壁纸在竖屏里铺得更满；图片参数与横屏计时页一致）
  focusPortrait,

  /// 使用统计·竖屏（2026-10-06 用户口径：竖屏统计页背景**全用规则 2 池**，
  /// 竖构图在竖屏里铺得更满；按纵向溢出深度加权，与横屏详细页同款权重）
  statsPortrait,

  /// 详细时间统计·竖屏（同 statsPortrait：全用规则 2 池 + 溢出深度加权）
  statsDetailPortrait;

  /// 该页背景策略。
  BgPagePolicy get policy => switch (this) {
        BgPage.stats => const BgPagePolicy(
            opacity: kBgOpacityStats,
            anyPool: true,
          ),
        BgPage.statsDetail => const BgPagePolicy(
            opacity: kBgOpacityStats,
            fixedProbability: 0.95,
            scrollableProbability: 0.05,
            weightOf: bgScrollDepthWeight,
          ),
        BgPage.focus => const BgPagePolicy(
            opacity: kBgOpacityFocus,
            whiten: kBgFocusWhiten,
            solidProbability: 0.18,
            fixedProbability: 0.80,
            scrollableProbability: 0.02,
          ),
        BgPage.focusPortrait => const BgPagePolicy(
            opacity: kBgOpacityFocus,
            whiten: kBgFocusWhiten,
            solidProbability: 0.18,
            fixedProbability: 0.02,
            scrollableProbability: 0.80,
            weightOf: bgScrollDepthWeight,
          ),
        BgPage.statsPortrait => const BgPagePolicy(
            opacity: kBgOpacityStats,
            scrollableProbability: 1.0,
            weightOf: bgScrollDepthWeight,
          ),
        BgPage.statsDetailPortrait => const BgPagePolicy(
            opacity: kBgOpacityStats,
            scrollableProbability: 1.0,
            weightOf: bgScrollDepthWeight,
          ),
      };

  /// 中文名（设置页展示）。
  String get label => switch (this) {
        BgPage.stats => '使用统计',
        BgPage.statsDetail => '详细时间统计',
        BgPage.focus => '计时页',
        BgPage.focusPortrait => '计时页（竖屏）',
        BgPage.statsPortrait => '使用统计（竖屏）',
        BgPage.statsDetailPortrait => '详细时间统计（竖屏）',
      };
}

/// 页面背景策略。
///
/// 抽图用**绝对概率**表达：`solidProbability + fixedProbability +
/// scrollableProbability = 1.0`（[anyPool] 为真时忽略比例，直接全池均匀）。
class BgPagePolicy {
  const BgPagePolicy({
    required this.opacity,
    this.whiten = 0,
    this.solidProbability = 0,
    this.fixedProbability = 0,
    this.scrollableProbability = 0,
    this.anyPool = false,
    this.weightOf,
  });

  /// 图片不透明度
  final double opacity;

  /// 图片额外掺白的比例（0 = 不掺白）。计时页用它压住图片饱和度，
  /// 让阶段染色（一眼信号）更突出。
  final double whiten;

  /// 「纯色无图」的概率
  final double solidProbability;

  /// 从**规则 1 池**（比例 ≥ 1.3）抽的概率
  final double fixedProbability;

  /// 从**规则 2 池**（比例 < 1.3，随滚动）抽的概率
  final double scrollableProbability;

  /// true = 不看比例，直接在全池里均匀抽（使用统计页）
  final bool anyPool;

  /// 规则 2 池内的抽取权重（null = 均匀随机）；权重全为 0 时回退均匀，
  /// 不能反过来让池子抽不出图。
  final double Function(BgImage image)? weightOf;
}

/// 背景形态。
enum BackdropKind {
  /// 纯色（页面原本的底色/阶段染色）
  solid,

  /// 图片背景
  image,
}

/// 一页当前该显示什么背景。
class BackdropSpec {
  const BackdropSpec.solid()
      : kind = BackdropKind.solid,
        image = null,
        opacity = 0,
        whiten = 0;

  const BackdropSpec.image(
    this.image, {
    required this.opacity,
    this.whiten = 0,
  }) : kind = BackdropKind.image;

  final BackdropKind kind;
  final BgImage? image;
  final double opacity;

  /// 图片额外掺白的比例（见 [BgPagePolicy.whiten]）
  final double whiten;

  /// 是否真的有图画（纯色或图库为空时为 false）
  bool get hasImage => kind == BackdropKind.image && image != null;

  /// 稳定键：用于渲染层判断「换没换」（id 相同就不重建 Image）
  String get key => hasImage ? image!.id : 'solid';

  @override
  String toString() => hasImage
      ? 'BackdropSpec(image=${image!.id}, opacity=$opacity, whiten=$whiten)'
      : 'BackdropSpec(solid)';
}

// ------------------------------------------------------------------ 纯函数（可单测）

/// 规则 2 池内的抽取权重：按图片**铺满屏幕后的纵向溢出量**（像素）加权。
///
/// 溢出深度就是「随滚动」观感的强弱——溢出 1600px 的竖构图滚动时
/// 背景大幅移动，溢出 28px 的浅横构图滚到底也只挪一指宽。
/// 规则 1 的图里，比例 ≥16:9 的那部分溢出恒为 0。
double bgScrollDepthWeight(BgImage image) {
  final size = bgCoverSize(
    imageWidth: image.width.toDouble(),
    imageHeight: image.height.toDouble(),
    viewWidth: kBgScreenWidth.toDouble(),
    viewHeight: kBgScreenHeight.toDouble(),
  );
  final overflow = size.height - kBgScreenHeight;
  return overflow > 0 ? overflow : 0;
}

/// 抽一个换背景间隔：`[5min, 5h]` 闭区间均匀随机。
Duration bgRandomInterval(Random random) => Duration(
      minutes: kBgMinIntervalMinutes +
          random.nextInt(kBgMaxIntervalMinutes - kBgMinIntervalMinutes + 1),
    );

/// 在池内选一张，尽量避开 [excludeId]（池只有 1 张时只能重复）。
///
/// **这就是「抽完下一次抽完就放回」的实现**：只有 [excludeId]（当前显示的
/// 那一张）被排除，其余全部照常参与；下一次抽完，调用方把 excludeId 换成
/// 新抽到的那张，旧的立刻回到池里。池子不会越抽越小。
///
/// [weightOf] 非空时按权重抽取（权重 ∝ 出现概率）；累计权重为 0 时回退均匀。
BgImage? bgPickImage(
  List<BgImage> pool,
  Random random, {
  String? excludeId,
  double Function(BgImage image)? weightOf,
}) {
  if (pool.isEmpty) return null;
  var candidates = pool;
  if (pool.length > 1 && excludeId != null) {
    final filtered = [for (final i in pool) if (i.id != excludeId) i];
    if (filtered.isNotEmpty) candidates = filtered;
  }
  if (weightOf == null) {
    return candidates[random.nextInt(candidates.length)];
  }
  final weights = [for (final i in candidates) weightOf(i)];
  final total = weights.fold<double>(0, (a, b) => a + b);
  if (total <= 0) {
    return candidates[random.nextInt(candidates.length)];
  }
  // 轮盘赌：随机点落在哪个权重区间就抽谁
  var point = random.nextDouble() * total;
  for (var i = 0; i < candidates.length; i++) {
    point -= weights[i];
    if (point <= 0) return candidates[i];
  }
  return candidates.last;
}

/// 按策略抽一份背景：先定「纯色 / 规则 1 池 / 规则 2 池」，再在池内抽一张。
///
/// 命中池为空时换另一个池兜底（两个池都被本页接受，不算跳出约束）；
/// 两个池都空 → 纯色。
BackdropSpec bgRoll(
  BgLibrary library,
  BgPagePolicy policy,
  Random random, {
  String? excludeId,
}) {
  if (library.isEmpty) return const BackdropSpec.solid();

  // 使用统计页：全池均匀，不走比例
  if (policy.anyPool) {
    return _specOf(
        bgPickImage(library.images, random, excludeId: excludeId), policy);
  }

  // 一次掷骰子决定三种结局（概率之和 = 1）
  var point = random.nextDouble();
  if (point < policy.solidProbability) return const BackdropSpec.solid();
  point -= policy.solidProbability;

  final wantFixed = point < policy.fixedProbability;
  var pool = wantFixed ? library.fixedPool : library.scrollablePool;
  var weighted = wantFixed ? null : policy.weightOf;
  if (pool.isEmpty) {
    // 首选池空 → 换另一个池兜底
    pool = wantFixed ? library.scrollablePool : library.fixedPool;
    weighted = wantFixed ? policy.weightOf : null;
    if (pool.isEmpty) return const BackdropSpec.solid();
  }
  return _specOf(
    bgPickImage(pool, random, excludeId: excludeId, weightOf: weighted),
    policy,
  );
}

/// 抽到图就包成图片背景，抽不到就退纯色（宁可纯色，也不留一块空白）。
BackdropSpec _specOf(BgImage? picked, BgPagePolicy policy) => picked == null
    ? const BackdropSpec.solid()
    : BackdropSpec.image(picked,
        opacity: policy.opacity, whiten: policy.whiten);

// ------------------------------------------------------------------ Provider

/// 用户图库存储（测试覆盖为临时目录）。
final bgLibraryStoreProvider =
    Provider<BgLibraryStore>((ref) => BgLibraryStore());

/// 原生导入通道（测试覆盖为 fake）。
final bgImportChannelProvider =
    Provider<BgImportChannel>((ref) => const BgImportChannel());

/// 候选池 = 内置（APK 资源）+ 用户（应用专属外存），按 id 去重。
///
/// 内置清单缺失/损坏不阻塞用户图库：两者独立解析后合并。
final bgFullLibraryProvider = FutureProvider<BgLibrary>((ref) async {
  final bundled = await _loadBundledLibrary();
  final user = await ref.watch(bgLibraryStoreProvider).read();
  return BgLibrary.merge(bundled, user);
});

/// 抽图用候选池 = 全量图库 **剔除禁用图**（图库管理页维护禁用集）。
///
/// 禁用集变化时本池自动重建，三页的 backdropProvider（watch 本池）
/// 也随之重建重抽——禁用当前正显示的图会立刻换图，无需手动刷新。
final bgLibraryProvider = FutureProvider<BgLibrary>((ref) async {
  final full = await ref.watch(bgFullLibraryProvider.future);
  return bgExcludeDisabled(full, ref.watch(bgDisabledIdsProvider));
});

/// 从图库剔除禁用图（纯函数，可单测）。
BgLibrary bgExcludeDisabled(BgLibrary library, Set<String> disabled) {
  if (disabled.isEmpty) return library;
  return BgLibrary(
      [for (final i in library.images) if (!disabled.contains(i.id)) i]);
}

/// 禁用图 id 集（SharedPreferences stringList 持久化）。
final bgDisabledIdsProvider =
    StateNotifierProvider<BgDisabledIdsNotifier, Set<String>>((ref) =>
        BgDisabledIdsNotifier(ref.watch(sharedPreferencesProvider)));

class BgDisabledIdsNotifier extends StateNotifier<Set<String>> {
  BgDisabledIdsNotifier(this._prefs) : super(_load(_prefs));

  static const _kKey = 'bg_disabled_ids';
  final SharedPreferences _prefs;

  static Set<String> _load(SharedPreferences prefs) =>
      (prefs.getStringList(_kKey) ?? const <String>[]).toSet();

  Future<void> _persist() async =>
      _prefs.setStringList(_kKey, state.toList());

  /// 切换一张图的禁用状态，返回切换后是否禁用。
  Future<bool> toggle(String id) async {
    final next = Set<String>.from(state);
    final nowDisabled = !next.remove(id);
    if (nowDisabled) next.add(id);
    state = next;
    await _persist();
    return nowDisabled;
  }

  /// 删除图时同步清理禁用集（图都没了，禁用状态没有意义）。
  Future<void> discard(String id) async {
    if (!state.contains(id)) return;
    state = Set<String>.from(state)..remove(id);
    await _persist();
  }
}

/// 读内置图库清单（资产缺失/坏 JSON → 空池，不抛）。
Future<BgLibrary> _loadBundledLibrary() async {
  try {
    final raw = await rootBundle.loadString(kBgBundledManifestAsset);
    return BgLibrary.decode(
      raw,
      bundled: true,
      refOf: (id, entry) {
        final asset = entry['asset'];
        if (asset is String && asset.isNotEmpty) return asset;
        return 'assets/backgrounds/$id.webp';
      },
    );
  } catch (_) {
    return BgLibrary.empty;
  }
}

/// 某页当前背景（三页各自一个实例，独立随机）。
///
/// 池子还没加载出来时给纯色（不闪烁、不留白），加载完自动开抽。
final backdropProvider = StateNotifierProvider.autoDispose
    .family<BackdropNotifier, BackdropSpec, BgPage>((ref, page) {
  final library = ref.watch(bgLibraryProvider).valueOrNull ?? BgLibrary.empty;
  return BackdropNotifier(page: page, library: library);
});

/// 一页背景的随机调度器。
class BackdropNotifier extends StateNotifier<BackdropSpec> {
  BackdropNotifier({
    required this.page,
    required BgLibrary library,
    Random? random,
  })  : _random = random ?? Random(),
        super(const BackdropSpec.solid()) {
    _library = library;
    if (library.isEmpty) return; // 池空：保持纯色，不排定时器
    _roll();
  }

  /// 所属页面
  final BgPage page;

  final Random _random;
  late BgLibrary _library;
  Timer? _timer;

  /// 当前图 id（换图时用它避开重复；**只记住这一张**，抽完即放回）
  String? _currentId;

  /// 手动换一张（设置页「换一张」/ 调试用），并重排下一次随机间隔。
  ///
  /// 带 mounted 守卫：定时器回调与 UI 引用都可能在 dispose 之后到达，
  /// 而 `state` 在 dispose 后赋值会直接抛（state_notifier 的调试断言）。
  void reroll() {
    if (!mounted || _library.isEmpty) return;
    _roll();
  }

  /// 该页可抽的图总数（设置页展示）。
  int get poolSize => _library.length;

  void _roll() {
    if (!mounted) return;
    final spec = bgRoll(_library, page.policy, _random, excludeId: _currentId);
    // 只替换「当前这一张」：上一张在这次抽完的同时就回到了池里
    _currentId = spec.image?.id;
    state = spec;
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(bgRandomInterval(_random), () {
      if (!mounted) return;
      _roll();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
