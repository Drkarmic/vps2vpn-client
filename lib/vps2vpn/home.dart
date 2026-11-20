// vps2vpn: the simple-mode home page ("status center").
//
// A coral hero card with one big connect button and plain words, then speed,
// routing, connect switches, subscription and connectivity. Reuses FlClash's
// dashboard cards below the hero so they keep their behaviour.

import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const vpsCoral = Color(0xFFFF6F61);
const vpsCoralDeep = Color(0xFFE63E5C);
const vpsCoralSoft = Color(0xFFFF9A7B);

const _countryNames = {
  'SG': '新加坡', 'US': '美国', 'JP': '日本', 'HK': '香港', 'TW': '台湾',
  'KR': '韩国', 'DE': '德国', 'GB': '英国', 'FR': '法国', 'NL': '荷兰',
  'AU': '澳大利亚', 'CA': '加拿大', 'IN': '印度', 'MY': '马来西亚',
  'TH': '泰国', 'VN': '越南', 'PH': '菲律宾', 'ID': '印度尼西亚',
  'RU': '俄罗斯', 'CN': '中国', 'MO': '澳门', 'TR': '土耳其',
};

bool _zh(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'zh';

String _countryLabel(BuildContext context, String code) {
  final upper = code.toUpperCase();
  if (_zh(context)) return _countryNames[upper] ?? upper;
  return upper;
}

class VpsHomeView extends ConsumerWidget {
  const VpsHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = _zh(context);
    return Scaffold(
      title: zh ? '首页' : 'Home',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final side = wide ? 32.0 : 16.0;
          const gap = 16.0;
          final takeover = DashboardWidget.networkTakeover.platforms.contains(
            SupportPlatform.currentPlatform,
          );
          return DashboardDensityScope(
            density: wide ? DashboardDensity.compact : DashboardDensity.mobile,
            scale: 1,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                side,
                context.contentTopPadding,
                side,
                24 + context.bottomInset,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: gap,
                    children: [
                      _HeroCard(wide: wide),
                      SizedBox(
                        height: wide ? 132 : 124,
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: gap,
                          children: [
                            Expanded(
                              child: SpeedCard(
                                direction: TrafficDirection.upload,
                              ),
                            ),
                            Expanded(
                              child: SpeedCard(
                                direction: TrafficDirection.download,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 64, child: OutboundModeBar()),
                      SizedBox(
                        height: 64,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: gap,
                          children: takeover
                              ? const [
                                  Expanded(
                                    child: NetworkTakeoverTile(
                                      TakeoverSwitch.systemProxy,
                                    ),
                                  ),
                                  Expanded(
                                    child: NetworkTakeoverTile(
                                      TakeoverSwitch.tun,
                                    ),
                                  ),
                                ]
                              : const [Expanded(child: VpnTile())],
                        ),
                      ),
                      SizedBox(
                        height: wide ? 176 : null,
                        child: Flex(
                          direction: wide ? Axis.horizontal : Axis.vertical,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: gap,
                          children: [
                            if (wide)
                              const Expanded(child: ProfilesCard())
                            else
                              const SizedBox(height: 160, child: ProfilesCard()),
                            if (wide)
                              const Expanded(
                                child: ServiceStatusCard(columns: 2),
                              )
                            else
                              const SizedBox(
                                height: 176,
                                child: ServiceStatusCard(columns: 1),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The coral card: brand, connected or not, where traffic exits, and the
/// one button that connects.
class _HeroCard extends ConsumerStatefulWidget {
  const _HeroCard({required this.wide});

  final bool wide;

  @override
  ConsumerState<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends ConsumerState<_HeroCard> {
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
    final zh = _zh(context);
    final isStart = ref.watch(isStartProvider);
    final suspended = isStart && ref.watch(suspendProvider);
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    final runTime = ref.watch(runTimeProvider);
    final info = ref
        .watch(
          outboundIpProbeProvider.select(
            (state) => state.entryOf(routedOutbound),
          ),
        )
        .value;
    final dark = context.colorScheme.brightness == Brightness.dark;
    final on = isStart && !suspended;

    final title = !hasProfile
        ? (zh ? '还没有添加服务器' : 'No server yet')
        : suspended
        ? (zh ? '已暂停' : 'Paused')
        : on
        ? (zh ? '已连接' : 'Connected')
        : (zh ? '未连接' : 'Not connected');
    final subtitle = !hasProfile
        ? (zh ? '点右边的按钮，粘贴订阅链接就能开始' : 'Tap the button to add a subscription')
        : on
        ? (zh ? '已运行 ${getTimeText(runTime)}' : 'Up ${getTimeText(runTime)}')
        : (zh ? '点右边的按钮，一键连接' : 'Tap the button to connect');
    final exit = info == null
        ? null
        : '${_countryLabel(context, info.countryCode)} · ${info.countryCode.toUpperCase()}';

    final gradient = on
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [vpsCoralSoft, vpsCoral, vpsCoralDeep],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF3A2A2C), Color(0xFF2A2224), Color(0xFF221D1F)]
                : const [Color(0xFFFFF1EE), Color(0xFFFFE3DD), Color(0xFFFFD6CE)],
          );
    final ink = on
        ? const Color(0xFFFFFFFF)
        : (dark ? const Color(0xFFFFFFFF) : const Color(0xFF3B1F1C));
    final inkSoft = ink.withValues(alpha: 0.78);

    final button = _PowerButton(
      on: on,
      enabled: true,
      size: widget.wide ? 148 : 120,
      // With no server yet, the button leads to where one is added.
      onTap: hasProfile
          ? () => ref.read(commonActionProvider.notifier).toggleRunning()
          : () => ref
                .read(currentPageLabelProvider.notifier)
                .toPage(PageLabel.tools),
    );

    final texts = Column(
      crossAxisAlignment: widget.wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Brand(ink: ink),
        SizedBox(height: widget.wide ? 28 : 20),
        Text(
          title,
          style: TextStyle(
            fontSize: widget.wide ? 40 : 32,
            fontWeight: FontWeight.w800,
            height: 1.1,
            color: ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(subtitle, style: TextStyle(fontSize: 15, color: inkSoft)),
        if (exit != null && hasProfile) ...[
          const SizedBox(height: 18),
          _Pill(
            ink: ink,
            label: zh ? '出口  $exit' : 'Exit  $exit',
          ),
        ],
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: on
            ? [
                BoxShadow(
                  color: vpsCoral.withValues(alpha: 0.35),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
        children: [
          // Soft decorative circles.
          Positioned(
            right: -60,
            top: -80,
            child: _Blob(size: 260, color: ink.withValues(alpha: 0.07)),
          ),
          Positioned(
            left: -40,
            bottom: -90,
            child: _Blob(size: 200, color: ink.withValues(alpha: 0.05)),
          ),
          Padding(
            padding: EdgeInsets.all(widget.wide ? 36 : 24),
            child: widget.wide
                ? Row(
                    children: [
                      Expanded(child: texts),
                      const SizedBox(width: 24),
                      button,
                    ],
                  )
                : Column(
                    children: [texts, const SizedBox(height: 24), button],
                  ),
          ),
        ],
      ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.ink});

  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [vpsCoralSoft, vpsCoralDeep],
            ),
            border: Border.all(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: const Text(
            'V',
            style: TextStyle(
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'vps2vpn',
          style: TextStyle(
            color: ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.ink, required this.label});

  final Color ink;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// A big round power button with a breathing ring while connected.
class _PowerButton extends StatefulWidget {
  const _PowerButton({
    required this.on,
    required this.enabled,
    required this.size,
    required this.onTap,
  });

  final bool on;
  final bool enabled;
  final double size;
  final VoidCallback onTap;

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  bool _hover = false;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    if (widget.on) _pulse.repeat();
  }

  @override
  void didUpdateWidget(_PowerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.on && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final on = widget.on;
    final face = on ? const Color(0xFFFFFFFF) : vpsCoral;
    final glyph = on ? vpsCoralDeep : const Color(0xFFFFFFFF);
    final scale = _down ? 0.94 : (_hover ? 1.04 : 1.0);
    return Opacity(
      opacity: widget.enabled ? 1 : 0.45,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.enabled ? widget.onTap : null,
          child: SizedBox(
            width: size * 1.35,
            height: size * 1.35,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (on)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, _) {
                      final t = _pulse.value;
                      return Container(
                        width: size * (1 + 0.35 * t),
                        height: size * (1 + 0.35 * t),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(
                            0xFFFFFFFF,
                          ).withValues(alpha: 0.28 * (1 - t)),
                        ),
                      );
                    },
                  ),
                AnimatedScale(
                  scale: scale,
                  duration: const Duration(milliseconds: 160),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: face,
                      boxShadow: [
                        BoxShadow(
                          color: (on ? const Color(0xFF000000) : vpsCoral)
                              .withValues(alpha: on ? 0.18 : 0.45),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: CustomPaint(painter: _PowerGlyph(glyph)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerGlyph extends CustomPainter {
  _PowerGlyph(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.065
      ..strokeCap = StrokeCap.round;
    const gapAngle = math.pi / 3.2;
    canvas.drawArc(
      Rect.fromCircle(center: c.translate(0, r * 0.12), radius: r),
      -math.pi / 2 + gapAngle / 2,
      2 * math.pi - gapAngle,
      false,
      paint,
    );
    canvas.drawLine(
      c.translate(0, -r * 1.15),
      c.translate(0, -r * 0.05),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PowerGlyph oldDelegate) => oldDelegate.color != color;
}
