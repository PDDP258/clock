/// 设置页「背景」区（看板 #55；2026-10-05 图库操作集中到图库管理页）。
///
/// 两件事：**看得到**（三页当前背景预览）、**换得动**（每页独立手动换一张）。
/// 图库的预览/禁用/删除/添加统一在 `GalleryManagePage`。
///
/// 单独成文件的原因：设置页 1200+ 行，背景这块自带多个 provider 依赖，
/// 塞进去会让设置页彻底没法读。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/background/bg_image.dart';
import '../application/background_controller.dart';
import '../application/bg_import.dart' show bgUserLibraryProvider;
import 'gallery_manage_page.dart';
import 'page_background.dart';

/// 背景区（设置页内嵌）。
class BackgroundSettingsSection extends ConsumerWidget {
  const BackgroundSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final library = ref.watch(bgLibraryProvider);
    final user = ref.watch(bgUserLibraryProvider);

    final full = ref.watch(bgFullLibraryProvider).valueOrNull;
    // 内置张数取全量（不受禁用影响）；total 是当前实际可抽的候选数
    final bundledCount = full?.images.where((i) => i.bundled).length ?? 0;
    final total = library.valueOrNull?.length ?? 0;
    final userCount = user.valueOrNull?.length ?? 0;
    final disabledCount = ref.watch(bgDisabledIdsProvider).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------------------------------------------- 三页预览 + 换一张
        for (final page in BgPage.values) _PageRow(page: page),
        const SizedBox(height: 4),
        Text(
          '三页各自独立随机，每 5 分钟 ~ 5 小时换一次；'
          '计时页只在纯色与「高铺满·固定」图之间轮换'
          '（纯色概率更高，保住余光可读性）；'
          '详细页偏向滚动感强的竖构图（溢出越深越容易被抽中）',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const Divider(height: 24),
        // 图库的看/禁/删/加全部集中在图库管理页（2026-10-05）
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('图库管理'),
          subtitle: Text(
              '内置 $bundledCount 张 · 候选 $total 张'
              '${userCount > 0 ? ' · 我添加的 $userCount 张' : ''}'
              '${disabledCount > 0 ? ' · 已禁用 $disabledCount 张' : ''}'
              ' · 预览 / 禁用 / 删除 / 添加'),
          subtitleTextStyle:
              TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const GalleryManagePage())),
        ),
      ],
    );
  }
}

/// 一页的背景预览 + 手动换一张。
class _PageRow extends ConsumerWidget {
  const _PageRow({required this.page});

  final BgPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final spec = ref.watch(backdropProvider(page));
    final notifier = ref.read(backdropProvider(page).notifier);
    final library = ref.watch(bgLibraryProvider).valueOrNull ?? BgLibrary.empty;
    final image = spec.image;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 64,
          height: 36,
          child: image == null
              ? ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: const Center(
                      child: Icon(Icons.block_outlined, size: 16)),
                )
              : Opacity(
                  // 预览里把不透明度拉到与页面一致（跟随策略常量走），
                  // 否则缩略图会「比实际深」，误导判断
                  opacity: spec.opacity,
                  child: Image(
                    image: bgImageProvider(image),
                    fit: BoxFit.cover,
                    // 掺白也要还原，否则缩略图与页面不一致
                    color: spec.whiten > 0
                        ? Colors.white.withValues(alpha: spec.whiten)
                        : null,
                    colorBlendMode:
                        spec.whiten > 0 ? BlendMode.srcATop : null,
                    errorBuilder: (_, __, ___) =>
                        const ColoredBox(color: Colors.grey),
                  ),
                ),
        ),
      ),
      title: Text(page.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(image == null
              ? '纯色'
              : '${image.width}×${image.height} · ${image.rule.label}'),
          // 池构成一眼可验：真机上就能确认每页从哪个池抽、各占多少
          const SizedBox(height: 2),
          Text(
            _poolLabel(page, library),
            style: TextStyle(
                fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: '换一张',
        icon: const Icon(Icons.shuffle),
        onPressed: notifier.reroll,
      ),
    );
  }

  /// 该页候选池的构成与比例（设置页展示，便于真机核对）。
  static String _poolLabel(BgPage page, BgLibrary lib) {
    final policy = page.policy;
    if (policy.anyPool) return '候选：全池 ${lib.length} 张 · 均匀随机';
    final parts = <String>[
      '规则1池 ${lib.fixedPool.length} 张 ${_pct(policy.fixedProbability)}',
      '规则2池 ${lib.scrollablePool.length} 张 '
          '${_pct(policy.scrollableProbability)}',
      if (policy.solidProbability > 0)
        '纯色 ${_pct(policy.solidProbability)}',
    ];
    return '候选：${parts.join(' · ')}';
  }

  static String _pct(double v) => '${(v * 100).round()}%';
}
