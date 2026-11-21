import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' show BannerLevel;
import 'package:url_launcher/url_launcher.dart';

const maxSubscriptionHeaderLength = 8192;

const maxSubscriptionTitleLength = TextInputLimits.name;

const maxSubscriptionAnnounceLength = 200;

const maxSubscriptionUpdateIntervalHours = 168;

const _base64Prefix = 'base64:';

const _linkSchemes = {'http', 'https', 'tg'};

/// A `base64:` prefix marks UTF-8 text encoded in base64.
String? subscriptionHeaderText(String? raw, {required int maxLength}) {
  if (raw == null || raw.length > maxSubscriptionHeaderLength) return null;
  var value = raw.trim();
  if (value.length >= _base64Prefix.length &&
      value.substring(0, _base64Prefix.length).toLowerCase() == _base64Prefix) {
    try {
      final encoded = value.substring(_base64Prefix.length).trim();
      value = utf8.decode(base64.decode(base64.normalize(encoded)));
    } on FormatException {
      return null;
    }
  } else {
    value = _utf8FromLatin1(value);
  }
  final buffer = StringBuffer();
  var pendingSpace = false;
  var length = 0;
  for (final rune in value.runes) {
    if (_isSpace(rune)) {
      pendingSpace = buffer.isNotEmpty;
      continue;
    }
    if (_isHidden(rune)) continue;
    if (length + (pendingSpace ? 1 : 0) >= maxLength) break;
    if (pendingSpace) {
      buffer.write(' ');
      length++;
      pendingSpace = false;
    }
    buffer.writeCharCode(rune);
    length++;
  }
  return buffer.isEmpty ? null : buffer.toString();
}

/// HTTP hands header bytes over as Latin-1; a title sent as raw UTF-8 reads
/// back right only once the bytes are decoded again.
String _utf8FromLatin1(String value) {
  if (!value.codeUnits.any((unit) => unit > 0x7f) ||
      value.codeUnits.any((unit) => unit > 0xff)) {
    return value;
  }
  try {
    return utf8.decode(latin1.encode(value));
  } on FormatException {
    return value;
  }
}

bool _isSpace(int rune) =>
    rune == 0x20 ||
    (rune >= 0x09 && rune <= 0x0d) ||
    rune == 0x85 ||
    rune == 0xa0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200a) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202f ||
    rune == 0x205f ||
    rune == 0x3000;

/// Control, format and bidi characters can hide or reorder what text says.
bool _isHidden(int rune) =>
    rune < 0x20 ||
    (rune >= 0x7f && rune <= 0x9f) ||
    rune == 0xad ||
    rune == 0x061c ||
    (rune >= 0x200b && rune <= 0x200f) ||
    (rune >= 0x202a && rune <= 0x202e) ||
    (rune >= 0x2060 && rune <= 0x206f) ||
    rune == 0xfeff ||
    (rune >= 0xfff9 && rune <= 0xfffb) ||
    (rune >= 0xe0000 && rune <= 0xe007f);

/// [raw] as an http, https or tg link, or null. Links carrying credentials,
/// spaces or non-ASCII characters are refused, so what is shown is what opens.
Uri? subscriptionHeaderLink(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty ||
      value.length > TextInputLimits.url ||
      value.codeUnits.any((unit) => unit <= 0x20 || unit >= 0x7f)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !_linkSchemes.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

int? subscriptionUpdateIntervalHours(String? raw) {
  if (raw == null || raw.length > TextInputLimits.interval + 2) return null;
  final hours = int.tryParse(raw.trim());
  if (hours == null || hours <= 0) return null;
  return hours > maxSubscriptionUpdateIntervalHours
      ? maxSubscriptionUpdateIntervalHours
      : hours;
}

Future<void> openSubscriptionLink(String? raw) async {
  final uri = subscriptionHeaderLink(raw);
  if (uri == null) return;
  final appLocalizations = currentAppLocalizations;
  final confirmed = await dialogs.showMessage(
    title: appLocalizations.externalLink,
    message: TextSpan(text: uri.toString()),
    confirmText: appLocalizations.go,
  );
  if (confirmed != true) return;
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    dialogs.showBanner(
      appLocalizations.subscriptionLinkOpenFailed,
      level: BannerLevel.warning,
    );
  }
}
