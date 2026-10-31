/// 使用指南（US-G01）：3 屏极简上手——按键教学 → 余光与反馈 → 权限与隐私。
///
/// 原则（US-H01）：数据默认仅存本地；敏感权限逐项说明用途后再引导开启。
/// 首次启动自动显示（完成后写 onboarding_done），也可从
/// 「设置 → 使用指南」随时重看——重看时「完成」仅返回上一页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/permissions.dart';
import '../../../platform/prefs/prefs_provider.dart';

/// 引导页完成标记（shared_preferences）。
const kOnboardingDoneKey = 'onboarding_done';

/// 使用指南页（首启引导 / 设置页重看共用）。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pageController = PageController();
  int _index = 0;

  /// 通知权限申请状态（第三屏按钮反馈用）
  bool? _notificationGranted;

  Future<void> _finish() async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(kOnboardingDoneKey, true);
    if (!mounted) return;
    final nav = Navigator.of(context);
    // 从设置页重看进来时有上一页可退；首启引导则替换到主页
    if (nav.canPop()) {
      nav.pop();
    } else {
      await nav.pushReplacementNamed('/');
    }
  }

  Future<void> _requestNotification() async {
    final granted = await AppPermissions.ensureNotificationPermission();
    setState(() => _notificationGranted = granted);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _buildKeysPage(),
                  _buildGlancePage(),
                  _buildPermissionPage(),
                ],
              ),
            ),
            // 页码指示 + 下一步/完成
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _index
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                          ),
                        ),
                    ],
                  ),
                  FilledButton(
                    onPressed: _index < 2
                        ? () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut)
                        : _finish,
                    child: Text(_index < 2 ? '下一步' : '完成'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 第一屏：按键教学——按当前真实默认映射（看板 #33/#38）。
  /// 注意：M500 实测长按不上报（R1），不教学长按，避免误导新用户。
  Widget _buildKeysPage() {
    return const _OnboardingSheet(
      icon: Icons.music_note,
      title: '用机身按键控制专注',
      body: '机器横放在桌角，全程不用摸屏幕。'
          '你只需记住一个键：单按「播放/暂停」。',
      items: [
        ('播放/暂停 · 单按', '开始 / 暂停'),
        ('播放/暂停 · 双按', '音乐下一首（计时不断）'),
        ('下一曲', '跳过当前阶段'),
        ('上一曲', '+5 分钟（正计时=打点）'),
        ('结束专注', '通知栏「结束」或屏幕按钮'),
      ],
    );
  }

  /// 第二屏：余光设计 + 声音反馈——颜色报状态，耳朵收确认。
  Widget _buildGlancePage() {
    return const _OnboardingSheet(
      icon: Icons.music_note,
      title: '放在余光里，用耳朵确认',
      body: '整屏颜色就是状态：专注与休息各一种颜色，余光一扫即知；'
          '大字号时间一米外可读。\n\n'
          '每次按键生效都会立刻有提示音确认（音型各不相同），'
          '熄屏也能盲操作；音、提醒可在设置中分别关闭。\n\n'
          '「设置 → 按键自检」可随时验证按键是否正常。',
      items: [],
    );
  }

  /// 第三屏：权限与隐私——逐项说明用途后再引导开启（US-H01）；
  /// 含 AI 安静原则告知（ADR-0006：默认关闭、主动触发、随时可删）。
  Widget _buildPermissionPage() {
    return _OnboardingSheet(
      icon: Icons.privacy_tip_outlined,
      title: '权限与隐私',
      body: '所有专注数据只存在本机，离线可用，不上传。\n\n'
          '通知权限用于在锁屏/通知栏显示计时状态和暂停/结束按钮，'
          '是后台计时的必要保障；拒绝后仅亮屏可用。\n\n'
          'AI 周报解读默认关闭：只有你在设置中手动开启并配置自己的 '
          'API Key，且主动点击「AI 解读」时才会联网，随时可一键删除。',
      items: const [],
      footer: Column(
        children: [
          FilledButton.tonalIcon(
            onPressed: _requestNotification,
            icon: const Icon(Icons.notifications_outlined),
            label: Text(switch (_notificationGranted) {
              true => '通知权限已开启',
              false => '未开启，可稍后在设置中开启',
              null => '开启通知权限',
            }),
          ),
        ],
      ),
    );
  }
}

/// 单屏骨架：图标 + 标题 + 说明 + 可选条目表 + 可选底部操作。
/// 横屏（M500 锁定方向）下左右双栏，竖屏单列，两侧都可滚动兜底小画布。
class _OnboardingSheet extends StatelessWidget {
  const _OnboardingSheet({
    required this.icon,
    required this.title,
    required this.body,
    required this.items,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<(String, String)> items;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: landscape ? 44 : 56,
                color: Theme.of(context).colorScheme.primary),
            SizedBox(height: landscape ? 12 : 20),
            Text(title,
                style: TextStyle(
                    fontSize: landscape ? 22 : 26,
                    fontWeight: FontWeight.w700)),
          ],
        );
        final detail = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: const TextStyle(fontSize: 15, height: 1.5)),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      for (final (key, action) in items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(key,
                                      style: const TextStyle(fontSize: 14))),
                              Text(action,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (footer != null) ...[
              const SizedBox(height: 16),
              Center(child: footer!),
            ],
          ],
        );
        if (landscape) {
          // 720p 横屏画布仅 ~640×360dp：左标题右内容，右栏滚动兜底
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 2, child: header),
                const SizedBox(width: 24),
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(child: detail),
                ),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              header,
              const SizedBox(height: 16),
              detail,
            ],
          ),
        );
      },
    );
  }
}
