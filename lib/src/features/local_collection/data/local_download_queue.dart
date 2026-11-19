import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_catalog.dart';

enum LocalDownloadState { queued, downloading, paused, failed }

typedef LocalRuntimeChapter = ({String sourceId, String locator});
typedef ResolveLocalDownload =
    Future<List<({Uri url, Map<String, String> headers})>> Function(
      String sourceId,
      String locator,
    );

class LocalDownloadRequest {
  const LocalDownloadRequest({
    required this.seriesId,
    required this.title,
    required this.chapterId,
    required this.chapterTitle,
    required this.pages,
    this.runtimeChapter,
    this.source,
  });

  factory LocalDownloadRequest.fromJson(Map<String, dynamic> json) =>
      LocalDownloadRequest(
        seriesId: json['series'] as String,
        title: json['title'] as String,
        chapterId: json['chapter'] as String,
        chapterTitle: json['chapterTitle'] as String,
        pages:
            (json['pages'] as List?)?.cast<String>().map(Uri.parse).toList() ??
            const [],
        runtimeChapter: switch (json['source']) {
          {'id': final String id, 'chapter': final String locator} => (
            sourceId: id,
            locator: locator,
          ),
          _ => null,
        },
        source: LocalSeriesSource.fromJson(json['seriesSource']),
      );

  final String seriesId;
  final String title;
  final String chapterId;
  final String chapterTitle;
  final List<Uri> pages;
  final LocalRuntimeChapter? runtimeChapter;
  final LocalSeriesSource? source;

  Map<String, Object> toJson() => {
    'series': seriesId,
    'title': title,
    'chapter': chapterId,
    'chapterTitle': chapterTitle,
    if (source case final seriesSource?) 'seriesSource': seriesSource.toJson(),
    if (runtimeChapter case final chapter?)
      'source': {'id': chapter.sourceId, 'chapter': chapter.locator}
    else
      'pages': pages.map((page) => page.toString()).toList(),
  };
}

class LocalDownload {
  const LocalDownload(this.request, this.state, {this.done = 0, this.total});

  final LocalDownloadRequest request;
  final LocalDownloadState state;
  final int done;
  final int? total;
  int get pageCount => total ?? request.pages.length;
}

class LocalDownloadQueue extends ValueNotifier<List<LocalDownload>> {
  LocalDownloadQueue(
    this._catalog,
    this._file, {
    http.Client Function()? clientFactory,
    ResolveLocalDownload? resolveRuntimeChapter,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _resolveRuntimeChapter = resolveRuntimeChapter,
       super(const []);

  final LocalCatalog _catalog;
  final File _file;
  final http.Client Function() _clientFactory;
  final ResolveLocalDownload? _resolveRuntimeChapter;
  final ValueNotifier<int> completed = ValueNotifier(0);
  Future<void>? _loaded;
  Future<void> _writes = Future.value();
  Future<void> _worker = Future.value();
  bool _running = false;
  http.Client? _client;
  LocalDownloadRequest? _active;

  Future<void> get idle => _worker;

  Future<void> load() => _loaded ??= _load();

  Future<void> _load() async {
    if (!await _file.exists()) return;
    final saved = jsonDecode(await _file.readAsString()) as List<dynamic>;
    value = [
      for (final row in saved.cast<Map<String, dynamic>>())
        LocalDownload(
          LocalDownloadRequest.fromJson(row),
          row['state'] == LocalDownloadState.failed.name
              ? LocalDownloadState.failed
              : LocalDownloadState.paused,
        ),
    ];
  }

  Future<void> enqueue(LocalDownloadRequest request) async {
    await load();
    if (_find(request.seriesId, request.chapterId) != null) return;
    final chapter = LocalDownload(request, LocalDownloadState.queued);
    value = [...value, chapter];
    try {
      await _persist();
    } catch (_) {
      value = value.where((item) => !identical(item, chapter)).toList();
      rethrow;
    }
    _start();
  }

  Future<void> pause(String seriesId, String chapterId) async {
    final item = _find(seriesId, chapterId);
    if (item == null || item.state == LocalDownloadState.paused) return;
    _set(item.request, LocalDownloadState.paused, done: item.done);
    if (identical(_active, item.request)) _client?.close();
    await _persist();
  }

  Future<void> resume(String seriesId, String chapterId) async {
    final item = _find(seriesId, chapterId);
    if (item == null || item.state == LocalDownloadState.downloading) return;
    _set(item.request, LocalDownloadState.queued, done: item.done);
    await _persist();
    _start();
  }

  /// Whether any chapter is waiting or downloading.
  bool get running => value.any(
    (item) =>
        item.state == LocalDownloadState.queued ||
        item.state == LocalDownloadState.downloading,
  );

  /// Pauses every chapter, as Tachimanga's Pause button does.
  Future<void> pauseAll() async {
    final active = _active;
    value = [
      for (final item in value)
        item.state == LocalDownloadState.queued ||
                item.state == LocalDownloadState.downloading
            ? LocalDownload(
                item.request,
                LocalDownloadState.paused,
                done: item.done,
                total: item.total,
              )
            : item,
    ];
    if (active != null) _client?.close();
    await _persist();
  }

  /// Queues every paused or failed chapter again.
  Future<void> resumeAll() async {
    value = [
      for (final item in value)
        item.state == LocalDownloadState.paused ||
                item.state == LocalDownloadState.failed
            ? LocalDownload(
                item.request,
                LocalDownloadState.queued,
                done: item.done,
                total: item.total,
              )
            : item,
    ];
    await _persist();
    _start();
  }

  /// Removes every chapter from the queue.
  Future<void> clear() async {
    final items = [...value];
    value = const [];
    if (_active != null) {
      _client?.close();
      await _worker;
    }
    await _persist();
    for (final item in items) {
      await _catalog.purgePartialRemoteChapter(
        item.request.seriesId,
        item.request.chapterId,
      );
    }
  }

  Future<void> remove(String seriesId, String chapterId) async {
    final item = _find(seriesId, chapterId);
    if (item == null) return;
    value = value
        .where((candidate) => !identical(candidate.request, item.request))
        .toList();
    if (identical(_active, item.request)) {
      _client?.close();
      await _worker;
    }
    await _persist();
    await _catalog.purgePartialRemoteChapter(seriesId, chapterId);
  }

  LocalDownload? _find(String seriesId, String chapterId) => value
      .where(
        (item) =>
            item.request.seriesId == seriesId &&
            item.request.chapterId == chapterId,
      )
      .firstOrNull;

  void _set(
    LocalDownloadRequest request,
    LocalDownloadState state, {
    int done = 0,
    int? total,
  }) {
    value = [
      for (final item in value)
        if (identical(item.request, request))
          LocalDownload(request, state, done: done, total: total ?? item.total)
        else
          item,
    ];
  }

  Future<void> _persist() {
    final json = jsonEncode([
      for (final item in value)
        {...item.request.toJson(), 'state': item.state.name},
    ]);
    final write = _writes.then((_) async {
      await _file.parent.create(recursive: true);
      final staging = File('${_file.path}.part');
      await staging.writeAsString(json, flush: true);
      await staging.rename(_file.path);
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  void _start() {
    if (_running) return;
    _running = true;
    _worker = _drain().whenComplete(() {
      _running = false;
      if (value.any((item) => item.state == LocalDownloadState.queued)) {
        _start();
      }
    });
    unawaited(
      _worker.catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }),
    );
  }

  Future<void> _drain() async {
    while (true) {
      final job = value
          .where((item) => item.state == LocalDownloadState.queued)
          .firstOrNull;
      if (job == null) return;
      final request = job.request;
      final client = _clientFactory();
      _active = request;
      _client = client;
      _set(request, LocalDownloadState.downloading, done: job.done);
      bool isActive() {
        final current = _find(request.seriesId, request.chapterId);
        return identical(current?.request, request) &&
            current?.state == LocalDownloadState.downloading;
      }

      try {
        final chapter = request.runtimeChapter;
        final runtimePages = chapter == null
            ? null
            : await (_resolveRuntimeChapter ??
                  (String _, String _) => throw StateError(
                    'Extension runtime is unavailable.',
                  ))(chapter.sourceId, chapter.locator);
        if (!isActive()) throw const LocalTransferCancelled();
        await _catalog.saveRemoteChapter(
          seriesId: request.seriesId,
          title: request.title,
          chapterId: request.chapterId,
          chapterTitle: request.chapterTitle,
          pages:
              runtimePages?.map((page) => page.url).toList() ?? request.pages,
          pageHeaders: runtimePages?.map((page) => page.headers).toList(),
          client: client,
          source: request.source,
          isCancelled: () => !isActive(),
          onProgress: (done, total) {
            if (isActive()) {
              _set(
                request,
                LocalDownloadState.downloading,
                done: done,
                total: total,
              );
            }
          },
        );
        value = value
            .where((item) => !identical(item.request, request))
            .toList();
        completed.value++;
      } catch (_) {
        if (isActive()) _set(request, LocalDownloadState.failed);
      } finally {
        client.close();
        _client = null;
        _active = null;
      }
      await _persist();
    }
  }
}
