/// 图库管理页（2026-10-05 用户需求）：进入即网格预览全部图，
/// 单图可看大图、禁用/启用，用户图可删除；顶部按钮加图（相册/文件管理器）。
///
/// 与设置页背景区的分工：设置页管「每页怎么抽」（预览/换一张/概率说明），
/// 本页管「图库里有什么」（看/禁/删/加）。禁用集变化会自动重建抽图池，
/// 三页背景随之重抽——禁用当前正在显示的图会立刻换一张。
///
/// 禁用 vs 删除的语义：
/// - **禁用**：只是从候选池剔除，文件与清单条目都在，随时可启用；
/// - **删除**：仅对「我添加的图」开放——清单去条目 + 删文件，不可恢复；
///   内置图打进 APK 删不掉，不想看到就用禁用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/background/bg_image.dart';
import '../../../platform/files/background_import_channel.dart';
import '../application/background_controller.dart';
import '../application/bg_import.dart';
import 'page_background.dart';

/// 图库管理页。
class GalleryManagePage extends ConsumerStatefulWidget {
  const GalleryManagePage({super.key});

  @override
  ConsumerState<GalleryManagePage> createState() => _GalleryManagePageState();
}

class _GalleryManagePageState extends ConsumerState<GalleryManagePage> {
  _GalleryBusy? _busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final full = ref.watch(bgFullLibraryProvider);
    final disabled = ref.watch(bgDisabledIdsProvider);
    final images = full.valueOrNull?.images ?? const <BgImage>[];
    final disabledCount = disabled.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('图库管理（${images.length}）'),
        actions: [
          IconButton(
            tooltip: '添加图片',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _busy == null ? _importFromPicker : null,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy != null) const LinearProgressIndicator(minHeight: 2),
          if (disabledCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '已禁用 $disabledCount 张：不参与随机抽取，点图片可重新启用',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          Expanded(
            child: images.isEmpty
                ? Center(
                    child: Text('图库是空的，点右上角添加图片',
                        style: TextStyle(color: scheme.onSurfaceVariant)))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 16 / 11,
                    ),
                    itemCount: images.length,
                    itemBuilder: (context, index) {
                      final image = images[index];
                      final isDisabled = disabled.contains(image.id);
                      return _GalleryTile(
                        image: image,
                        isDisabled: isDisabled,
                        onTap: () => _preview(image),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 加图

  /// 弹来源选择：相册（推荐）或文件管理器。相册权限稳定、挑图顺手；
  /// 文件管理器能进任意目录，相册找不到时用。
  Future<void> _importFromPicker() async {
    final source = await showModalBottomSheet<BgPickSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('添加图片',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              subtitle: const Text('推荐，挑图更方便'),
              trailing: const Icon(Icons.star_outline, size: 18),
              onTap: () => Navigator.pop(context, BgPickSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('从文件管理器选择'),
              subtitle: const Text('相册里找不到时用'),
              onTap: () => Navigator.pop(context, BgPickSource.files),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _busy = _GalleryBusy.picker);
    final service = ref.read(bgImportServiceProvider);
    final outcome = source == BgPickSource.gallery
        ? await service.fromGallery()
        : await service.fromFileManager();
    if (!mounted) return;
    setState(() => _busy = null);
    _refreshPools();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(outcome.message)));
  }

  void _refreshPools() {
    ref.invalidate(bgFullLibraryProvider);
    ref.invalidate(bgUserLibraryProvider);
    ref.invalidate(bgLibraryProvider);
  }

  // ------------------------------------------------------------------ 预览与单图操作

  Future<void> _preview(BgImage image) async {
    final isDisabled = ref.read(bgDisabledIdsProvider).contains(image.id);
    final action = await showDialog<_GalleryAction>(
      context: context,
      builder: (context) => _ImagePreviewDialog(
        image: image,
        isDisabled: isDisabled,
      ),
    );
    if (action == null || !mounted) return;
    final ids = ref.read(bgDisabledIdsProvider.notifier);
    switch (action) {
      case _GalleryAction.toggleDisable:
        final nowDisabled = await ids.toggle(image.id);
        if (!mounted) return;
        ref.invalidate(bgLibraryProvider);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(nowDisabled
                  ? '已禁用：三页背景不再抽到这张'
                  : '已启用：重新进入候选池')));
      case _GalleryAction.delete:
        final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('删除这张图？'),
                content: const Text('图片文件与登记条目会一并删除，不可恢复。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.error),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除')),
                ],
              ),
            ) ??
            false;
        if (!ok || !mounted) return;
        await ref.read(bgLibraryStoreProvider).remove(image.id);
        await ids.discard(image.id);
        if (!mounted) return;
        _refreshPools();
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('已删除')));
    }
  }
}

enum _GalleryBusy { picker }

enum _GalleryAction { toggleDisable, delete }

/// 单图大图预览 + 操作按钮。
class _ImagePreviewDialog extends StatelessWidget {
  const _ImagePreviewDialog({required this.image, required this.isDisabled});

  final BgImage image;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.42,
                ),
                child: Image(
                  image: bgImageProvider(image),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 120,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${image.sourceName.isEmpty ? image.id : image.sourceName}\n'
              '${image.width}×${image.height} · ${image.rule.label} · '
              '${image.bundled ? "内置" : "我添加的"}'
              '${image.bytes > 0 ? " · ${(image.bytes / 1024).round()} KB" : ""}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            if (isDisabled)
              Text('当前已禁用：不参与任何页面的随机抽取',
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: Icon(isDisabled
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  label: Text(isDisabled ? '启用' : '禁用'),
                  onPressed: () =>
                      Navigator.of(context).pop(_GalleryAction.toggleDisable),
                ),
                const Spacer(),
                if (!image.bundled)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    onPressed: () =>
                        Navigator.of(context).pop(_GalleryAction.delete),
                    child: const Text('删除'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 网格缩略图：禁用的图压暗 + 角标。
class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.image,
    required this.isDisabled,
    required this.onTap,
  });

  final BgImage image;
  final bool isDisabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: bgImageProvider(image),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: const Center(
                    child: Icon(Icons.broken_image_outlined, size: 20)),
              ),
            ),
            if (isDisabled)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.55),
                child: Center(
                  child: Icon(Icons.visibility_off_outlined,
                      size: 20, color: Colors.white.withValues(alpha: 0.9)),
                ),
              ),
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  image.category.code,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.white, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
