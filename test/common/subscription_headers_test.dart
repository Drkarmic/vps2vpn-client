import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:flutter_test/flutter_test.dart';

String? _text(String? raw, [int maxLength = 200]) =>
    subscriptionHeaderText(raw, maxLength: maxLength);

void main() {
  group('subscriptionHeaderText', () {
    test('keeps plain text and folds whitespace into single spaces', () {
      expect(
        _text('  Account\tstopped:\r\n  renew   now '),
        'Account stopped: renew now',
      );
      expect(_text(null), isNull);
      expect(_text('   '), isNull);
    });

    test('decodes a base64: prefixed UTF-8 value', () {
      final encoded = base64.encode(utf8.encode('账户已停用，请续费'));
      expect(_text('base64:$encoded'), '账户已停用，请续费');
      expect(_text('BASE64: $encoded'), '账户已停用，请续费');
      final urlSafe = base64Url
          .encode(utf8.encode('???>>>'))
          .replaceAll('=', '');
      expect(_text('base64:$urlSafe'), '???>>>');
    });

    test('drops a base64 value that is not valid base64 or UTF-8', () {
      expect(_text('base64:@@@not base64@@@'), isNull);
      expect(_text('base64:${base64.encode([0xff, 0xfe])}'), isNull);
      expect(_text('base64:'), isNull);
    });

    test('reads raw UTF-8 bytes that arrived as Latin-1', () {
      final mojibake = latin1.decode(utf8.encode('我的机场'));
      expect(_text(mojibake), '我的机场');
      expect(_text('Café'), 'Café');
    });

    test('strips control, zero-width and bidi override characters', () {
      expect(_text('Pay\u202Etxt.exe\u202C now'), 'Paytxt.exe now');
      expect(_text('a\u0000b\u0007c\u200Bd\uFEFFe\u2066f'), 'abcdef');
      expect(_text('\u0085\u2028line\u2029two'), 'line two');
    });

    test('caps the text at maxLength characters without a dangling space', () {
      expect(_text('abcdef', 3), 'abc');
      expect(_text('ab cdef', 3), 'ab');
      expect(_text('😀😀😀😀', 2), '😀😀');
    });

    test('ignores a header longer than the read limit', () {
      expect(_text('a' * (maxSubscriptionHeaderLength + 1)), isNull);
      expect(_text('a' * maxSubscriptionHeaderLength, 10), 'a' * 10);
    });
  });

  group('subscriptionHeaderLink', () {
    test('accepts http, https and tg links', () {
      expect(
        subscriptionHeaderLink(' https://panel.example/u/abc ').toString(),
        'https://panel.example/u/abc',
      );
      expect(subscriptionHeaderLink('http://panel.example'), isNotNull);
      expect(
        subscriptionHeaderLink('tg://resolve?domain=support').toString(),
        'tg://resolve?domain=support',
      );
      expect(subscriptionHeaderLink('HTTPS://Panel.example/x'), isNotNull);
    });

    test('refuses other schemes, credentials and hostless links', () {
      for (final raw in [
        null,
        '',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'data:text/html,hi',
        'intent://x#Intent;end',
        'ms-settings:privacy',
        'https://bank.example@evil.example/',
        'https:///path',
        'tg:resolve',
        '/relative/path',
      ]) {
        expect(subscriptionHeaderLink(raw), isNull, reason: raw);
      }
    });

    test('refuses spaces, control and non-ASCII characters', () {
      expect(subscriptionHeaderLink('https://a.example/x y'), isNull);
      expect(subscriptionHeaderLink('https://a.example/\u0000'), isNull);
      expect(subscriptionHeaderLink('https://pаypal.example'), isNull);
      expect(subscriptionHeaderLink('https://a.example/\u202E'), isNull);
    });

    test('refuses a link longer than the url input limit', () {
      final path = 'a' * TextInputLimits.url;
      expect(subscriptionHeaderLink('https://a.example/$path'), isNull);
    });
  });

  group('subscriptionUpdateIntervalHours', () {
    test('reads positive whole hours and caps them at a week', () {
      expect(subscriptionUpdateIntervalHours(' 12 '), 12);
      expect(subscriptionUpdateIntervalHours('1'), 1);
      expect(subscriptionUpdateIntervalHours('100000'), 168);
    });

    test('ignores zero, negative, fractional and oversized values', () {
      for (final raw in [null, '', '0', '-5', '1.5', 'soon', '9' * 40]) {
        expect(subscriptionUpdateIntervalHours(raw), isNull, reason: raw);
      }
    });
  });
}
