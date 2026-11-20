// vps2vpn "Me": your subscriptions, look and language, and the door to
// advanced mode.

import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/vps2vpn/kit.dart';
import 'package:fl_clash/vps2vpn/shell.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' show ThemeMode;

class VpsMePage extends ConsumerStatefulWidget {
  const VpsMePage({super.key});

  @override
  ConsumerState<VpsMePage> createState() => _VpsMePageState();
}

class _VpsMePageState extends ConsumerState<VpsMePage> {
  String? _note;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    final ok = text.startsWith('http://') || text.startsWith('https://') || text.contains('://');
    if (!ok) {
      setState(() => _note = tr(context, '剪贴板里没有订阅链接。先在部署工具里点「复制订阅链接」。',
          'No subscription link on the clipboard. Copy it from the deploy tool first.'));
      return;
    }
    setState(() => _note = null);
    await ref.read(profilesActionProvider.notifier).addProfileFromLink(text);
  }

  @override
  Widget build(BuildContext context) {
    final p = VpsPalette.of(context);
    final profiles = ref.watch(profilesProvider);
    final currentId = ref.watch(currentProfileIdProvider);
    final themeMode = ref.watch(themeSettingProvider.select((s) => s.themeMode));
    final locale = ref.watch(appSettingProvider.select((s) => s.locale));
    final autoLaunch = ref.watch(appSettingProvider.select((s) => s.autoLaunch));
    final advanced = ref.watch(appSettingProvider.select((s) => s.advancedMode));

    return VpsPage(
      title: tr(context, '我的', 'Me'),
      subtitle: tr(context, '订阅、外观和设置', 'Subscriptions, look and settings'),
      children: [
        VpsSectionTitle(
          tr(context, '我的订阅', 'Subscriptions'),
          trailing: profiles.isEmpty
              ? null
              : VpsPressable(
                  onTap: () => ref.read(profilesActionProvider.notifier).updateProfiles(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VpsIconView(VpsIcon.refresh, size: 15, color: p.accent),
                      const SizedBox(width: 5),
                      Text(tr(context, '全部更新', 'Update all'), style: vpsText(p, size: 13, weight: FontWeight.w700, color: p.accent)),
                    ],
                  ),
                ),
        ),
        for (final profile in profiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProfileCard(
              profile: profile,
              selected: profile.id == currentId,
              onTap: () => ref.read(currentProfileIdProvider.notifier).value = profile.id,
              onUpdate: () => ref.read(profilesActionProvider.notifier).updateProfile(profile, showLoading: true),
            ),
          ),
        VpsCard(
          highlight: profiles.isEmpty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profiles.isEmpty ? tr(context, '添加你的服务器', 'Add your server') : tr(context, '再添加一个', 'Add another'),
                style: vpsText(p, size: 16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                tr(context, '在部署工具里复制订阅链接，然后点下面的按钮', 'Copy the subscription link from the deploy tool, then tap below'),
                style: vpsText(p, size: 13, color: p.soft),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  VpsButton(label: tr(context, '粘贴订阅链接', 'Paste link'), icon: VpsIcon.paste, filled: true, onTap: _paste),
                  VpsButton(
                    label: tr(context, '从文件导入', 'From file'),
                    icon: VpsIcon.file,
                    onTap: () => ref.read(profilesActionProvider.notifier).addProfileFormFile(),
                  ),
                ],
              ),
              if (_note != null) ...[
                const SizedBox(height: 10),
                Text(_note!, style: vpsText(p, size: 12.5, color: p.warn)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        VpsSectionTitle(tr(context, '外观', 'Appearance')),
        VpsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VpsSegmented<ThemeMode>(
                items: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
                value: themeMode,
                labelOf: (m) => switch (m) {
                  ThemeMode.system => tr(context, '跟随系统', 'System'),
                  ThemeMode.light => tr(context, '明亮', 'Light'),
                  ThemeMode.dark => tr(context, '深色极光', 'Aurora dark'),
                },
                onChanged: (m) => ref.read(themeSettingProvider.notifier).update((s) => s.copyWith(themeMode: m)),
              ),
              const SizedBox(height: 14),
              VpsSegmented<String?>(
                items: const [null, 'zh', 'en'],
                value: locale == null ? null : (locale.startsWith('zh') ? 'zh' : (locale.startsWith('en') ? 'en' : null)),
                labelOf: (l) => switch (l) {
                  'zh' => '中文',
                  'en' => 'English',
                  _ => tr(context, '系统语言', 'System language'),
                },
                onChanged: (l) => ref.read(appSettingProvider.notifier).update((s) => s.copyWith(locale: l)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        VpsSectionTitle(tr(context, '设置', 'Settings')),
        VpsCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Column(
            children: [
              VpsRow(
                icon: VpsIcon.sun,
                title: tr(context, '开机自动启动', 'Start with Windows'),
                trailing: VpsSwitch(
                  value: autoLaunch,
                  onChanged: (v) => ref.read(appSettingProvider.notifier).update((s) => s.copyWith(autoLaunch: v)),
                ),
              ),
              Container(height: 1, color: p.line),
              VpsRow(
                icon: VpsIcon.gear,
                title: tr(context, '高级模式', 'Advanced mode'),
                subtitle: tr(context, '显示全部页面和专业设置（给懂行的人）', 'Every page and expert setting'),
                trailing: VpsSwitch(
                  value: advanced,
                  onChanged: (v) => ref.read(appSettingProvider.notifier).update((s) => s.copyWith(advancedMode: v)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        VpsCard(
          child: Row(
            children: [
              const VpsLogo(size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('vps2vpn  v${globalState.packageInfo.version}', style: vpsText(p, size: 15, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      tr(context, '基于开源项目 FlClash（GPL-3.0）和 mihomo 内核', 'Built on FlClash (GPL-3.0) and the mihomo core'),
                      style: vpsText(p, size: 12.5, color: p.soft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.profile, required this.selected, required this.onTap, required this.onUpdate});

  final Profile profile;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = VpsPalette.of(context);
    final sub = profile.subscriptionInfo;
    final used = sub == null ? 0 : sub.upload + sub.download;
    final total = sub?.total ?? 0;
    final ratio = total > 0 ? math.min(1.0, used / total) : 0.0;
    String? expire;
    if (sub != null && sub.expire > 0) {
      final d = DateTime.fromMillisecondsSinceEpoch(sub.expire * 1000);
      expire = tr(context, '${d.year}-${_two(d.month)}-${_two(d.day)} 到期', 'Expires ${d.year}-${_two(d.month)}-${_two(d.day)}');
    }
    final updated = profile.lastUpdateDate;
    return VpsCard(
      onTap: onTap,
      highlight: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: selected ? p.accentGradient : null,
                  color: selected ? null : p.accentWash,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: VpsIconView(VpsIcon.servers, size: 19, color: selected ? p.accentInk : p.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.realLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: vpsText(p, size: 15.5, weight: FontWeight.w700)),
                    Text(
                      [
                        if (selected) tr(context, '正在使用', 'In use'),
                        if (updated != null) tr(context, '${_ago(context, updated)}更新', 'updated ${_ago(context, updated)}'),
                      ].join(' · '),
                      style: vpsText(p, size: 12.5, color: selected ? p.accent : p.soft),
                    ),
                  ],
                ),
              ),
              if (profile.url.isNotEmpty)
                VpsPressable(
                  onTap: onUpdate,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: VpsIconView(VpsIcon.refresh, size: 18, color: p.soft),
                  ),
                ),
            ],
          ),
          if (total > 0 || expire != null) ...[
            const SizedBox(height: 14),
            if (total > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 6,
                  child: Stack(
                    children: [
                      Container(color: p.line),
                      FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(decoration: BoxDecoration(gradient: p.accentGradient)),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (total > 0)
                  Text(
                    tr(context, '已用 ${used.traffic.show} / ${total.traffic.show}', '${used.traffic.show} of ${total.traffic.show} used'),
                    style: vpsText(p, size: 12.5, color: p.soft),
                  ),
                const Spacer(),
                if (expire != null) Text(expire, style: vpsText(p, size: 12.5, color: p.soft)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

String _ago(BuildContext context, DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr(context, '刚刚', 'just now');
  if (d.inHours < 1) return tr(context, '${d.inMinutes} 分钟前', '${d.inMinutes} min ago');
  if (d.inDays < 1) return tr(context, '${d.inHours} 小时前', '${d.inHours} h ago');
  return tr(context, '${d.inDays} 天前', '${d.inDays} d ago');
}
