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
  final Set<Future<void>> _workers = {};
  final Map<LocalDownloadRequest, http.Client> _active = Map.identity();
  final Map<LocalDownloadRequest, Completer<void>> _finished = Map.identity();
  int _concurrency = 1;

  /// Completes once no chapter is downloading or waiting for a worker.
  Future<void> get idle async {
    while (_workers.isNotEmpty) {
      await Future.wait([..._workers]);
    }
  }

  /// How many chapters download at the same time.
  int get concurrency => _concurrency;

  static const maxConcurrency = 5;

  set concurrency(int value) {
    _concurrency = value.clamp(1, maxConcurrency);
    _start();
  }

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
    _active[item.request]?.close();
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
    _closeActive();
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
    _closeActive();
    await idle;
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
    _active[item.request]?.close();
    await _finished[item.request]?.future;
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

  void _closeActive() {
    for (final client in _active.values) {
      client.close();
    }
  }

  /// Starts workers until [concurrency] are running or nothing is waiting.
  void _start() {
    var waiting = value
        .where((item) => item.state == LocalDownloadState.queued)
        .length;
    while (_workers.length < _concurrency && waiting > 0) {
      waiting--;
      late final Future<void> worker;
      worker = _drain().whenComplete(() {
        _workers.remove(worker);
        if (value.any((item) => item.state == LocalDownloadState.queued)) {
          _start();
        }
      });
      _workers.add(worker);
      unawaited(
        worker.catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(exception: error, stack: stack),
          );
        }),
      );
    }
  }

  Future<void> _drain() async {
    // A lowered limit retires the extra workers between chapters.
    while (_workers.length <= _concurrency) {
      final job = value
          .where((item) => item.state == LocalDownloadState.queued)
          .firstOrNull;
      if (job == null) return;
      final request = job.request;
      final client = _clientFactory();
      _active[request] = client;
      final finished = _finished[request] = Completer<void>();
      // Claimed synchronously, so no other worker picks the same chapter.
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
        _active.remove(request);
        _finished.remove(request);
        finished.complete();
      }
      await _persist();
    }
  }
}
