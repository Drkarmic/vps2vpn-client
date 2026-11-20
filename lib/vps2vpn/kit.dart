// vps2vpn design kit: palette (dark "aurora", light "minimal"), cards,
// buttons, switches, segmented control, logo and line icons.
// Everything simple mode draws comes from here, so the look stays one system.

import 'dart:math' as math;

import 'package:prism_ui/prism_ui.dart' show BuildContextExtension;
import 'package:flutter/widgets.dart';

const vpsCoral = Color(0xFFFF6F61);
const vpsCoralSoft = Color(0xFFFF8A70);
const vpsCoralDeep = Color(0xFFE63E5C);
const vpsViolet = Color(0xFF8B5CF6);

class VpsPalette {
  const VpsPalette._({
    required this.dark,
    required this.bg,
    required this.side,
    required this.card,
    required this.cardHi,
    required this.line,
    required this.text,
    required this.soft,
    required this.muted,
    required this.accent,
    required this.accentInk,
    required this.accentWash,
    required this.good,
    required this.warn,
    required this.bad,
    required this.glowA,
    required this.glowB,
  });

  final bool dark;
  final Color bg;
  final Color side;
  final Color card;
  final Color cardHi;
  final Color line;
  final Color text;
  final Color soft;
  final Color muted;
  final Color accent;
  final Color accentInk;
  final Color accentWash;
  final Color good;
  final Color warn;
  final Color bad;
  final Color glowA;
  final Color glowB;

  static const _dark = VpsPalette._(
    dark: true,
    bg: Color(0xFF0E0F1A),
    side: Color(0xFF12131F),
    card: Color(0x0FFFFFFF),
    cardHi: Color(0x1AFFFFFF),
    line: Color(0x17FFFFFF),
    text: Color(0xFFF4F4FA),
    soft: Color(0xFFA9ACCB),
    muted: Color(0xFF6B6E8F),
    accent: vpsCoralSoft,
    accentInk: Color(0xFFFFFFFF),
    accentWash: Color(0x40FF8A70),
    good: Color(0xFF6EE7B7),
    warn: Color(0xFFFCD34D),
    bad: Color(0xFFFF8A8A),
    glowA: Color(0x55FF6F61),
    glowB: Color(0x408B5CF6),
  );

  static const _light = VpsPalette._(
    dark: false,
    bg: Color(0xFFFBF8F6),
    side: Color(0xFFF5EFEC),
    card: Color(0xFFFFFFFF),
    cardHi: Color(0xFFFFF6F3),
    line: Color(0xFFEFE4E0),
    text: Color(0xFF2B1B18),
    soft: Color(0xFF8A7671),
    muted: Color(0xFFB7A6A1),
    accent: vpsCoral,
    accentInk: Color(0xFFFFFFFF),
    accentWash: Color(0xFFFFE8E3),
    good: Color(0xFF1D9E75),
    warn: Color(0xFFBA7517),
    bad: Color(0xFFD64545),
    glowA: Color(0x00000000),
    glowB: Color(0x00000000),
  );

  static VpsPalette of(BuildContext context) =>
      context.colorScheme.brightness == Brightness.dark ? _dark : _light;

  LinearGradient get accentGradient => dark
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [vpsCoralSoft, vpsCoralDeep, vpsViolet],
          stops: [0, 0.6, 1],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [vpsCoralSoft, vpsCoral, vpsCoralDeep],
        );
}

bool vpsZh(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'zh';

/// Picks the Chinese or English text by the app's language.
String tr(BuildContext context, String zh, String en) =>
    vpsZh(context) ? zh : en;

TextStyle vpsText(
  VpsPalette p, {
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
  double? spacing,
}) => TextStyle(
  fontSize: size,
  fontWeight: weight,
  color: color ?? p.text,
  height: height,
  letterSpacing: spacing,
);

/// The rounded surface every block sits on: glass in dark, paper in light.
class VpsCard extends StatelessWidget {
  const VpsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.onTap,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: highlight ? p.cardHi : p.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: highlight ? p.accent.withValues(alpha: 0.55) : p.line,
          width: highlight ? 1.4 : 1,
        ),
        boxShadow: p.dark
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF7A3B2E).withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return VpsPressable(onTap: onTap!, child: box);
  }
}

/// Hover lift + press shrink + click cursor for anything tappable.
class VpsPressable extends StatefulWidget {
  const VpsPressable({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<VpsPressable> createState() => _VpsPressableState();
}

class _VpsPressableState extends State<VpsPressable> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : (_hover ? 1.01 : 1),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A pill button: filled (accent) or quiet (outline).
class VpsButton extends StatelessWidget {
  const VpsButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final VpsIcon? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final fg = filled ? p.accentInk : p.text;
    return VpsPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          gradient: filled ? p.accentGradient : null,
          color: filled ? null : p.card,
          borderRadius: BorderRadius.circular(99),
          border: filled ? null : Border.all(color: p.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              VpsIconView(icon!, size: 17, color: fg),
              const SizedBox(width: 8),
            ],
            Text(label, style: vpsText(p, size: 14, weight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// A smooth custom switch.
class VpsSwitch extends StatelessWidget {
  const VpsSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    return VpsPressable(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 50,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          gradient: value ? p.accentGradient : null,
          color: value ? null : (p.dark ? const Color(0x26FFFFFF) : const Color(0xFFE8DDD9)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}

/// Two or three choices in one pill, the chosen one slides.
class VpsSegmented<T> extends StatelessWidget {
  const VpsSegmented({
    super.key,
    required this.items,
    required this.value,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> items;
  final T value;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final index = math.max(0, items.indexOf(value));
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 8) / items.length;
        return Container(
          height: 46,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: p.dark ? const Color(0x12FFFFFF) : const Color(0xFFF1EAE6),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: p.accentGradient,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: VpsPressable(
                        onTap: () => onChanged(item),
                        child: Center(
                          child: Text(
                            labelOf(item),
                            style: vpsText(
                              p,
                              size: 14,
                              weight: FontWeight.w600,
                              color: item == value ? p.accentInk : p.soft,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class VpsChip extends StatelessWidget {
  const VpsChip({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final c = color ?? p.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.dark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: vpsText(p, size: 12, weight: FontWeight.w600, color: c)),
    );
  }
}

/// The vps2vpn mark: a rounded tile with a "V" path rising to a point,
/// read as "your server" (the dot) feeding a secure tunnel (the V).
class VpsLogo extends StatelessWidget {
  const VpsLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: p.accentGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: vpsCoral.withValues(alpha: 0.35),
            blurRadius: size * 0.4,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: CustomPaint(painter: _LogoMark()),
    );
  }
}

class _LogoMark extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final stroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(w * 0.27, w * 0.34)
      ..lineTo(w * 0.5, w * 0.74)
      ..lineTo(w * 0.73, w * 0.34);
    canvas.drawPath(path, stroke);
    canvas.drawCircle(
      Offset(w * 0.5, w * 0.3),
      w * 0.075,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_LogoMark oldDelegate) => false;
}

/// Our own line icons, drawn so nothing looks borrowed.
enum VpsIcon { home, servers, check, me, bolt, globe, shield, refresh, paste, file, gear, info, sun, arrowUp, arrowDown, sparkle, plus, chevron }

class VpsIconView extends StatelessWidget {
  const VpsIconView(this.icon, {super.key, this.size = 22, this.color});

  final VpsIcon icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? VpsPalette.of(context).text;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _IconPainter(icon, c)),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);

  final VpsIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 24;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset o(double x, double y) => Offset(x * u, y * u);
    RRect rr(double l, double t, double r, double b, double rad) =>
        RRect.fromLTRBR(l * u, t * u, r * u, b * u, Radius.circular(rad * u));
    Path poly(List<List<double>> pts, {bool close = false}) {
      final path = Path()..moveTo(pts[0][0] * u, pts[0][1] * u);
      for (final pt in pts.skip(1)) {
        path.lineTo(pt[0] * u, pt[1] * u);
      }
      if (close) path.close();
      return path;
    }

    switch (icon) {
      case VpsIcon.home:
        canvas.drawPath(poly([[3.5, 11], [12, 4], [20.5, 11]]), p);
        canvas.drawPath(poly([[6, 9.5], [6, 20], [18, 20], [18, 9.5]]), p);
        canvas.drawLine(o(10, 20), o(10, 15), p);
        canvas.drawLine(o(14, 20), o(14, 15), p);
        canvas.drawLine(o(10, 15), o(14, 15), p);
      case VpsIcon.servers:
        canvas.drawRRect(rr(4, 4, 20, 10.5, 2.5), p);
        canvas.drawRRect(rr(4, 13.5, 20, 20, 2.5), p);
        canvas.drawCircle(o(7.5, 7.25), 0.9 * u, p..style = PaintingStyle.fill);
        canvas.drawCircle(o(7.5, 16.75), 0.9 * u, p);
        p.style = PaintingStyle.stroke;
        canvas.drawLine(o(12, 7.25), o(16.5, 7.25), p);
        canvas.drawLine(o(12, 16.75), o(16.5, 16.75), p);
      case VpsIcon.check:
        canvas.drawPath(
          poly([[12, 3], [19.5, 6], [19.5, 12], [12, 21], [4.5, 12], [4.5, 6]], close: true),
          p,
        );
        canvas.drawPath(poly([[8.5, 12], [11, 14.5], [15.5, 9.5]]), p);
      case VpsIcon.me:
        canvas.drawCircle(o(12, 8.5), 3.8 * u, p);
        canvas.drawArc(Rect.fromLTRB(4.5 * u, 14 * u, 19.5 * u, 28 * u), math.pi * 1.08, math.pi * 0.84, false, p);
      case VpsIcon.bolt:
        canvas.drawPath(poly([[13, 3], [5.5, 13.5], [11.5, 13.5], [10.5, 21], [18.5, 10.5], [12.5, 10.5]], close: true), p);
      case VpsIcon.globe:
        canvas.drawCircle(o(12, 12), 8.5 * u, p);
        canvas.drawOval(Rect.fromLTRB(8 * u, 3.5 * u, 16 * u, 20.5 * u), p);
        canvas.drawLine(o(3.5, 12), o(20.5, 12), p);
      case VpsIcon.shield:
        canvas.drawPath(poly([[12, 3], [19.5, 6], [19.5, 12], [12, 21], [4.5, 12], [4.5, 6]], close: true), p);
      case VpsIcon.refresh:
        canvas.drawArc(Rect.fromCircle(center: o(12, 12), radius: 7.5 * u), -math.pi * 0.35, math.pi * 1.6, false, p);
        canvas.drawPath(poly([[17.5, 3.5], [18.2, 7.6], [14, 8]]), p);
      case VpsIcon.paste:
        canvas.drawRRect(rr(5, 5, 19, 21, 2.5), p);
        canvas.drawRRect(rr(9, 3, 15, 7, 1.5), p);
        canvas.drawLine(o(9, 12), o(15, 12), p);
        canvas.drawLine(o(9, 16), o(13, 16), p);
      case VpsIcon.file:
        canvas.drawPath(poly([[6, 3], [14, 3], [19, 8], [19, 21], [6, 21]], close: true), p);
        canvas.drawPath(poly([[14, 3], [14, 8], [19, 8]]), p);
      case VpsIcon.gear:
        canvas.drawCircle(o(12, 12), 3 * u, p);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(
            o(12 + 6 * math.cos(a), 12 + 6 * math.sin(a)),
            o(12 + 8.5 * math.cos(a), 12 + 8.5 * math.sin(a)),
            p,
          );
        }
        canvas.drawCircle(o(12, 12), 6 * u, p);
      case VpsIcon.info:
        canvas.drawCircle(o(12, 12), 8.5 * u, p);
        canvas.drawLine(o(12, 11), o(12, 16.5), p);
        canvas.drawCircle(o(12, 7.8), 0.6 * u, p);
      case VpsIcon.sun:
        canvas.drawCircle(o(12, 12), 4 * u, p);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(
            o(12 + 6.5 * math.cos(a), 12 + 6.5 * math.sin(a)),
            o(12 + 8.5 * math.cos(a), 12 + 8.5 * math.sin(a)),
            p,
          );
        }
      case VpsIcon.arrowUp:
        canvas.drawLine(o(12, 19), o(12, 5), p);
        canvas.drawPath(poly([[6.5, 10.5], [12, 5], [17.5, 10.5]]), p);
      case VpsIcon.arrowDown:
        canvas.drawLine(o(12, 5), o(12, 19), p);
        canvas.drawPath(poly([[6.5, 13.5], [12, 19], [17.5, 13.5]]), p);
      case VpsIcon.sparkle:
        canvas.drawPath(poly([[12, 3], [13.8, 10.2], [21, 12], [13.8, 13.8], [12, 21], [10.2, 13.8], [3, 12], [10.2, 10.2]], close: true), p);
      case VpsIcon.plus:
        canvas.drawLine(o(12, 5), o(12, 19), p);
        canvas.drawLine(o(5, 12), o(19, 12), p);
      case VpsIcon.chevron:
        canvas.drawPath(poly([[9, 5], [16, 12], [9, 19]]), p);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.icon != icon || old.color != color;
}

/// The background: deep night with two soft glows (dark) or warm paper (light).
class VpsBackdrop extends StatelessWidget {
  const VpsBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    return ColoredBox(
      color: p.bg,
      child: Stack(
        children: [
          if (p.dark) ...[
            Positioned(
              top: -220,
              right: -160,
              child: _Glow(color: p.glowA, size: 640),
            ),
            Positioned(
              bottom: -260,
              left: 80,
              child: _Glow(color: p.glowB, size: 620),
            ),
          ],
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class VpsSectionTitle extends StatelessWidget {
  const VpsSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: vpsText(p, size: 13, weight: FontWeight.w600, color: p.soft, spacing: 0.6)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A settings-style row inside a card.
class VpsRow extends StatelessWidget {
  const VpsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final VpsIcon icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: p.accentWash,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: VpsIconView(icon, size: 19, color: p.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: vpsText(p, size: 15, weight: FontWeight.w600)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: vpsText(p, size: 12.5, color: p.soft)),
                  ),
              ],
            ),
          ),
          trailing ?? (onTap != null ? VpsIconView(VpsIcon.chevron, size: 18, color: p.muted) : const SizedBox()),
        ],
      ),
    );
    if (onTap == null) return row;
    return VpsPressable(onTap: onTap!, child: row);
  }
}
