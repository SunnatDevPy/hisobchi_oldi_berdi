import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Compile-time flag passed by `build_aab.ps1` via `--dart-define=PLAY_STORE=true`.
const bool kIsPlayStoreBuild = bool.fromEnvironment(
  'PLAY_STORE',
  defaultValue: false,
);

/// Pure-Dart FIPS 180-4 SHA-256 digest & salted PIN hashing utilities.
class AppPinHasher {
  static const String prefix = 'sha256v1:';
  static const int _rounds = 5000;

  static final List<int> _primes = _firstNPrimes(64);
  static final List<int> _initH = List<int>.unmodifiable(
    List<int>.generate(8, (i) => _fracBits(math.sqrt(_primes[i]))),
  );
  static final List<int> _roundK = List<int>.unmodifiable(
    List<int>.generate(64, (i) => _fracBits(math.pow(_primes[i], 1.0 / 3.0))),
  );

  static int _fracBits(num value) {
    final frac = value.toDouble() - value.floorToDouble();
    return (frac * 4294967296.0).floor() & 0xFFFFFFFF;
  }

  static List<int> _firstNPrimes(int count) {
    final out = <int>[];
    var n = 2;
    while (out.length < count) {
      var prime = true;
      for (var d = 2; d * d <= n; d++) {
        if (n % d == 0) {
          prime = false;
          break;
        }
      }
      if (prime) out.add(n);
      n++;
    }
    return out;
  }

  static int _rotr(int x, int n) =>
      ((x >>> n) | (x << (32 - n))) & 0xFFFFFFFF;

  static Uint8List sha256Bytes(List<int> input) {
    final bitLen = input.length * 8;
    final paddedLen = ((input.length + 9 + 63) ~/ 64) * 64;
    final data = Uint8List(paddedLen);
    data.setRange(0, input.length, input);
    data[input.length] = 0x80;
    final bd = ByteData.sublistView(data);
    bd.setUint32(paddedLen - 8, (bitLen ~/ 0x100000000) & 0xFFFFFFFF);
    bd.setUint32(paddedLen - 4, bitLen & 0xFFFFFFFF);

    final h = List<int>.from(_initH);
    final w = List<int>.filled(64, 0);

    for (var offset = 0; offset < paddedLen; offset += 64) {
      for (var i = 0; i < 16; i++) {
        w[i] = bd.getUint32(offset + i * 4);
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
      }

      var a = h[0], b = h[1], c = h[2], d = h[3];
      var e = h[4], f = h[5], g = h[6], hh = h[7];

      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = (hh + s1 + ch + _roundK[i] + w[i]) & 0xFFFFFFFF;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xFFFFFFFF;

        hh = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xFFFFFFFF;
      }

      h[0] = (h[0] + a) & 0xFFFFFFFF;
      h[1] = (h[1] + b) & 0xFFFFFFFF;
      h[2] = (h[2] + c) & 0xFFFFFFFF;
      h[3] = (h[3] + d) & 0xFFFFFFFF;
      h[4] = (h[4] + e) & 0xFFFFFFFF;
      h[5] = (h[5] + f) & 0xFFFFFFFF;
      h[6] = (h[6] + g) & 0xFFFFFFFF;
      h[7] = (h[7] + hh) & 0xFFFFFFFF;
    }

    final out = Uint8List(32);
    final outBd = ByteData.sublistView(out);
    for (var i = 0; i < 8; i++) {
      outBd.setUint32(i * 4, h[i]);
    }
    return out;
  }

  static String _toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write((b & 0xFF).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static bool isHashed(String value) => value.startsWith(prefix);

  static String hashPin(String pin, {String? saltHex}) {
    final salt = saltHex ?? _generateSaltHex();
    final pinBytes = utf8.encode(pin);
    var acc = sha256Bytes(<int>[...utf8.encode(salt), ...pinBytes]);
    for (var i = 1; i < _rounds; i++) {
      acc = sha256Bytes(<int>[...acc, ...pinBytes]);
    }
    return '$prefix$salt:${_toHex(acc)}';
  }

  static bool verifyPin(String candidate, String stored) {
    if (stored.isEmpty || candidate.isEmpty) return false;
    if (!isHashed(stored)) {
      return _constantTimeEquals(candidate, stored);
    }
    final rest = stored.substring(prefix.length);
    final sep = rest.indexOf(':');
    if (sep <= 0) return false;
    final saltHex = rest.substring(0, sep);
    final recomputed = hashPin(candidate, saltHex: saltHex);
    return _constantTimeEquals(recomputed, stored);
  }

  static String _generateSaltHex() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return _toHex(bytes);
  }

  static bool _constantTimeEquals(String a, String b) {
    final len = math.max(a.length, b.length);
    var diff = a.length ^ b.length;
    for (var i = 0; i < len; i++) {
      final ca = i < a.length ? a.codeUnitAt(i) : 0;
      final cb = i < b.length ? b.codeUnitAt(i) : 0;
      diff |= ca ^ cb;
    }
    return diff == 0;
  }
}
