// vps2vpn home: one big connect button, where you exit, live speed,
// plan usage, how you go online, and whether the AI sites open.

import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/service_status.dart';
import 'package:fl_clash/vps2vpn/kit.dart';
import 'package:fl_clash/vps2vpn/shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _countryZh = {
  'SG': '新加坡', 'US': '美国', 'JP': '日本', 'HK': '香港', 'TW': '台湾',
  'KR': '韩国', 'DE': '德国', 'GB': '英国', 'FR': '法国', 'NL': '荷兰',
  'AU': '澳大利亚', 'CA': '加拿大', 'IN': '印度', 'MY': '马来西亚',
  'TH': '泰国', 'VN': '越南', 'PH': '菲律宾', 'ID': '印度尼西亚',
  'RU': '俄罗斯', 'CN': '中国', 'MO': '澳门', 'TR': '土耳其',
};

String countryName(BuildContext context, String code) {
  final c = code.toUpperCase();
  return vpsZh(context) ? (_countryZh[c] ?? c) : c;
}

/// The first selectable group: what "the server you use" means here.
Group? mainGroup(List<Group> groups) {
  for (final g in groups) {
    if (g.type == GroupType.Selector && g.hidden != true) return g;
  }
  return groups.isEmpty ? null : groups.first;
}

class VpsHomePage extends ConsumerWidget {
  const VpsHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = VpsPalette.of(context);
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    final systemProxy = ref.watch(networkSettingProvider.select((s) => s.systemProxy));
    final tun = ref.watch(patchClashConfigProvider.select((s) => s.tun.enable));
    return VpsPage(
      title: tr(context, '你好', 'Hello'),
      subtitle: tr(context, '自己的服务器，自己的 VPN', 'Your server, your VPN'),
      children: [
        const _Hero(),
        const SizedBox(height: 16),
        const _Stats(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 720;
            final routing = VpsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      VpsIconView(VpsIcon.globe, size: 19, color: p.accent),
                      const SizedBox(width: 10),
                      Text(tr(context, '上网方式', 'Routing'), style: vpsText(p, size: 15, weight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  VpsSegmented<Mode>(
                    items: const [Mode.rule, Mode.global],
                    value: mode == Mode.direct ? Mode.rule : mode,
                    labelOf: (m) => m == Mode.rule
                        ? tr(context, '智能分流', 'Smart')
                        : tr(context, '全部走代理', 'Everything'),
                    onChanged: (m) => ref.read(setupActionProvider.notifier).changeMode(m),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    mode == Mode.global
                        ? tr(context, '所有网站都经过你的服务器', 'Every site goes through your server')
                        : tr(context, '国内网站直连更快，国外网站走服务器', 'Local sites go direct, the rest via your server'),
                    style: vpsText(p, size: 12.5, color: p.soft),
                  ),
                ],
              ),
            );
            final takeover = VpsCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  VpsRow(
                    icon: VpsIcon.bolt,
                    title: tr(context, '浏览器和大多数软件', 'Browsers and most apps'),
                    subtitle: tr(context, '系统代理', 'System proxy'),
                    trailing: VpsSwitch(
                      value: systemProxy,
                      onChanged: (v) => ref.read(networkSettingProvider.notifier).update((s) => s.copyWith(systemProxy: v)),
                    ),
                  ),
                  Container(height: 1, color: p.line),
                  VpsRow(
                    icon: VpsIcon.shield,
                    title: tr(context, '全部软件（含终端、游戏）', 'Every app, terminal included'),
                    subtitle: tr(context, '虚拟网卡 · 需要管理员权限', 'Virtual adapter · needs admin'),
                    trailing: VpsSwitch(
                      value: tun,
                      onChanged: (v) => ref.read(patchClashConfigProvider.notifier).update((s) => s.copyWith.tun(enable: v)),
                    ),
                  ),
                ],
              ),
            );
            if (!wide) {
              return Column(children: [routing, const SizedBox(height: 16), takeover]);
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: routing),
                  const SizedBox(width: 16),
                  Expanded(child: takeover),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const _AiStrip(),
      ],
    );
  }
}

class _Hero extends ConsumerStatefulWidget {
  const _Hero();

  @override
  ConsumerState<_Hero> createState() => _HeroState();
}

class _HeroState extends ConsumerState<_Hero> {
  late final OutboundIpProbe _probe;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier)..watch(routedOutbound);
  }

  @override
  void dispose() {
    _probe.unwatch(routedOutbound);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final isStart = ref.watch(isStartProvider);
    final suspended = isStart && ref.watch(suspendProvider);
    final on = isStart && !suspended;
    final hasProfile = ref.watch(profilesProvider.select((s) => s.isNotEmpty));
    final runTime = ref.watch(runTimeProvider);
    final info = ref.watch(outboundIpProbeProvider.select((s) => s.entryOf(routedOutbound))).value;
    final group = mainGroup(ref.watch(currentGroupsStateProvider).value);
    final line = group == null ? null : ref.watch(selectedProxyNameProvider(group.name));

    final title = !hasProfile
        ? tr(context, '先添加你的服务器', 'Add your server first')
        : suspended
        ? tr(context, '已暂停', 'Paused')
        : on
        ? tr(context, '已连接', 'Connected')
        : tr(context, '未连接', 'Not connected');
    final sub = !hasProfile
        ? tr(context, '点按钮，粘贴部署工具给你的订阅链接', 'Tap the button and paste your subscription link')
        : on
        ? tr(context, '已安全连接 ${getTimeText(runTime)}', 'Protected for ${getTimeText(runTime)}')
        : tr(context, '点一下按钮就能连上', 'One tap to connect');

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 640;
        final button = _PowerRing(
          on: on,
          size: wide ? 176 : 150,
          label: !hasProfile ? tr(context, '添加', 'Add') : (on ? tr(context, '断开', 'Stop') : tr(context, '连接', 'Connect')),
          onTap: hasProfile
              ? () => ref.read(commonActionProvider.notifier).toggleRunning()
              : () => vpsTab.value = vpsTabMe,
        );
        final texts = Column(
          crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                title,
                key: ValueKey(title),
                style: vpsText(p, size: wide ? 40 : 32, weight: FontWeight.w800, spacing: -0.5, height: 1.1,
                    color: on && !p.dark ? vpsCoralDeep : p.text),
              ),
            ),
            const SizedBox(height: 10),
            Text(sub, textAlign: wide ? TextAlign.start : TextAlign.center, style: vpsText(p, size: 14.5, color: p.soft)),
            if (hasProfile) ...[
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: wide ? WrapAlignment.start : WrapAlignment.center,
                children: [
                  _InfoPill(
                    label: tr(context, '出口', 'Exit'),
                    value: info == null ? '—' : '${countryName(context, info.countryCode)} · ${info.countryCode.toUpperCase()}',
                  ),
                  if (line != null && line.isNotEmpty)
                    _InfoPill(label: tr(context, '线路', 'Line'), value: line),
                ],
              ),
            ],
          ],
        );
        return Container(
          padding: EdgeInsets.all(wide ? 36 : 24),
          decoration: BoxDecoration(
            color: p.dark ? const Color(0x14FFFFFF) : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: on ? p.accent.withValues(alpha: 0.5) : p.line, width: on ? 1.5 : 1),
            boxShadow: p.dark
                ? const []
                : [BoxShadow(color: const Color(0xFF7A3B2E).withValues(alpha: 0.08), blurRadius: 40, offset: const Offset(0, 14))],
          ),
          child: wide
              ? Row(children: [Expanded(child: texts), const SizedBox(width: 24), button])
              : Column(children: [button, const SizedBox(height: 18), texts]),
        );
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: p.dark ? const Color(0x12FFFFFF) : const Color(0xFFFBF3F0),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: p.line),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label  ', style: vpsText(p, size: 13, color: p.soft)),
          TextSpan(text: value, style: vpsText(p, size: 13, weight: FontWeight.w700)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The connect button: a glowing ring that breathes while connected.
class _PowerRing extends StatefulWidget {
  const _PowerRing({required this.on, required this.size, required this.label, required this.onTap});

  final bool on;
  final double size;
  final String label;
  final VoidCallback onTap;

  @override
  State<_PowerRing> createState() => _PowerRingState();
}

class _PowerRingState extends State<_PowerRing> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.on) _spin.repeat();
  }

  @override
  void didUpdateWidget(_PowerRing old) {
    super.didUpdateWidget(old);
    if (widget.on && !_spin.isAnimating) _spin.repeat();
    if (!widget.on && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final s = widget.size;
    return VpsPressable(
      onTap: widget.onTap,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow.
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: vpsCoral.withValues(alpha: widget.on ? 0.45 : (p.dark ? 0.15 : 0.18)),
                    blurRadius: widget.on ? 60 : 30,
                    spreadRadius: widget.on ? 4 : 0,
                  ),
                ],
              ),
            ),
            // Rotating gradient ring.
            AnimatedBuilder(
              animation: _spin,
              builder: (_, _) => Transform.rotate(
                angle: _spin.value * 2 * math.pi,
                child: CustomPaint(
                  size: Size(s, s),
                  painter: _RingPainter(on: widget.on, track: p.dark ? const Color(0x1FFFFFFF) : const Color(0xFFF3E6E2)),
                ),
              ),
            ),
            // Face.
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: s * 0.7,
              height: s * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: widget.on ? p.accentGradient : null,
                color: widget.on ? null : (p.dark ? const Color(0xFF1C1D2E) : const Color(0xFFFFF4F1)),
                border: widget.on ? null : Border.all(color: p.accent.withValues(alpha: 0.5), width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(s * 0.24),
                    painter: _PowerGlyph(widget.on ? const Color(0xFFFFFFFF) : p.accent),
                  ),
                  SizedBox(height: s * 0.03),
                  Text(
                    widget.label,
                    style: vpsText(p, size: s * 0.08, weight: FontWeight.w700, color: widget.on ? const Color(0xFFFFFFFF) : p.accent),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.on, required this.track});

  final bool on;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = track);
    if (!on) return;
    canvas.drawArc(
      rect,
      0,
      math.pi * 1.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [Color(0x00FF8A70), vpsCoralSoft, vpsCoralDeep, vpsViolet],
          stops: [0, 0.35, 0.7, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.on != on || old.track != track;
}

class _PowerGlyph extends CustomPainter {
  _PowerGlyph(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.42;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round;
    const gap = math.pi / 3;
    canvas.drawArc(Rect.fromCircle(center: c.translate(0, r * 0.15), radius: r), -math.pi / 2 + gap / 2, 2 * math.pi - gap, false, paint);
    canvas.drawLine(c.translate(0, -r * 1.05), c.translate(0, -r * 0.05), paint);
  }

  @override
  bool shouldRepaint(_PowerGlyph old) => old.color != color;
}

class _Stats extends ConsumerWidget {
  const _Stats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffics = ref.watch(trafficsProvider);
    final now = traffics.list.safeLast(const Traffic());
    final total = ref.watch(totalTrafficProvider);
    final profile = ref.watch(currentProfileProvider);
    final sub = profile?.subscriptionInfo;
    String? left;
    String? expire;
    if (sub != null && sub.total > 0) {
      final remain = math.max(0, sub.total - sub.upload - sub.download);
      left = remain.traffic.show;
    }
    if (sub != null && sub.expire > 0) {
      final days = DateTime.fromMillisecondsSinceEpoch(sub.expire * 1000).difference(DateTime.now()).inDays;
      expire = days >= 0 ? tr(context, '还剩 $days 天', '$days days left') : tr(context, '已到期', 'Expired');
    }
    final tiles = [
      _Stat(icon: VpsIcon.arrowDown, label: tr(context, '下载', 'Down'), value: '${now.down.traffic.show}/s'),
      _Stat(icon: VpsIcon.arrowUp, label: tr(context, '上传', 'Up'), value: '${now.up.traffic.show}/s'),
      _Stat(icon: VpsIcon.sparkle, label: tr(context, '本次用量', 'This session'), value: (total.up + total.down).traffic.show),
      _Stat(
        icon: VpsIcon.shield,
        label: left != null ? tr(context, '剩余流量', 'Data left') : tr(context, '到期', 'Expires'),
        value: left ?? expire ?? '—',
        foot: left != null ? expire : null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : 2;
        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, this.foot});

  final VpsIcon icon;
  final String label;
  final String value;
  final String? foot;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    return VpsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VpsIconView(icon, size: 16, color: p.accent),
              const SizedBox(width: 6),
              Text(label, style: vpsText(p, size: 12.5, color: p.soft, weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: vpsText(p, size: 22, weight: FontWeight.w800, spacing: -0.3)),
          if (foot != null) Text(foot!, style: vpsText(p, size: 12, color: p.soft)),
        ],
      ),
    );
  }
}

const aiTargets = [ServiceTarget.claude, ServiceTarget.chatgpt, ServiceTarget.gemini];

/// "Can I use the AI sites right now?" in one line.
class _AiStrip extends ConsumerStatefulWidget {
  const _AiStrip();

  @override
  ConsumerState<_AiStrip> createState() => _AiStripState();
}

class _AiStripState extends ConsumerState<_AiStrip> {
  late final ServiceStatus _services;

  @override
  void initState() {
    super.initState();
    _services = ref.read(serviceStatusProvider.notifier);
    for (final t in aiTargets) {
      _services.watch(t);
    }
  }

  @override
  void dispose() {
    for (final t in aiTargets) {
      _services.unwatch(t);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final state = ref.watch(serviceStatusProvider);
    return VpsCard(
      onTap: () => vpsTab.value = vpsTabCheck,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(gradient: p.accentGradient, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: const VpsIconView(VpsIcon.sparkle, size: 19, color: Color(0xFFFFFFFF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'AI 能不能用', 'AI availability'), style: vpsText(p, size: 15, weight: FontWeight.w700)),
                Text(tr(context, '通过你的服务器访问时', 'Through your server'), style: vpsText(p, size: 12.5, color: p.soft)),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final t in aiTargets) serviceChip(context, t, state.entryOf(t)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Plain-word status chip for one site.
Widget serviceChip(BuildContext context, ServiceTarget t, ProbeEntry<ServiceCheck> entry) {
  final p = VpsPalette.of(context);
  final check = entry.value;
  final (mark, color) = switch (check?.status) {
    null => (entry.isLoading ? '…' : '?', p.muted),
    ServiceProbeStatus.available => ('✓', p.good),
    ServiceProbeStatus.restricted || ServiceProbeStatus.originalsOnly || ServiceProbeStatus.comingSoon => ('!', p.warn),
    _ => ('✗', p.bad),
  };
  return VpsChip(label: '${t.label} $mark', color: color);
}
