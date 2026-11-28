import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// A minimal Mihon backup (`.tachibk`: gzipped protobuf) that Suwayomi's
// `restoreBackup` reads. Field numbers follow Mihon's
// `eu.kanade.tachiyomi.data.backup.models` (Backup, BackupManga,
// BackupSource); `tool/qa/sync_spike/backup.py` is the reference spike S3
// used.

/// A manga to create in the server library.
class BackupSeries {
  const BackupSeries({
    required this.sourceId,
    required this.url,
    required this.title,
    this.sourceName = '',
    this.addedAt,
  });

  /// The Mihon source id, a signed 64-bit number as text.
  final String sourceId;
  final String url;
  final String title;
  final String sourceName;
  final DateTime? addedAt;
}

/// The backup bytes for [series], each a library favourite.
Uint8List encodeMihonBackup(List<BackupSeries> series) {
  final body = _Writer();
  final sources = <String, String>{};
  for (final entry in series) {
    sources.putIfAbsent(entry.sourceId, () => entry.sourceName);
    final manga = _Writer()
      ..int64(1, entry.sourceId)
      ..string(2, entry.url)
      ..string(3, entry.title)
      ..varint(13, entry.addedAt?.millisecondsSinceEpoch ?? 0)
      ..varint(100, 1);
    body.bytes(1, manga.done());
  }
  for (final MapEntry(key: id, value: name) in sources.entries) {
    body.bytes(
      101,
      (_Writer()
            ..string(1, name)
            ..int64(2, id))
          .done(),
    );
  }
  return Uint8List.fromList(gzip.encode(body.done()));
}

class _Writer {
  final _out = BytesBuilder(copy: false);

  void _raw(BigInt value) {
    var rest = value.toUnsigned(64);
    final mask = BigInt.from(0x7f);
    while (true) {
      final byte = (rest & mask).toInt();
      rest >>= 7;
      if (rest == BigInt.zero) {
        _out.addByte(byte);
        return;
      }
      _out.addByte(byte | 0x80);
    }
  }

  void _key(int field, int wire) => _raw(BigInt.from(field << 3 | wire));

  void varint(int field, int value) {
    _key(field, 0);
    _raw(BigInt.from(value));
  }

  void int64(int field, String value) {
    _key(field, 0);
    _raw(BigInt.parse(value));
  }

  void bytes(int field, List<int> data) {
    _key(field, 2);
    _raw(BigInt.from(data.length));
    _out.add(data);
  }

  void string(int field, String text) => bytes(field, utf8.encode(text));

  Uint8List done() => _out.toBytes();
}
