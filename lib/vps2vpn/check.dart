// vps2vpn "Check": where the internet sees you, and which sites open.

import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/service_status.dart';
import 'package:fl_clash/vps2vpn/home.dart';
import 'package:fl_clash/vps2vpn/kit.dart';
import 'package:fl_clash/vps2vpn/shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _groups = [
  ('AI', [ServiceTarget.claude, ServiceTarget.chatgpt, ServiceTarget.gemini]),
  ('常用', [ServiceTarget.google, ServiceTarget.github, ServiceTarget.youtube, ServiceTarget.discord]),
  ('影音', [ServiceTarget.netflix, ServiceTarget.disneyPlus, ServiceTarget.spotify, ServiceTarget.tiktok]),
];

List<ServiceTarget> get _all => [for (final (_, ts) in _groups) ...ts];

String statusText(BuildContext context, ProbeEntry<ServiceCheck> entry) {
  final s = entry.value?.status;
  if (s == null) return entry.isLoading ? tr(context, '检测中…', 'Checking…') : tr(context, '还没检测', 'Not checked');
  return switch (s) {
    ServiceProbeStatus.available => tr(context, '能用', 'Works'),
    ServiceProbeStatus.restricted => tr(context, '部分受限', 'Limited'),
    ServiceProbeStatus.originalsOnly => tr(context, '仅自制剧', 'Originals only'),
    ServiceProbeStatus.comingSoon => tr(context, '该地区即将开放', 'Coming soon here'),
    ServiceProbeStatus.unsupportedRegion => tr(context, '该地区不支持', 'Not in this region'),
    ServiceProbeStatus.disallowedIsp => tr(context, '机房 IP 被拒', 'Datacenter IP refused'),
    ServiceProbeStatus.blocked => tr(context, '被封锁', 'Blocked'),
    ServiceProbeStatus.unavailable => tr(context, '不能用', 'Unavailable'),
    ServiceProbeStatus.timeout => tr(context, '超时', 'Timed out'),
    ServiceProbeStatus.failed => tr(context, '检测失败', 'Check failed'),
  };
}

class VpsCheckPage extends ConsumerStatefulWidget {
  const VpsCheckPage({super.key});

  @override
  ConsumerState<VpsCheckPage> createState() => _VpsCheckPageState();
}

class _VpsCheckPageState extends ConsumerState<VpsCheckPage> {
  late final ServiceStatus _services;
  late final OutboundIpProbe _ip;
  bool _showIp = false;

  @override
  void initState() {
    super.initState();
    _services = ref.read(serviceStatusProvider.notifier);
    _ip = ref.read(outboundIpProbeProvider.notifier)..watch(routedOutbound);
    for (final t in _all) {
      _services.watch(t);
    }
  }

  @override
  void dispose() {
    for (final t in _all) {
      _services.unwatch(t);
    }
    _ip.unwatch(routedOutbound);
    super.dispose();
  }

  void _recheck() {
    _ip.refresh([routedOutbound]);
    _services.refresh(_all);
  }

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final isStart = ref.watch(isStartProvider);
    final ipEntry = ref.watch(outboundIpProbeProvider.select((s) => s.entryOf(routedOutbound)));
    final info = ipEntry.value;
    final services = ref.watch(serviceStatusProvider);
    final working = _all.where((t) => services.entryOf(t).value?.status == ServiceProbeStatus.available).length;

    return VpsPage(
      title: tr(context, '检测', 'Check'),
      subtitle: tr(context, '看看别人眼中的你，以及哪些网站能打开', 'How sites see you, and what opens'),
      action: VpsButton(label: tr(context, '重新检测', 'Check again'), icon: VpsIcon.refresh, onTap: _recheck),
      children: [
        if (!isStart)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: VpsCard(
              onTap: () => vpsTab.value = vpsTabHome,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  VpsIconView(VpsIcon.info, size: 19, color: p.warn),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr(context, '现在没连接，下面是不走服务器时的结果', 'Not connected: results below are without your server'),
                      style: vpsText(p, size: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 640;
            final exit = VpsCard(
              highlight: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(context, '你的出口', 'Your exit'), style: vpsText(p, size: 13, color: p.soft, weight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    info == null
                        ? (ipEntry.isLoading ? tr(context, '查询中…', 'Looking up…') : '—')
                        : countryName(context, info.countryCode),
                    style: vpsText(p, size: 30, weight: FontWeight.w800, spacing: -0.3),
                  ),
                  const SizedBox(height: 10),
                  if (info != null)
                    VpsPressable(
                      onTap: () => setState(() => _showIp = !_showIp),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _showIp ? info.ip : _mask(info.ip),
                            style: vpsText(p, size: 14, weight: FontWeight.w600, color: p.soft),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _showIp ? tr(context, '隐藏', 'Hide') : tr(context, '显示', 'Show'),
                            style: vpsText(p, size: 13, weight: FontWeight.w700, color: p.accent),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
            final score = VpsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(context, '能正常打开', 'Opening fine'), style: vpsText(p, size: 13, color: p.soft, weight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$working', style: vpsText(p, size: 30, weight: FontWeight.w800, color: p.good)),
                      TextSpan(text: ' / ${_all.length}', style: vpsText(p, size: 18, weight: FontWeight.w700, color: p.soft)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: SizedBox(
                      height: 8,
                      child: Stack(
                        children: [
                          Container(color: p.line),
                          FractionallySizedBox(
                            widthFactor: _all.isEmpty ? 0 : working / _all.length,
                            child: Container(decoration: BoxDecoration(gradient: p.accentGradient)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
            if (!wide) return Column(children: [exit, const SizedBox(height: 12), score]);
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: exit), const SizedBox(width: 12), Expanded(child: score)],
              ),
            );
          },
        ),
        for (final (name, targets) in _groups) ...[
          const SizedBox(height: 22),
          VpsSectionTitle(name == '常用' ? tr(context, '常用', 'Everyday') : name == '影音' ? tr(context, '影音', 'Media') : name),
          VpsCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Column(
              children: [
                for (final (i, t) in targets.indexed) ...[
                  if (i > 0) Container(height: 1, color: p.line),
                  _ServiceLine(target: t, entry: services.entryOf(t)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

String _mask(String ip) {
  if (ip.contains(':')) {
    final parts = ip.split(':');
    return '${parts.first}:••••:••••';
  }
  final parts = ip.split('.');
  if (parts.length != 4) return '••••';
  return '${parts[0]}.••.••.${parts[3]}';
}

class _ServiceLine extends StatelessWidget {
  const _ServiceLine({required this.target, required this.entry});

  final ServiceTarget target;
  final ProbeEntry<ServiceCheck> entry;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final check = entry.value;
    final color = switch (check?.status) {
      null => p.muted,
      ServiceProbeStatus.available => p.good,
      ServiceProbeStatus.restricted || ServiceProbeStatus.originalsOnly || ServiceProbeStatus.comingSoon => p.warn,
      _ => p.bad,
    };
    final region = check?.region;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.accentWash, borderRadius: BorderRadius.circular(10)),
            child: Text(target.label.substring(0, 1), style: vpsText(p, size: 15, weight: FontWeight.w800, color: p.accent)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(target.label, style: vpsText(p, size: 15, weight: FontWeight.w600))),
          if (region != null && region.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(region.toUpperCase(), style: vpsText(p, size: 12.5, color: p.soft)),
            ),
          VpsChip(label: statusText(context, entry), color: color),
        ],
      ),
    );
  }
}
