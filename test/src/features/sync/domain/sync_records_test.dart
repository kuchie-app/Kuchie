import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/sync/domain/sync_method.dart';
import 'package:kuchie/src/features/sync/domain/sync_records.dart';
import 'package:kuchie/src/features/sync/domain/sync_status.dart';

void main() {
  final at = DateTime.utc(2026, 11, 27, 8, 30, 15, 250);

  test('categories match by name, ignoring case and spaces', () {
    expect(categoryKey('  Action '), categoryKey('action'));
  });

  group('SeriesState', () {
    final state = SeriesState(
      inLibrary: true,
      categories: const {'b', 'a'},
      changedAt: at,
    );

    test('round-trips through JSON with sorted categories', () {
      expect(state.toJson(), {
        'inLibrary': true,
        'categories': ['a', 'b'],
        'changedAt': at.millisecondsSinceEpoch,
      });
      expect(SeriesState.fromJson(state.toJson()), state);
      expect(SeriesState.fromJson(const {}), SeriesState.absent);
      expect(
        SeriesState.fromJson(const {
          'inLibrary': 'yes',
          'categories': ['a', 3],
          'changedAt': 'soon',
        }),
        const SeriesState(inLibrary: false, categories: {'a'}),
      );
    });

    test('sameAs ignores the change time, == does not', () {
      final later = state.copyWith(changedAt: at.add(const Duration(hours: 1)));
      expect(state.sameAs(later), isTrue);
      expect(state == later, isFalse);
      expect(state.copyWith(), state);
      expect(state.copyWith().hashCode, state.hashCode);
      expect(
        state.copyWith(inLibrary: false, categories: const {'c'}),
        SeriesState(inLibrary: false, categories: const {'c'}, changedAt: at),
      );
      expect('$state', contains('inLibrary: true'));
    });
  });

  group('ChapterState', () {
    final state = ChapterState(
      read: true,
      page: 12,
      bookmarked: true,
      readAt: at,
    );

    test('round-trips through JSON', () {
      expect(ChapterState.fromJson(state.toJson()), state);
      expect(ChapterState.fromJson(state.toJson()).hashCode, state.hashCode);
      expect(const ChapterState().toJson(), {
        'read': false,
        'page': 0,
        'bookmarked': false,
      });
      expect(
        ChapterState.fromJson(const {'page': -3, 'read': 1}),
        const ChapterState(),
      );
      expect('$state', contains('page: 12'));
    });
  });

  group('SeriesMeta', () {
    const meta = SeriesMeta(rating: 4, tags: ['x', 'y'], notes: 'good');

    test('round-trips through JSON', () {
      expect(SeriesMeta.fromJson(meta.toJson()), meta);
      expect(SeriesMeta.fromJson(meta.toJson()).hashCode, meta.hashCode);
      expect(const SeriesMeta().toJson(), {'tags': <String>[]});
      expect(
        SeriesMeta.fromJson(const {
          'rating': '4',
          'tags': ['a', 1],
          'notes': 2,
        }),
        const SeriesMeta(tags: ['a']),
      );
      expect('$meta', contains('rating: 4'));
    });
  });

  group('ReaderMeta', () {
    const meta = ReaderMeta({'mode': 'rtl'});

    test('round-trips through JSON, dropping non-string values', () {
      expect(ReaderMeta.fromJson(meta.toJson()), meta);
      expect(ReaderMeta.fromJson(meta.toJson()).hashCode, meta.hashCode);
      expect(ReaderMeta.fromJson(const {'mode': 'rtl', 'zoom': 2}), meta);
      expect('$meta', 'ReaderMeta({mode: rtl})');
    });
  });

  test('SyncMethod reads stored names, defaulting to none', () {
    expect(SyncMethod.fromName('suwayomi'), SyncMethod.suwayomi);
    expect(SyncMethod.fromName('icloud'), SyncMethod.icloud);
    expect(SyncMethod.fromName('dropbox'), SyncMethod.none);
    expect(SyncMethod.fromName(null), SyncMethod.none);
  });

  group('SyncStatus', () {
    test('compares by value', () {
      final pairs = <(SyncStatus, SyncStatus)>[
        (const SyncOff(), const SyncOff()),
        (SyncIdle(lastSuccessAt: at), SyncIdle(lastSuccessAt: at)),
        (const SyncInProgress(), const SyncInProgress()),
        (
          SyncWaitingForServer(lastSuccessAt: at, pending: 2),
          SyncWaitingForServer(lastSuccessAt: at, pending: 2),
        ),
        (const SyncPending(3), const SyncPending(3)),
        (
          const SyncActionNeeded(SyncActionReason.loginExpired),
          const SyncActionNeeded(SyncActionReason.loginExpired),
        ),
      ];
      for (final (a, b) in pairs) {
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      }
      expect(const SyncPending(3), isNot(const SyncPending(4)));
      expect(
        const SyncActionNeeded(SyncActionReason.loginExpired),
        isNot(const SyncActionNeeded(SyncActionReason.serverChanged)),
      );
      expect(const SyncOff(), isNot(const SyncInProgress()));
    });

    test('waiting is stale after a week without a sync', () {
      final now = at.add(const Duration(days: 8));
      expect(SyncWaitingForServer(lastSuccessAt: at).isStale(now), isTrue);
      expect(
        SyncWaitingForServer(
          lastSuccessAt: at,
        ).isStale(at.add(const Duration(days: 6))),
        isFalse,
      );
      expect(const SyncWaitingForServer().isStale(now), isFalse);
    });
  });
}
