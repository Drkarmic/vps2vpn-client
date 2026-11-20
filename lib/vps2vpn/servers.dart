// vps2vpn "Servers": pick the line you use, see how fast each one answers.

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/vps2vpn/home.dart';
import 'package:fl_clash/vps2vpn/kit.dart';
import 'package:fl_clash/vps2vpn/shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Protocol names a non-expert can read.
String protocolLabel(BuildContext context, String type) {
  final t = type.toLowerCase();
  return switch (t) {
    'hysteria2' || 'hysteria' => tr(context, 'Hysteria2 · 快', 'Hysteria2 · fast'),
    'vless' => tr(context, 'REALITY · 稳', 'REALITY · steady'),
    'tuic' => tr(context, 'TUIC · 快', 'TUIC · fast'),
    'trojan' => 'Trojan',
    'vmess' => 'VMess',
    'ss' || 'shadowsocks' => 'Shadowsocks',
    'anytls' => 'AnyTLS',
    'wireguard' => 'WireGuard',
    'direct' => tr(context, '直连', 'Direct'),
    'reject' => tr(context, '拦截', 'Block'),
    'selector' => tr(context, '手动选择', 'Manual'),
    'urltest' => tr(context, '自动选最快', 'Fastest'),
    'fallback' => tr(context, '自动备用', 'Auto fallback'),
    'loadbalance' => tr(context, '负载均衡', 'Balanced'),
    _ => type,
  };
}

class VpsServersPage extends ConsumerStatefulWidget {
  const VpsServersPage({super.key});

  @override
  ConsumerState<VpsServersPage> createState() => _VpsServersPageState();
}

class _VpsServersPageState extends ConsumerState<VpsServersPage> {
  String? _groupName;
  bool _testing = false;

  Future<void> _test(Group group) async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      await ref.read(proxiesActionProvider.notifier).delayTest(group.all, group.testUrl);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final groups = ref.watch(currentGroupsStateProvider).value.where((g) => g.hidden != true).toList();
    final hasProfile = ref.watch(profilesProvider.select((s) => s.isNotEmpty));
    final fallback = mainGroup(groups);
    final group = groups.firstWhere((g) => g.name == _groupName, orElse: () => fallback ?? const Group(type: GroupType.Selector, name: ''));

    if (groups.isEmpty) {
      return VpsPage(
        title: tr(context, '服务器', 'Servers'),
        subtitle: tr(context, '你的线路都在这里', 'All your lines'),
        children: [
          VpsCard(
            padding: const EdgeInsets.all(36),
            child: Column(
              children: [
                VpsIconView(VpsIcon.servers, size: 40, color: p.accent),
                const SizedBox(height: 14),
                Text(
                  hasProfile
                      ? tr(context, '当前是直连模式，或线路还没加载出来', 'Nothing to pick in this mode yet')
                      : tr(context, '还没有服务器', 'No servers yet'),
                  style: vpsText(p, size: 17, weight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(context, '在「我的」里添加订阅链接后，这里会出现你的线路', 'Add your subscription in Me and your lines show up here'),
                  textAlign: TextAlign.center,
                  style: vpsText(p, size: 13.5, color: p.soft),
                ),
                if (!hasProfile) ...[
                  const SizedBox(height: 18),
                  VpsButton(
                    label: tr(context, '去添加', 'Add one'),
                    icon: VpsIcon.plus,
                    filled: true,
                    onTap: () => vpsTab.value = vpsTabMe,
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    final selected = ref.watch(selectedProxyNameProvider(group.name));
    final selectable = group.type == GroupType.Selector;
    return VpsPage(
      title: tr(context, '服务器', 'Servers'),
      subtitle: selectable
          ? tr(context, '点一下就换线路', 'Tap a line to switch')
          : tr(context, '这一组会自动选择', 'This group picks automatically'),
      action: VpsButton(
        label: _testing ? tr(context, '测速中…', 'Testing…') : tr(context, '测速', 'Test speed'),
        icon: VpsIcon.bolt,
        onTap: () => _test(group),
      ),
      children: [
        if (groups.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in groups)
                _GroupTab(
                  label: g.name,
                  selected: g.name == group.name,
                  onTap: () => setState(() => _groupName = g.name),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 820 ? 3 : (c.maxWidth >= 520 ? 2 : 1);
            final w = (c.maxWidth - 12 * (cols - 1)) / cols;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final proxy in group.all)
                  SizedBox(
                    width: w,
                    child: _ProxyCard(
                      proxy: proxy,
                      testUrl: group.testUrl,
                      selected: proxy.name == selected,
                      onTap: selectable
                          ? () => ref.read(proxiesActionProvider.notifier).changeProxy(groupName: group.name, proxyName: proxy.name)
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _GroupTab extends StatelessWidget {
  const _GroupTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    return VpsPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? p.accentGradient : null,
          color: selected ? null : p.card,
          borderRadius: BorderRadius.circular(99),
          border: selected ? null : Border.all(color: p.line),
        ),
        child: Text(
          label,
          style: vpsText(p, size: 13.5, weight: FontWeight.w600, color: selected ? p.accentInk : p.text),
        ),
      ),
    );
  }
}

class _ProxyCard extends ConsumerWidget {
  const _ProxyCard({required this.proxy, required this.testUrl, required this.selected, this.onTap});

  final Proxy proxy;
  final String? testUrl;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = VpsPalette.of(context);
    final delay = ref.watch(delayProvider(proxyName: proxy.name, testUrl: testUrl));
    final (delayText, delayColor) = switch (delay) {
      null => ('—', p.muted),
      0 => ('…', p.soft),
      < 0 => (tr(context, '超时', 'Timeout'), p.bad),
      < 200 => ('$delay ms', p.good),
      < 500 => ('$delay ms', p.warn),
      _ => ('$delay ms', p.bad),
    };
    return VpsCard(
      onTap: onTap,
      highlight: selected,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? p.accent : const Color(0x00000000),
              border: Border.all(color: selected ? p.accent : p.muted, width: 1.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(proxy.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: vpsText(p, size: 14.5, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(protocolLabel(context, proxy.type), style: vpsText(p, size: 12, color: p.soft)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(delayText, style: vpsText(p, size: 13, weight: FontWeight.w700, color: delayColor)),
        ],
      ),
    );
  }
}
