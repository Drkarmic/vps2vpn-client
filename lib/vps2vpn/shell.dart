// vps2vpn simple-mode window: our own sidebar (wide) or floating tab bar
// (narrow) around four pages. Replaces FlClash's shell while advanced mode
// is off.

import 'dart:io';

import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/vps2vpn/check.dart';
import 'package:fl_clash/vps2vpn/home.dart';
import 'package:fl_clash/vps2vpn/kit.dart';
import 'package:fl_clash/vps2vpn/mine.dart';
import 'package:fl_clash/vps2vpn/servers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' show Theme;

/// The open tab; pages switch it (e.g. the home button opens "Me").
/// VPS2VPN_TAB (0-3) opens a page at start; used for test screenshots.
final vpsTab = ValueNotifier<int>(
  (int.tryParse(Platform.environment['VPS2VPN_TAB'] ?? '') ?? 0).clamp(0, 3),
);

const vpsTabHome = 0;
const vpsTabServers = 1;
const vpsTabCheck = 2;
const vpsTabMe = 3;

class VpsShell extends StatelessWidget {
  const VpsShell({super.key});

  static const _pages = [
    VpsHomePage(),
    VpsServersPage(),
    VpsCheckPage(),
    VpsMePage(),
  ];

  @override
  Widget build(BuildContext context) {
    // Our pages sit outside prism_ui's Scaffold, so give them the app's font
    // (and no debug underline) here.
    return DefaultTextStyle(
      style: Theme.of(context).bodyTextStyle.copyWith(
        decoration: TextDecoration.none,
        color: VpsPalette.of(context).text,
      ),
      child: VpsBackdrop(
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 760;
            return ValueListenableBuilder<int>(
              valueListenable: vpsTab,
              builder: (context, tab, _) {
                final body = AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.015),
                        end: Offset.zero,
                      ).animate(a),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(key: ValueKey(tab), child: _pages[tab]),
                );
                if (wide) {
                  return Row(
                    children: [
                      _SideNav(tab: tab),
                      Expanded(child: body),
                    ],
                  );
                }
                return Stack(
                  children: [
                    Positioned.fill(child: body),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: _BottomNav(tab: tab),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

List<(VpsIcon, String)> _tabs(BuildContext context) => [
  (VpsIcon.home, tr(context, '首页', 'Home')),
  (VpsIcon.servers, tr(context, '服务器', 'Servers')),
  (VpsIcon.check, tr(context, '检测', 'Check')),
  (VpsIcon.me, tr(context, '我的', 'Me')),
];

class _SideNav extends ConsumerWidget {
  const _SideNav({required this.tab});

  final int tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = VpsPalette.of(context);
    final isStart = ref.watch(isStartProvider);
    return Container(
      width: 224,
      decoration: BoxDecoration(
        color: p.dark ? const Color(0x99121320) : p.side,
        border: Border(right: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(
              children: [
                const VpsLogo(size: 34),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'vps2vpn',
                      style: vpsText(
                        p,
                        size: 18,
                        weight: FontWeight.w800,
                        spacing: 0.3,
                      ),
                    ),
                    Text(
                      tr(context, '你自己的 VPN', 'Your own VPN'),
                      style: vpsText(p, size: 11.5, color: p.soft),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          for (final (i, (icon, label)) in _tabs(context).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _NavItem(
                icon: icon,
                label: label,
                selected: i == tab,
                onTap: () => vpsTab.value = i,
              ),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.line),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isStart ? p.good : p.muted,
                    boxShadow: isStart
                        ? [
                            BoxShadow(
                              color: p.good.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ]
                        : const [],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  isStart
                      ? tr(context, '已连接', 'Connected')
                      : tr(context, '未连接', 'Not connected'),
                  style: vpsText(p, size: 13, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final VpsIcon icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    return VpsPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? p.accentWash : const Color(0x00000000),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            VpsIconView(icon, size: 21, color: selected ? p.accent : p.soft),
            const SizedBox(width: 14),
            Text(
              label,
              style: vpsText(
                p,
                size: 15,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? p.text : p.soft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.tab});

  final int tab;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    return Container(
      height: 66,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.dark ? const Color(0xE6181A2B) : const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.line),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final (i, (icon, label)) in _tabs(context).indexed)
            Expanded(
              child: VpsPressable(
                onTap: () => vpsTab.value = i,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: i == tab ? p.accentWash : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      VpsIconView(
                        icon,
                        size: 21,
                        color: i == tab ? p.accent : p.soft,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: vpsText(
                          p,
                          size: 11,
                          weight: FontWeight.w600,
                          color: i == tab ? p.text : p.soft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Page frame: big title, optional action, scrolling body with room for the
/// floating tab bar on narrow windows.
class VpsPage extends StatelessWidget {
  const VpsPage({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 600;
        final side = wide ? 36.0 : 16.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            side,
            wide ? 30 : 18,
            side,
            wide ? 36 : 100,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 940),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: vpsText(
                                p,
                                size: wide ? 30 : 26,
                                weight: FontWeight.w800,
                                spacing: -0.3,
                              ),
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  subtitle!,
                                  style: vpsText(p, size: 14, color: p.soft),
                                ),
                              ),
                          ],
                        ),
                      ),
                      ?action,
                    ],
                  ),
                  const SizedBox(height: 22),
                  ...children,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
