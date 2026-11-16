import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/local_collection/data/apk_signature.dart';

import '../../../../helpers/signed_apk_fixture.dart';

void main() {
  final store = ApkTestSigner(1);
  final stranger = ApkTestSigner(2);

  test('returns the fingerprint stores publish as signingKey', () {
    expect(verifyApkSigners(signedApk(store)), [store.fingerprint]);
    expect(verifyApkSigners(signedApk(stranger)), [stranger.fingerprint]);
    expect(store.fingerprint, isNot(stranger.fingerprint));
  });

  test('refuses an APK whose contents changed after signing', () {
    final apk = signedApk(store);
    // Past the 30-byte local header and the 11-byte "classes.dex" name.
    apk[45] ^= 1;
    expect(() => verifyApkSigners(apk), _refused('modified'));
  });

  test('refuses a forged signature', () {
    final apk = signedApk(store);
    // The last bytes of the signer block are the public key; the signature
    // sits just before it. Flip a byte in the middle of the block instead.
    final magic = _indexOf(apk, 'APK Sig Block 42');
    apk[magic - 300] ^= 0xff;
    expect(() => verifyApkSigners(apk), throwsA(isA<ApkSignatureException>()));
  });

  test("refuses a store's certificate pasted in front of another key", () {
    final apk = signedApk(stranger, certificate: store.certificate);
    expect(() => verifyApkSigners(apk), _refused('certificate'));
  });

  test('refuses unsigned and non-APK files', () {
    final unsigned = Uint8List.fromList(
      ZipEncoder().encode(
        Archive()..addFile(ArchiveFile.bytes('classes.dex', [1, 2, 3])),
      ),
    );
    expect(() => verifyApkSigners(unsigned), _refused('v1-only'));
    expect(
      () => verifyApkSigners(Uint8List.fromList([80, 75, 3, 4, 5])),
      throwsA(isA<ApkSignatureException>()),
    );
  });
}

Matcher _refused(String reason) => throwsA(
  isA<ApkSignatureException>().having(
    (error) => error.message,
    'message',
    contains(reason),
  ),
);

int _indexOf(Uint8List haystack, String needle) {
  final bytes = needle.codeUnits;
  outer:
  for (var i = 0; i <= haystack.length - bytes.length; i++) {
    for (var j = 0; j < bytes.length; j++) {
      if (haystack[i + j] != bytes[j]) continue outer;
    }
    return i;
  }
  throw StateError('$needle not found');
}
