import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// An APK whose signature is missing, malformed or does not verify.
class ApkSignatureException extends FormatException {
  const ApkSignatureException(super.message);
}

const _v2BlockId = 0x7109871a;
const _v3BlockId = 0xf05368c0;
const _chunkSize = 1024 * 1024;

/// Verifies an APK the way Android does for APK Signature Scheme v2 and v3:
/// each signer's signature over its signed data, and the signed digest of the
/// whole archive. Returns the SHA-256 of every verified signer certificate, as
/// lowercase hex, which is what Mihon stores publish as `signingKey`.
///
/// Both blocks are checked when present, so a store that kept its original key
/// fingerprint still matches an APK whose v3 signer rotated to a new key.
List<String> verifyApkSigners(Uint8List apk) {
  final zip = _ZipLayout.read(apk);
  final blocks = _signingBlocks(apk, zip);
  final v2 = blocks[_v2BlockId];
  final v3 = blocks[_v3BlockId];
  if (v2 == null && v3 == null) {
    throw const ApkSignatureException(
      'The APK has no v2 or v3 signature. Older v1-only APKs are unsupported.',
    );
  }
  final fingerprints = <String>{};
  for (final (block, isV3) in [(v2, false), (v3, true)]) {
    if (block == null) continue;
    final signers = _lengthPrefixedItems(_Reader(block).lengthPrefixed());
    if (signers.isEmpty || signers.length > 10) {
      throw const ApkSignatureException('The APK signature has no signers.');
    }
    for (final signer in signers) {
      fingerprints.add(_verifySigner(apk, zip, signer, isV3: isV3));
    }
  }
  return fingerprints.toList(growable: false);
}

String _verifySigner(
  Uint8List apk,
  _ZipLayout zip,
  Uint8List signer, {
  required bool isV3,
}) {
  final reader = _Reader(signer);
  final signedData = reader.lengthPrefixed();
  if (isV3) {
    reader.uint32(); // minSdkVersion
    reader.uint32(); // maxSdkVersion
  }
  final signatures = _lengthPrefixedItems(reader.lengthPrefixed());
  final publicKey = reader.lengthPrefixed();

  final signed = _Reader(signedData);
  final digests = _lengthPrefixedItems(signed.lengthPrefixed());
  final certificates = _lengthPrefixedItems(signed.lengthPrefixed());
  if (certificates.isEmpty) {
    throw const ApkSignatureException('The APK signer has no certificate.');
  }

  final signatureByAlgorithm = <int, Uint8List>{};
  for (final item in signatures) {
    final entry = _Reader(item);
    signatureByAlgorithm[entry.uint32()] = entry.lengthPrefixed();
  }
  final digestByAlgorithm = <int, Uint8List>{};
  for (final item in digests) {
    final entry = _Reader(item);
    digestByAlgorithm[entry.uint32()] = entry.lengthPrefixed();
  }
  if (!_sameKeys(signatureByAlgorithm, digestByAlgorithm)) {
    throw const ApkSignatureException(
      'The APK signature and digest algorithms differ.',
    );
  }

  final algorithm = _preferredAlgorithm(signatureByAlgorithm.keys);
  if (algorithm == null) {
    throw const ApkSignatureException(
      'The APK uses an unsupported signature algorithm.',
    );
  }
  final key = _PublicKey.parse(publicKey);
  if (!key.verify(algorithm, signedData, signatureByAlgorithm[algorithm.id]!)) {
    throw const ApkSignatureException('The APK signature does not verify.');
  }
  // The leaf certificate must carry the key that produced the signature.
  if (!_bytesEqual(_certificatePublicKey(certificates.first), publicKey)) {
    throw const ApkSignatureException(
      'The APK certificate does not match its signing key.',
    );
  }
  final expected = digestByAlgorithm[algorithm.id]!;
  final actual = _contentDigest(apk, zip, algorithm.sha512);
  if (!_bytesEqual(expected, actual)) {
    throw const ApkSignatureException('The APK contents were modified.');
  }
  return _hex(SHA256Digest().process(certificates.first));
}

enum _Algorithm {
  rsaSha256(0x0103, sha512: false, ec: false),
  rsaSha512(0x0104, sha512: true, ec: false),
  ecdsaSha256(0x0201, sha512: false, ec: true),
  ecdsaSha512(0x0202, sha512: true, ec: true);

  const _Algorithm(this.id, {required this.sha512, required this.ec});
  final int id;
  final bool sha512;
  final bool ec;
}

_Algorithm? _preferredAlgorithm(Iterable<int> ids) {
  const order = [
    _Algorithm.rsaSha512,
    _Algorithm.ecdsaSha512,
    _Algorithm.rsaSha256,
    _Algorithm.ecdsaSha256,
  ];
  final available = ids.toSet();
  for (final algorithm in order) {
    if (available.contains(algorithm.id)) return algorithm;
  }
  return null;
}

/// The central directory and end record, located the way Android does.
class _ZipLayout {
  const _ZipLayout(this.centralDirectory, this.centralDirectorySize, this.end);

  final int centralDirectory;
  final int centralDirectorySize;
  final int end;

  static _ZipLayout read(Uint8List apk) {
    final data = ByteData.sublistView(apk);
    final lowest = apk.length - 22 - 0xffff;
    for (
      var offset = apk.length - 22;
      offset >= 0 && offset >= lowest;
      offset--
    ) {
      if (data.getUint32(offset, Endian.little) != 0x06054b50) continue;
      final comment = data.getUint16(offset + 20, Endian.little);
      if (offset + 22 + comment != apk.length) continue;
      final size = data.getUint32(offset + 12, Endian.little);
      final start = data.getUint32(offset + 16, Endian.little);
      if (start + size != offset) {
        throw const ApkSignatureException('The APK archive is malformed.');
      }
      return _ZipLayout(start, size, offset);
    }
    throw const ApkSignatureException('The file is not an APK archive.');
  }
}

/// The signing block sits right before the central directory.
Map<int, Uint8List> _signingBlocks(Uint8List apk, _ZipLayout zip) {
  final data = ByteData.sublistView(apk);
  final cd = zip.centralDirectory;
  if (cd < 32 ||
      String.fromCharCodes(apk.sublist(cd - 16, cd)) != 'APK Sig Block 42') {
    throw const ApkSignatureException(
      'The APK has no v2 or v3 signature. Older v1-only APKs are unsupported.',
    );
  }
  final size = data.getUint64(cd - 24, Endian.little);
  if (size < 24 || size > cd - 8) {
    throw const ApkSignatureException('The APK signing block is malformed.');
  }
  final start = cd - size - 8;
  if (data.getUint64(start, Endian.little) != size) {
    throw const ApkSignatureException('The APK signing block is malformed.');
  }
  final blocks = <int, Uint8List>{};
  var offset = start + 8;
  final end = cd - 24;
  while (offset < end) {
    if (end - offset < 12) {
      throw const ApkSignatureException('The APK signing block is malformed.');
    }
    final length = data.getUint64(offset, Endian.little);
    if (length < 4 || length > end - offset - 8) {
      throw const ApkSignatureException('The APK signing block is malformed.');
    }
    final id = data.getUint32(offset + 8, Endian.little);
    blocks[id] = Uint8List.sublistView(apk, offset + 12, offset + 8 + length);
    offset += 8 + length;
  }
  return blocks;
}

/// Chunked digest over the entries, central directory and end record, with
/// the end record pointing at where the signing block starts.
Uint8List _contentDigest(Uint8List apk, _ZipLayout zip, bool sha512) {
  final data = ByteData.sublistView(apk);
  final size = data.getUint64(zip.centralDirectory - 24, Endian.little);
  final signingBlockStart = zip.centralDirectory - size - 8;
  final end = Uint8List.fromList(apk.sublist(zip.end));
  ByteData.sublistView(end).setUint32(16, signingBlockStart, Endian.little);
  final sections = [
    Uint8List.sublistView(apk, 0, signingBlockStart),
    Uint8List.sublistView(
      apk,
      zip.centralDirectory,
      zip.centralDirectory + zip.centralDirectorySize,
    ),
    end,
  ];
  Digest digest() => sha512 ? SHA512Digest() : SHA256Digest();
  final chunkDigests = BytesBuilder(copy: false);
  var chunks = 0;
  for (final section in sections) {
    for (var offset = 0; offset < section.length; offset += _chunkSize) {
      final length = (section.length - offset).clamp(0, _chunkSize);
      final chunk = digest()
        ..update(Uint8List.fromList([0xa5]), 0, 1)
        ..update(_uint32(length), 0, 4)
        ..update(section, offset, length);
      final out = Uint8List(chunk.digestSize);
      chunk.doFinal(out, 0);
      chunkDigests.add(out);
      chunks++;
    }
  }
  final top = digest();
  final all = chunkDigests.takeBytes();
  top
    ..update(Uint8List.fromList([0x5a]), 0, 1)
    ..update(_uint32(chunks), 0, 4)
    ..update(all, 0, all.length);
  final out = Uint8List(top.digestSize);
  top.doFinal(out, 0);
  return out;
}

class _PublicKey {
  _PublicKey.rsa(RSAPublicKey this._rsa) : _ec = null;
  _PublicKey.ec(ECPublicKey this._ec) : _rsa = null;

  final RSAPublicKey? _rsa;
  final ECPublicKey? _ec;

  static const _rsaOid = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01];
  static const _ecOid = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01];
  static const _curves = {
    '2a8648ce3d030107': 'prime256v1',
    '2b81040022': 'secp384r1',
    '2b81040023': 'secp521r1',
  };

  static _PublicKey parse(Uint8List spki) {
    final outer = _Der(spki).sequence();
    final algorithm = outer.sequence();
    final oid = algorithm.read(0x06);
    final bits = outer.read(0x03);
    if (bits.isEmpty || bits.first != 0) {
      throw const ApkSignatureException('The APK signing key is malformed.');
    }
    final key = Uint8List.sublistView(bits, 1);
    if (_bytesEqual(oid, _rsaOid)) {
      final rsa = _Der(key).sequence();
      return _PublicKey.rsa(
        RSAPublicKey(_integer(rsa.read(0x02)), _integer(rsa.read(0x02))),
      );
    }
    if (_bytesEqual(oid, _ecOid)) {
      final curve = _curves[_hex(algorithm.read(0x06))];
      if (curve == null) {
        throw const ApkSignatureException('The APK uses an unsupported curve.');
      }
      final domain = ECDomainParameters(curve);
      final point = domain.curve.decodePoint(key);
      if (point == null) {
        throw const ApkSignatureException('The APK signing key is malformed.');
      }
      return _PublicKey.ec(ECPublicKey(point, domain));
    }
    throw const ApkSignatureException('The APK uses an unsupported key type.');
  }

  bool verify(_Algorithm algorithm, Uint8List message, Uint8List signature) {
    final digest = algorithm.sha512 ? 'SHA-512' : 'SHA-256';
    try {
      if (algorithm.ec) {
        final ec = _ec;
        if (ec == null) return false;
        final der = _Der(signature).sequence();
        final verifier = Signer('$digest/ECDSA')
          ..init(false, PublicKeyParameter<ECPublicKey>(ec));
        return verifier.verifySignature(
          message,
          ECSignature(_integer(der.read(0x02)), _integer(der.read(0x02))),
        );
      }
      final rsa = _rsa;
      if (rsa == null) return false;
      final verifier = Signer('$digest/RSA')
        ..init(false, PublicKeyParameter<RSAPublicKey>(rsa));
      return verifier.verifySignature(message, RSASignature(signature));
    } on ApkSignatureException {
      return false;
    } on ArgumentError {
      return false;
    }
  }
}

/// The SubjectPublicKeyInfo of an X.509 certificate, as raw DER.
Uint8List _certificatePublicKey(Uint8List certificate) {
  final tbs = _Der(certificate).sequence().sequence();
  if (tbs.peekTag() == 0xa0) tbs.read(0xa0); // version
  tbs
    ..read(0x02) // serialNumber
    ..read(0x30) // signature
    ..read(0x30) // issuer
    ..read(0x30) // validity
    ..read(0x30); // subject
  return tbs.raw(0x30);
}

/// A minimal DER reader: definite lengths only, which is all X.509 uses.
class _Der {
  _Der(this._bytes);

  final Uint8List _bytes;
  var _offset = 0;

  int peekTag() => _offset < _bytes.length ? _bytes[_offset] : -1;

  _Der sequence() => _Der(read(0x30));

  Uint8List read(int tag) {
    final (start, end) = _element(tag);
    _offset = end;
    return Uint8List.sublistView(_bytes, start, end);
  }

  /// The whole element, tag and length included.
  Uint8List raw(int tag) {
    final begin = _offset;
    final (_, end) = _element(tag);
    _offset = end;
    return Uint8List.sublistView(_bytes, begin, end);
  }

  (int, int) _element(int tag) {
    if (_offset + 2 > _bytes.length || _bytes[_offset] != tag) {
      throw const ApkSignatureException('The APK certificate is malformed.');
    }
    var cursor = _offset + 1;
    var length = _bytes[cursor++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || cursor + count > _bytes.length) {
        throw const ApkSignatureException('The APK certificate is malformed.');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | _bytes[cursor++];
      }
    }
    if (cursor + length > _bytes.length) {
      throw const ApkSignatureException('The APK certificate is malformed.');
    }
    return (cursor, cursor + length);
  }
}

/// Little-endian, length-prefixed fields used inside the signing block.
class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  var _offset = 0;

  bool get hasMore => _offset < _bytes.length;

  int uint32() {
    if (_offset + 4 > _bytes.length) {
      throw const ApkSignatureException('The APK signature is malformed.');
    }
    final value = ByteData.sublistView(
      _bytes,
    ).getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  Uint8List lengthPrefixed() {
    final length = uint32();
    if (length > _bytes.length - _offset) {
      throw const ApkSignatureException('The APK signature is malformed.');
    }
    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }
}

List<Uint8List> _lengthPrefixedItems(Uint8List bytes) {
  final reader = _Reader(bytes);
  return [for (; reader.hasMore;) reader.lengthPrefixed()];
}

BigInt _integer(Uint8List bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

Uint8List _uint32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

bool _sameKeys(Map<int, Object> a, Map<int, Object> b) =>
    a.length == b.length && a.keys.every(b.containsKey);

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
