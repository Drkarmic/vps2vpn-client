import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/vps2vpn/update_signing.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

// A throwaway key (not the release key), and a signature openssl made with it:
//   sign-update.sh -k test.pem vps2vpn-1.0.9-windows-amd64-setup.exe
const _testKey =
    'f5be85b6ef9f1a0df2c79f83de5af4b290597411d85f7271acddf4a547a9dc78';
const _testName = 'vps2vpn-1.0.9-windows-amd64-setup.exe';
const _testSha =
    'e34210a6de4f653edf588301431c3d69a633638cbf587345cc50a7fed9f38f4c';
const _testSig =
    '2u+w7rIKiMDKVATVOXCCzn3LxZVxnysJpBu4aECzPZdAeHB+otPdQBSIzuCKGKmYNF1nj9aLcsWPx7OLFPhwCw==';

void main() {
  group('RFC 8032 test vectors', () {
    final vectors = [
      (
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
        '',
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      ),
      (
        '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
        '72',
        '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
      ),
      (
        'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025',
        'af82',
        '6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a',
      ),
    ];
    for (final (i, (key, msg, sig)) in vectors.indexed) {
      test('vector ${i + 1} verifies, and fails once altered', () {
        expect(ed25519Verify(_hex(key), _hex(msg), _hex(sig)), isTrue);
        final bad = _hex(sig)..[10] ^= 1;
        expect(ed25519Verify(_hex(key), _hex(msg), bad), isFalse);
        expect(
          ed25519Verify(
            _hex(key),
            Uint8List.fromList([..._hex(msg), 0]),
            _hex(sig),
          ),
          isFalse,
        );
      });
    }

    test('a non-canonical S (S + L) is refused', () {
      final key = _hex(vectors[0].$1);
      final sig = _hex(vectors[0].$3);
      var s = BigInt.zero;
      for (var i = 63; i >= 32; i--) {
        s = (s << 8) | BigInt.from(sig[i]);
      }
      s +=
          (BigInt.one << 252) +
          BigInt.parse('27742317777372353535851937790883648493');
      for (var i = 32; i < 64; i++) {
        sig[i] = (s & BigInt.from(0xff)).toInt();
        s >>= 8;
      }
      expect(ed25519Verify(key, Uint8List(0), sig), isFalse);
    });
  });

  group('update signature', () {
    bool check({
      String name = _testName,
      String sha = _testSha,
      int size = 15,
      String sig = _testSig,
      String key = _testKey,
    }) => vpsVerifyUpdate(
      fileName: name,
      sha256Hex: sha,
      size: size,
      signatureText: sig,
      publicKeyHex: key,
    );

    test('an openssl signature by the key verifies', () {
      expect(check(), isTrue);
      expect(check(sig: '$_testSig\n'), isTrue);
      expect(check(sha: _testSha.toUpperCase()), isTrue);
    });

    test('any other file, size, name or key does not', () {
      expect(check(sha: '0' * 64), isFalse);
      expect(check(size: 16), isFalse);
      expect(check(name: 'vps2vpn-9.9.9-windows-amd64-setup.exe'), isFalse);
      expect(check(key: vpsUpdatePublicKeyHex), isFalse);
      expect(check(sig: 'not base64!'), isFalse);
      expect(check(sig: base64.encode(List.filled(63, 0))), isFalse);
      expect(check(key: 'zz'), isFalse);
    });

    test('the built-in key is the release key', () {
      // signed with the release key itself (a 0.0.0 file is never newer)
      expect(
        vpsVerifyUpdate(
          fileName: 'vps2vpn-0.0.0-test.exe',
          sha256Hex:
              'd3fb5b4cf03d8c372b2dec50e4dac7699f086d4b73ceb3ee1338eabf41a61b40',
          size: 21,
          signatureText:
              'mNGxD55mXhuAwewqGnarY93XU7XSFB9w6OpAQy2ZyFA5gf76A/Bb9+URsIcCI5Q8PezdtLeGWJB3lvsCofhdBg==',
        ),
        isTrue,
      );
      // a garbage signature fails cleanly instead of throwing
      expect(
        check(
          key: vpsUpdatePublicKeyHex,
          sig: base64.encode(List.filled(64, 7)),
        ),
        isFalse,
      );
    });
  });

  test('version from an installer name', () {
    expect(
      vpsUpdateFileVersion('vps2vpn-1.0.8-windows-amd64-setup.exe'),
      '1.0.8',
    );
    expect(vpsUpdateFileVersion('vps2vpn-v1.2-android.apk'), '1.2');
    expect(
      vpsUpdateFileVersion('vps2vpn-rs-1.11.0-android-arm64.apk'),
      '1.11.0',
    );
    expect(vpsUpdateFileVersion('other-1.0.8.exe'), isNull);
    expect(vpsUpdateFileVersion('vps2vpn-windows.exe'), isNull);
  });
}
