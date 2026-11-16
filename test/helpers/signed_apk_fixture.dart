import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pointycastle/export.dart';

/// A signing identity for test APKs: an RSA key and a minimal certificate.
class ApkTestSigner {
  ApkTestSigner._(this._private, this.publicKeyInfo, this.certificate);

  /// Deterministic per [seed], so fingerprints are stable across runs.
  factory ApkTestSigner(int seed) {
    final random = FortunaRandom()
      ..seed(KeyParameter(Uint8List(32)..fillRange(0, 32, seed)));
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    final public = pair.publicKey;
    final spki = _seq([
      _seq([_oid(_rsaEncryption), _null()]),
      _bitString(_seq([_int(public.modulus!), _int(public.exponent!)])),
    ]);
    final certificate = _seq([
      _seq([
        _tag(0xa0, _int(BigInt.two)),
        _int(BigInt.from(seed + 1)),
        _seq([_oid(_sha256WithRsa), _null()]),
        _seq([]),
        _seq([_utcTime('260101000000Z'), _utcTime('360101000000Z')]),
        _seq([]),
        spki,
      ]),
      _seq([_oid(_sha256WithRsa), _null()]),
      _bitString(Uint8List(16)),
    ]);
    return ApkTestSigner._(pair.privateKey, spki, certificate);
  }

  final RSAPrivateKey _private;
  final Uint8List publicKeyInfo;
  final Uint8List certificate;

  /// What a Mihon store publishes as `signingKey` for this signer.
  String get fingerprint => _hex(SHA256Digest().process(certificate));

  Uint8List sign(Uint8List message) {
    final signer = Signer('SHA-256/RSA')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(_private));
    return (signer.generateSignature(message) as RSASignature).bytes;
  }
}

/// A tiny APK with an APK Signature Scheme v2 block, as apksigner writes it.
///
/// [certificate] lets a test put a different certificate in front of a valid
/// signature, which a verifier must refuse.
Uint8List signedApk(
  ApkTestSigner signer, {
  String dex = 'kuchie-test-dex',
  Uint8List? certificate,
}) {
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('classes.dex', utf8.encode(dex)))
    ..addFile(ArchiveFile.bytes('AndroidManifest.xml', utf8.encode('<m/>')));
  final zip = Uint8List.fromList(ZipEncoder().encode(archive));
  final data = ByteData.sublistView(zip);
  final eocdOffset = zip.length - 22;
  final cdOffset = data.getUint32(eocdOffset + 16, Endian.little);
  final contents = Uint8List.sublistView(zip, 0, cdOffset);
  final centralDirectory = Uint8List.sublistView(zip, cdOffset, eocdOffset);
  final eocd = Uint8List.fromList(zip.sublist(eocdOffset));

  final digestEnd = Uint8List.fromList(eocd);
  ByteData.sublistView(digestEnd).setUint32(16, contents.length, Endian.little);
  final digest = _contentDigest([contents, centralDirectory, digestEnd]);

  final signedData = _concat([
    _lp(_lp(_concat([_u32(0x0103), _lp(digest)]))),
    _lp(_lp(certificate ?? signer.certificate)),
    _lp(Uint8List(0)),
  ]);
  final signerBlock = _concat([
    _lp(signedData),
    _lp(_lp(_concat([_u32(0x0103), _lp(signer.sign(signedData))]))),
    _lp(signer.publicKeyInfo),
  ]);
  final v2 = _lp(_lp(signerBlock));
  final pair = _concat([_u64(v2.length + 4), _u32(0x7109871a), v2]);
  final size = pair.length + 8 + 16;
  final block = _concat([
    _u64(size),
    pair,
    _u64(size),
    Uint8List.fromList(ascii.encode('APK Sig Block 42')),
  ]);

  ByteData.sublistView(
    eocd,
  ).setUint32(16, contents.length + block.length, Endian.little);
  return _concat([contents, block, centralDirectory, eocd]);
}

Uint8List _contentDigest(List<Uint8List> sections) {
  final chunks = <Uint8List>[];
  for (final section in sections) {
    for (var offset = 0; offset < section.length; offset += 1 << 20) {
      final end = (offset + (1 << 20)).clamp(0, section.length);
      final chunk = Uint8List.sublistView(section, offset, end);
      chunks.add(
        SHA256Digest().process(
          _concat([
            Uint8List.fromList([0xa5]),
            _u32(chunk.length),
            chunk,
          ]),
        ),
      );
    }
  }
  return SHA256Digest().process(
    _concat([
      Uint8List.fromList([0x5a]),
      _u32(chunks.length),
      ...chunks,
    ]),
  );
}

const _rsaEncryption = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01];
const _sha256WithRsa = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b];

Uint8List _tag(int tag, List<int> value) {
  final length = value.length;
  final header = length < 0x80
      ? [tag, length]
      : length < 0x100
      ? [tag, 0x81, length]
      : [tag, 0x82, length >> 8, length & 0xff];
  return Uint8List.fromList([...header, ...value]);
}

Uint8List _seq(List<Uint8List> items) => _tag(0x30, _concat(items));
Uint8List _oid(List<int> bytes) => _tag(0x06, bytes);
Uint8List _null() => Uint8List.fromList([0x05, 0x00]);
Uint8List _utcTime(String value) => _tag(0x17, ascii.encode(value));
Uint8List _bitString(Uint8List bytes) => _tag(0x03, [0, ...bytes]);

Uint8List _int(BigInt value) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  return _tag(0x02, bytes.first >= 0x80 ? [0, ...bytes] : bytes);
}

Uint8List _lp(Uint8List value) => _concat([_u32(value.length), value]);

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

Uint8List _u64(int value) =>
    Uint8List(8)..buffer.asByteData().setUint64(0, value, Endian.little);

Uint8List _concat(List<Uint8List> parts) {
  final out = BytesBuilder(copy: false);
  parts.forEach(out.add);
  return out.takeBytes();
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
