import 'dart:io';

import 'package:fl_clash/vps2vpn/panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('valid member and AI timestamps preserve their exact seconds', () {
    final member = VpsMember.fromJson({
      'name': 'Ann',
      'enabled': true,
      'used_up': 12,
      'used_down': 34,
      'quota_gb': 10,
      'expire_at': 1893456000,
      'ai': {'at': 1893456000, 'summary': 'ok'},
    });
    expect(member.used, 46);
    expect(member.quotaGb, 10);
    expect(member.unlimited, isFalse);
    expect(member.expireAt!.millisecondsSinceEpoch, 1893456000000);
    expect(member.ai!.at!.millisecondsSinceEpoch, 1893456000000);
  });

  test('malformed remote timestamps cannot break the member view', () {
    for (final bad in <Object?>[
      null,
      -1,
      0,
      '1893456000',
      8640000000001,
      1e300,
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ]) {
      final member = VpsMember.fromJson({
        'name': 'Ann',
        'enabled': true,
        'expire_at': bad,
        'ai': {'at': bad, 'summary': 'still usable'},
      });
      expect(member.expireAt, isNull, reason: 'expire_at=$bad');
      expect(member.ai, isNotNull, reason: 'ai response must remain usable');
      expect(member.ai!.at, isNull, reason: 'ai.at=$bad');
    }
  });

  test('timestamps near the documented DateTime limit stay bounded', () {
    final valid = VpsAiStatus.fromJson({'at': 8640000000000 - 1})!;
    final invalid = VpsAiStatus.fromJson({'at': 8640000000000 + 1})!;
    expect(valid.at, isNotNull);
    expect(invalid.at, isNull);
  });

  test('invalid usage and quota values never become non-finite state', () {
    final member = VpsMember.fromJson({
      'name': 'Ann',
      'enabled': true,
      'used_up': double.infinity,
      'used_down': double.nan,
      'quota_gb': double.infinity,
      'quota_eff': double.nan,
    });
    expect(member.used, 0);
    expect(member.quotaGb, 0);
    expect(member.unlimited, isTrue);

    final valid = VpsMember.fromJson({
      'name': 'Ann',
      'enabled': true,
      'used_up': 100,
      'used_down': 900,
      'quota_gb': 15,
    });
    expect(valid.used, 1000);
    expect(valid.unlimited, isFalse);
  });

  test('a valid HTTP-200 JSON with a huge timestamp remains parseable', () {
    const payload =
        '{"name":"Ann","enabled":true,"expire_at":1e300,'
        '"used_up":42,"ai":{"at":1e300,"summary":"ok"}}';
    final result = VpsMemberResult.fromResponse(
      Uri.parse('https://panel.example/s/token/api/'),
      HttpStatus.ok,
      payload,
    );
    expect(result.member, isNotNull);
    expect(result.member!.name, 'Ann');
    expect(result.member!.expireAt, isNull);
    expect(result.member!.ai!.at, isNull);
    expect(result.member!.used, 42);
  });
}
