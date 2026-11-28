// S7: the signer fingerprint Kuchie verifies for an APK, to compare with the
// `signingKey` a Suwayomi server reports for the store.
//
// Usage: dart run tool/qa/sync_spike/s7_signer.dart <extension.apk>...
import 'dart:io';

import 'package:kuchie/src/features/local_collection/data/apk_signature.dart';

void main(List<String> paths) {
  for (final path in paths) {
    final signers = verifyApkSigners(File(path).readAsBytesSync());
    stdout.writeln('${path.split('/').last} ${signers.join(',')}');
  }
}
