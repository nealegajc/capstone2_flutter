import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pbkdf2HmacSha256({
  required String password,
  required List<int> salt,
  required int iterations,
  int derivedKeyLength = 32,
}) {
  final hmac = Hmac(sha256, utf8.encode(password));
  final numBlocks = (derivedKeyLength / 32).ceil();
  final result = Uint8List(derivedKeyLength);

  for (int blockIndex = 1; blockIndex <= numBlocks; blockIndex++) {
    // U_1 = PRF(P, S || INT_32_BE(blockIndex))
    final blockBytes = Uint8List(salt.length + 4);
    blockBytes.setRange(0, salt.length, salt);
    blockBytes[salt.length] = (blockIndex >> 24) & 0xff;
    blockBytes[salt.length + 1] = (blockIndex >> 16) & 0xff;
    blockBytes[salt.length + 2] = (blockIndex >> 8) & 0xff;
    blockBytes[salt.length + 3] = blockIndex & 0xff;

    var u = Uint8List.fromList(hmac.convert(blockBytes).bytes);
    final blockResult = Uint8List.fromList(u);

    for (int iter = 1; iter < iterations; iter++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int i = 0; i < 32; i++) {
        blockResult[i] ^= u[i];
      }
    }

    final destOffset = (blockIndex - 1) * 32;
    final lengthToCopy = (derivedKeyLength - destOffset).clamp(0, 32);
    result.setRange(destOffset, destOffset + lengthToCopy, blockResult);
  }

  return result;
}

String toHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  group('PBKDF2-HMAC-SHA256 Test Vectors & Performance', () {
    test('Matches standard RFC test vector (c=1)', () {
      final key = pbkdf2HmacSha256(
        password: 'password',
        salt: utf8.encode('salt'),
        iterations: 1,
        derivedKeyLength: 32,
      );
      expect(
        toHex(key),
        equals(
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
        ),
      );
    });

    test('Matches standard RFC test vector (c=2)', () {
      final key = pbkdf2HmacSha256(
        password: 'password',
        salt: utf8.encode('salt'),
        iterations: 2,
        derivedKeyLength: 32,
      );
      expect(
        toHex(key),
        equals(
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
        ),
      );
    });

    test('Matches standard RFC test vector (c=4096)', () {
      final key = pbkdf2HmacSha256(
        password: 'password',
        salt: utf8.encode('salt'),
        iterations: 4096,
        derivedKeyLength: 32,
      );
      expect(
        toHex(key),
        equals(
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
        ),
      );
    });

    test('Runs 100,000 iterations within acceptable latency budget', () {
      final stopwatch = Stopwatch()..start();
      final key = pbkdf2HmacSha256(
        password: '123456',
        salt: utf8.encode('01234567890123456789012345678901'),
        iterations: 100000,
        derivedKeyLength: 32,
      );
      stopwatch.stop();

      expect(key.length, equals(32));
      // Latency should be reasonable for kiosk login (< 1500ms in debug VM, much faster in AOT)
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
    });
  });
}
