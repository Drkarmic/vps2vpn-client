// vps2vpn update signatures: an installer the panel offers is only kept when
// `<installer>.sig` holds an Ed25519 signature, by the release key below, over
//   "vps2vpn-update-v1\n<file name>\n<sha256 hex>\n<size in bytes>\n"
// (tool/sign_update.sh writes it). The panel, its
// TLS certificate or the download link can all be replaced by whoever owns
// the server; the release key cannot.
//
// Verification only, after RFC 8032 section 5.1.7, on Dart's BigInt: no new
// dependency for one check per update, and speed does not matter here.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The release key's Ed25519 public key (32 bytes, hex).
const vpsUpdatePublicKeyHex =
    '39f3a52a75eaf2175a8e3c7f8e0d3c2b2a6dcea45a6e97a878864a61d9e7f7b5';

/// The text an update signature covers.
String vpsUpdateStatement(String fileName, String sha256Hex, int size) =>
    'vps2vpn-update-v1\n$fileName\n${sha256Hex.toLowerCase()}\n$size\n';

/// True when [signatureText] (base64 of 64 bytes, as in a `.sig` file) is the
/// release key's signature for this file. Anything malformed is false.
bool vpsVerifyUpdate({
  required String fileName,
  required String sha256Hex,
  required int size,
  required String signatureText,
  String publicKeyHex = vpsUpdatePublicKeyHex,
}) {
  final Uint8List signature;
  try {
    signature = base64.decode(signatureText.trim());
  } on FormatException {
    return false;
  }
  final key = _hex(publicKeyHex);
  if (key == null) return false;
  return ed25519Verify(
    key,
    Uint8List.fromList(
      utf8.encode(vpsUpdateStatement(fileName, sha256Hex, size)),
    ),
    signature,
  );
}

/// The version in an installer's file name (`vps2vpn-1.0.8-windows-…`,
/// `vps2vpn-v1.0.8-…`, `vps2vpn-rs-1.0.8-…`), or null.
String? vpsUpdateFileVersion(String fileName) {
  final m = RegExp(
    r'^vps2vpn-(?:(?:dev|rs)-)?v?(\d+(?:\.\d+){0,3})(?=[-.])',
  ).firstMatch(fileName);
  return m?.group(1);
}

Uint8List? _hex(String text) {
  if (text.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(text)) {
    return null;
  }
  return Uint8List.fromList([
    for (var i = 0; i < text.length; i += 2)
      int.parse(text.substring(i, i + 2), radix: 16),
  ]);
}

// --- Ed25519 (RFC 8032), verification only -----------------------------------

final _p = (BigInt.one << 255) - BigInt.from(19);
final _q =
    (BigInt.one << 252) +
    BigInt.parse('27742317777372353535851937790883648493');
final _d = (BigInt.from(-121665) * BigInt.from(121666).modInverse(_p)) % _p;
final _sqrtM1 = BigInt.two.modPow((_p - BigInt.one) ~/ BigInt.from(4), _p);
final _two = BigInt.two;

typedef _Point = (BigInt, BigInt, BigInt, BigInt); // extended (X, Y, Z, T)

final _Point _base = () {
  final y = (BigInt.from(4) * BigInt.from(5).modInverse(_p)) % _p;
  final x = _recoverX(y, 0)!;
  return (x, y, BigInt.one, (x * y) % _p);
}();

final _Point _identity = (BigInt.zero, BigInt.one, BigInt.one, BigInt.zero);

BigInt? _recoverX(BigInt y, int sign) {
  if (y >= _p) return null;
  final x2 =
      ((y * y - BigInt.one) * ((_d * y * y + BigInt.one) % _p).modInverse(_p)) %
      _p;
  if (x2 == BigInt.zero) return sign == 1 ? null : BigInt.zero;
  var x = x2.modPow((_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
  if ((x * x - x2) % _p != BigInt.zero) x = (x * _sqrtM1) % _p;
  if ((x * x - x2) % _p != BigInt.zero) return null;
  if ((x & BigInt.one).toInt() != sign) x = _p - x;
  return x;
}

_Point _add(_Point a, _Point b) {
  final (x1, y1, z1, t1) = a;
  final (x2, y2, z2, t2) = b;
  final aa = ((y1 - x1) * (y2 - x2)) % _p;
  final bb = ((y1 + x1) * (y2 + x2)) % _p;
  final cc = (_two * t1 * t2 * _d) % _p;
  final dd = (_two * z1 * z2) % _p;
  final e = bb - aa, f = dd - cc, g = dd + cc, h = bb + aa;
  return ((e * f) % _p, (g * h) % _p, (f * g) % _p, (e * h) % _p);
}

_Point _mul(BigInt s, _Point point) {
  var result = _identity;
  var addend = point;
  while (s > BigInt.zero) {
    if ((s & BigInt.one) == BigInt.one) result = _add(result, addend);
    addend = _add(addend, addend);
    s >>= 1;
  }
  return result;
}

bool _equal(_Point a, _Point b) {
  final (x1, y1, z1, _) = a;
  final (x2, y2, z2, _) = b;
  return (x1 * z2 - x2 * z1) % _p == BigInt.zero &&
      (y1 * z2 - y2 * z1) % _p == BigInt.zero;
}

BigInt _littleEndian(List<int> bytes) {
  var n = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    n = (n << 8) | BigInt.from(bytes[i]);
  }
  return n;
}

_Point? _decompress(List<int> bytes) {
  if (bytes.length != 32) return null;
  var y = _littleEndian(bytes);
  final sign = (y >> 255).toInt();
  y &= (BigInt.one << 255) - BigInt.one;
  final x = _recoverX(y, sign);
  if (x == null) return null;
  return (x, y, BigInt.one, (x * y) % _p);
}

/// Ed25519 signature check (RFC 8032 5.1.7). Rejects a non-canonical S.
bool ed25519Verify(
  Uint8List publicKey,
  Uint8List message,
  Uint8List signature,
) {
  if (publicKey.length != 32 || signature.length != 64) return false;
  final a = _decompress(publicKey);
  if (a == null) return false;
  final rBytes = signature.sublist(0, 32);
  final r = _decompress(rBytes);
  if (r == null) return false;
  final s = _littleEndian(signature.sublist(32));
  if (s >= _q) return false;
  final digest = sha512.convert([...rBytes, ...publicKey, ...message]).bytes;
  final h = _littleEndian(digest) % _q;
  return _equal(_mul(s, _base), _add(r, _mul(h, a)));
}
