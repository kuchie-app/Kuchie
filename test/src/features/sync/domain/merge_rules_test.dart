import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/sync/domain/merge_rules.dart';
import 'package:kuchie/src/features/sync/domain/sync_records.dart';

final t0 = DateTime.utc(2026, 11, 1, 12);
final t1 = t0.add(const Duration(minutes: 5));

/// The outcome's kind, for compact table rows.
String kind(MergeOutcome<Object?> outcome) => switch (outcome) {
  MergeKeep() => 'keep',
  MergePushLocal() => 'push',
  MergeApplyRemote() => 'apply',
  MergeBoth() => 'both',
};

SeriesState series(
  bool inLibrary, [
  Set<String> categories = const {},
  DateTime? changedAt,
]) => SeriesState(
  inLibrary: inLibrary,
  categories: categories,
  changedAt: changedAt,
);

void main() {
  group('MergeOutcome', () {
    test('says which side gets written', () {
      const outcomes = [
        MergeKeep(1),
        MergePushLocal(1),
        MergeApplyRemote(1),
        MergeBoth(1),
      ];
      expect(
        [for (final o in outcomes) (o.writesLocal, o.writesRemote)],
        [(false, false), (false, true), (true, false), (true, true)],
      );
      expect(outcomes.map((o) => '$o'), [
        'MergeKeep(1)',
        'MergePushLocal(1)',
        'MergeApplyRemote(1)',
        'MergeBoth(1)',
      ]);
    });
  });

  group('merge3', () {
    // Every combination of base, local and remote over {null, a, b}: null is
    // "this side does not have it". The rule marks the rows it decided.
    const values = [null, 'a', 'b'];
    for (final base in values) {
      for (final local in values) {
        for (final remote in values) {
          test('base $base, local $local, remote $remote', () {
            var ruleCalls = 0;
            final outcome = merge3<String>(
              base: base,
              local: local,
              remote: remote,
              rule: (b, l, r) {
                ruleCalls++;
                return 'merged';
              },
            );
            if (local == remote) {
              expect((kind(outcome), outcome.value), ('keep', local));
            } else if (local == base) {
              expect((kind(outcome), outcome.value), ('apply', remote));
            } else if (remote == base) {
              expect((kind(outcome), outcome.value), ('push', local));
            } else {
              expect((kind(outcome), outcome.value), ('both', 'merged'));
              expect(ruleCalls, 1);
              return;
            }
            expect(ruleCalls, 0);
          });
        }
      }
    }

    test('a rule that picks one side writes only the other side', () {
      expect(
        kind(merge3(base: 'a', local: 'b', remote: 'c', rule: (_, l, _) => l)),
        'push',
      );
      expect(
        kind(merge3(base: 'a', local: 'b', remote: 'c', rule: (_, _, r) => r)),
        'apply',
      );
    });

    test('uses the given equality', () {
      final outcome = merge3<String>(
        base: 'a',
        local: 'A',
        remote: 'a',
        rule: (_, _, _) => fail('no conflict'),
        equals: (a, b) => a?.toLowerCase() == b?.toLowerCase(),
      );
      expect(kind(outcome), 'keep');
    });
  });

  group('mergeSeries', () {
    // (base, local, remote, localRead, remoteRead) -> (kind, inLibrary)
    final rows =
        <
          (
            String,
            SeriesState?,
            SeriesState?,
            SeriesState?,
            bool,
            bool,
            String,
            bool?,
          )
        >[
          (
            'unknown on both sides',
            null,
            null,
            null,
            false,
            false,
            'keep',
            null,
          ),
          (
            'only on the server',
            null,
            null,
            series(true),
            false,
            false,
            'apply',
            true,
          ),
          (
            'only on the iPhone',
            null,
            series(true),
            null,
            false,
            false,
            'push',
            true,
          ),
          (
            'unchanged',
            series(true),
            series(true),
            series(true),
            false,
            false,
            'keep',
            true,
          ),
          (
            'removed on the iPhone',
            series(true),
            series(false),
            series(true),
            false,
            false,
            'push',
            false,
          ),
          (
            'removed on the server',
            series(true),
            series(true),
            series(false),
            false,
            false,
            'apply',
            false,
          ),
          (
            'removed on both',
            series(true),
            series(false),
            series(false),
            true,
            true,
            'keep',
            false,
          ),
          (
            'added on both',
            series(false),
            series(true),
            series(true),
            false,
            false,
            'keep',
            true,
          ),
          // Reading wins.
          (
            'removed on the iPhone, read on the server',
            series(true),
            series(false),
            series(true),
            false,
            true,
            'apply',
            true,
          ),
          (
            'removed on the server, read on the iPhone',
            series(true),
            series(true),
            series(false),
            true,
            false,
            'push',
            true,
          ),
          (
            'removed and read on the same side',
            series(true),
            series(false),
            series(true),
            true,
            false,
            'push',
            false,
          ),
          (
            'removed on the server, read on the server',
            series(true),
            series(true),
            series(false),
            false,
            true,
            'apply',
            false,
          ),
          (
            'unknown here, read there',
            null,
            null,
            series(true),
            false,
            true,
            'apply',
            true,
          ),
        ];
    for (final (
          name,
          base,
          local,
          remote,
          localRead,
          remoteRead,
          expected,
          inLibrary,
        )
        in rows) {
      test(name, () {
        final outcome = mergeSeries(
          base: base,
          local: local,
          remote: remote,
          localReadSinceBase: localRead,
          remoteReadSinceBase: remoteRead,
        );
        expect(kind(outcome), expected);
        expect(outcome.value?.inLibrary, inLibrary);
      });
    }

    group('first sync, membership differs', () {
      test('the newer change wins', () {
        final outcome = mergeSeries(
          base: null,
          local: series(true, const {}, t0),
          remote: series(false, const {}, t1),
        );
        expect((kind(outcome), outcome.value!.inLibrary), ('apply', false));
        final reversed = mergeSeries(
          base: null,
          local: series(false, const {}, t1),
          remote: series(true, const {}, t0),
        );
        expect((kind(reversed), reversed.value!.inLibrary), ('push', false));
      });

      test('times that cannot tell keep the series', () {
        for (final (localAt, remoteAt) in [
          (null, t1),
          (t0, t0.add(const Duration(seconds: 2))),
        ]) {
          final outcome = mergeSeries(
            base: null,
            local: series(false, const {}, localAt),
            remote: series(true, const {}, remoteAt),
          );
          expect((kind(outcome), outcome.value!.inLibrary), ('apply', true));
        }
      });
    });

    group('categories merge per name', () {
      final rows =
          <
            (
              String,
              Set<String>?,
              Set<String>,
              Set<String>,
              String,
              Set<String>,
            )
          >[
            (
              'added on the iPhone',
              {'a'},
              {'a', 'b'},
              {'a'},
              'push',
              {'a', 'b'},
            ),
            (
              'removed on the server',
              {'a', 'b'},
              {'a', 'b'},
              {'a'},
              'apply',
              {'a'},
            ),
            (
              'added here, removed there',
              {'a', 'b'},
              {'a', 'b', 'c'},
              {'a'},
              'both',
              {'a', 'c'},
            ),
            (
              'the same change on both',
              {'a'},
              {'a', 'b'},
              {'a', 'b'},
              'keep',
              {'a', 'b'},
            ),
            ('first sync unions', null, {'a'}, {'b'}, 'both', {'a', 'b'}),
          ];
      for (final (name, base, local, remote, expected, result) in rows) {
        test(name, () {
          final outcome = mergeSeries(
            base: base == null ? null : series(true, base),
            local: series(true, local),
            remote: series(true, remote),
          );
          expect(kind(outcome), expected);
          expect(outcome.value!.categories, result);
        });
      }
    });

    test('times alone are not a difference', () {
      final outcome = mergeSeries(
        base: series(true),
        local: series(true, const {'a'}, t0),
        remote: series(true, const {'a'}, t1),
      );
      expect(kind(outcome), 'keep');
    });

    test('keeps the later change time', () {
      final outcome = mergeSeries(
        base: series(true),
        local: series(false, const {}, t1),
        remote: series(true, const {}, t0),
      );
      expect(outcome.value!.changedAt, t1);
    });
  });

  group('mergeChapter', () {
    const unread = ChapterState();
    ChapterState state({
      bool read = false,
      int page = 0,
      bool bookmarked = false,
      DateTime? readAt,
    }) => ChapterState(
      read: read,
      page: page,
      bookmarked: bookmarked,
      readAt: readAt,
    );

    final rows =
        <
          (
            String,
            ChapterState?,
            ChapterState,
            ChapterState,
            String,
            ChapterState,
          )
        >[
          ('unchanged', unread, unread, unread, 'keep', unread),
          (
            'read on the iPhone',
            unread,
            state(read: true),
            unread,
            'push',
            state(read: true),
          ),
          (
            'unread on the server',
            state(read: true),
            state(read: true),
            unread,
            'apply',
            unread,
          ),
          (
            'page on the server',
            unread,
            unread,
            state(page: 4),
            'apply',
            state(page: 4),
          ),
          (
            'bookmark here, read there',
            unread,
            state(bookmarked: true),
            state(read: true),
            'both',
            state(read: true, bookmarked: true),
          ),
          (
            'unbookmarked on the iPhone',
            state(bookmarked: true),
            unread,
            state(bookmarked: true),
            'push',
            unread,
          ),
          (
            'first sync, bookmark on one side',
            null,
            state(bookmarked: true),
            unread,
            'push',
            state(bookmarked: true),
          ),
          (
            'first sync, read times cannot tell',
            null,
            state(read: true),
            unread,
            'push',
            state(read: true),
          ),
          (
            'first sync, newer unread wins',
            null,
            state(read: true, readAt: t0),
            state(readAt: t1),
            'apply',
            state(readAt: t1),
          ),
          (
            'first sync, newer read wins',
            null,
            state(readAt: t1),
            state(read: true, readAt: t0),
            'push',
            state(readAt: t1),
          ),
          (
            'page: the newer read wins',
            state(page: 2),
            state(page: 5, readAt: t0),
            state(page: 7, readAt: t1),
            'apply',
            state(page: 7, readAt: t1),
          ),
          (
            'page: the newer read wins (iPhone)',
            state(page: 2),
            state(page: 5, readAt: t1),
            state(page: 7, readAt: t0),
            'push',
            state(page: 5, readAt: t1),
          ),
          (
            'page: times cannot tell, furthest wins',
            state(page: 2),
            state(page: 9),
            state(page: 7),
            'push',
            state(page: 9),
          ),
          (
            'history keeps the latest read',
            state(readAt: t0),
            state(readAt: t1),
            state(readAt: t0),
            'push',
            state(readAt: t1),
          ),
          (
            'history only grows',
            state(readAt: t0),
            unread,
            state(readAt: t0),
            'apply',
            state(readAt: t0),
          ),
        ];
    for (final (name, base, local, remote, expected, result) in rows) {
      test(name, () {
        final outcome = mergeChapter(base: base, local: local, remote: remote);
        expect(kind(outcome), expected);
        expect(outcome.value, result);
      });
    }
  });

  group('mergeSeriesMeta', () {
    const empty = SeriesMeta();
    final rows =
        <
          (
            String,
            SeriesMeta?,
            SeriesMeta,
            SeriesMeta,
            DateTime?,
            DateTime?,
            String,
            SeriesMeta,
          )
        >[
          ('unchanged', empty, empty, empty, null, null, 'keep', empty),
          (
            'rating on the iPhone',
            empty,
            const SeriesMeta(rating: 4),
            empty,
            null,
            null,
            'push',
            const SeriesMeta(rating: 4),
          ),
          (
            'agreed empty rating, set on the server',
            empty,
            empty,
            const SeriesMeta(rating: 3),
            null,
            null,
            'apply',
            const SeriesMeta(rating: 3),
          ),
          (
            'rating here, notes there',
            empty,
            const SeriesMeta(rating: 4),
            const SeriesMeta(notes: 'n'),
            null,
            null,
            'both',
            const SeriesMeta(rating: 4, notes: 'n'),
          ),
          (
            'notes cleared on the server',
            const SeriesMeta(notes: 'n'),
            const SeriesMeta(notes: 'n'),
            empty,
            null,
            null,
            'apply',
            empty,
          ),
          (
            'tag order counts',
            const SeriesMeta(tags: ['a', 'b']),
            const SeriesMeta(tags: ['b', 'a']),
            const SeriesMeta(tags: ['a', 'b']),
            null,
            null,
            'push',
            const SeriesMeta(tags: ['b', 'a']),
          ),
          (
            'conflict, server changed later',
            const SeriesMeta(rating: 1),
            const SeriesMeta(rating: 2),
            const SeriesMeta(rating: 3),
            t0,
            t1,
            'apply',
            const SeriesMeta(rating: 3),
          ),
          (
            'conflict, iPhone changed later',
            const SeriesMeta(rating: 1),
            const SeriesMeta(rating: 2),
            const SeriesMeta(rating: 3),
            t1,
            t0,
            'push',
            const SeriesMeta(rating: 2),
          ),
          (
            'conflict, times unknown: iPhone wins',
            const SeriesMeta(tags: ['a']),
            const SeriesMeta(tags: ['b']),
            const SeriesMeta(tags: ['c']),
            null,
            t1,
            'push',
            const SeriesMeta(tags: ['b']),
          ),
          (
            'first sync, both set',
            null,
            const SeriesMeta(notes: 'x'),
            const SeriesMeta(notes: 'y'),
            t0,
            t1,
            'apply',
            const SeriesMeta(notes: 'y'),
          ),
        ];
    for (final (name, base, local, remote, localAt, remoteAt, expected, result)
        in rows) {
      test(name, () {
        final outcome = mergeSeriesMeta(
          base: base,
          local: local,
          remote: remote,
          localChangedAt: localAt,
          remoteChangedAt: remoteAt,
        );
        expect(kind(outcome), expected);
        expect(outcome.value, result);
      });
    }
  });

  group('mergeReaderMeta', () {
    bool owns(String key) => key.startsWith('kuchie_');
    const mode = 'kuchie_reader_mode';
    const zoom = 'kuchie_reader_zoom';
    const webUi = 'webui_reader_mode';

    final rows =
        <
          (
            String,
            Map<String, String>?,
            Map<String, String>,
            Map<String, String>,
            DateTime?,
            DateTime?,
            String,
            Map<String, String>,
          )
        >[
          (
            'unchanged',
            {mode: 'rtl'},
            {mode: 'rtl'},
            {mode: 'rtl'},
            null,
            null,
            'keep',
            {mode: 'rtl'},
          ),
          (
            'changed on the iPhone',
            {mode: 'rtl'},
            {mode: 'ltr'},
            {mode: 'rtl'},
            null,
            null,
            'push',
            {mode: 'ltr'},
          ),
          (
            'added on the server',
            {},
            {},
            {zoom: '2'},
            null,
            null,
            'apply',
            {zoom: '2'},
          ),
          (
            'deleted on the iPhone',
            {mode: 'rtl'},
            {},
            {mode: 'rtl'},
            null,
            null,
            'push',
            {},
          ),
          (
            'different keys on each side',
            {},
            {mode: 'ltr'},
            {zoom: '2'},
            null,
            null,
            'both',
            {mode: 'ltr', zoom: '2'},
          ),
          (
            'conflict, server later',
            {mode: 'rtl'},
            {mode: 'ltr'},
            {mode: 'webtoon'},
            t0,
            t1,
            'apply',
            {mode: 'webtoon'},
          ),
          (
            'conflict, times unknown',
            {mode: 'rtl'},
            {mode: 'ltr'},
            {mode: 'webtoon'},
            null,
            null,
            'push',
            {mode: 'ltr'},
          ),
          (
            'first sync conflict',
            null,
            {mode: 'ltr'},
            {mode: 'webtoon'},
            null,
            null,
            'push',
            {mode: 'ltr'},
          ),
          // Another client's key is outside the merge: never applied, never
          // deleted, though the iPhone does not have it.
          (
            'other client keys stay out',
            {webUi: 'a'},
            {},
            {webUi: 'b'},
            null,
            null,
            'keep',
            {},
          ),
          (
            'other client keys beside owned ones',
            {mode: 'rtl', webUi: 'a'},
            {mode: 'ltr'},
            {mode: 'rtl', webUi: 'a'},
            null,
            null,
            'push',
            {mode: 'ltr'},
          ),
        ];
    for (final (name, base, local, remote, localAt, remoteAt, expected, result)
        in rows) {
      test(name, () {
        final outcome = mergeReaderMeta(
          base: base == null ? null : ReaderMeta(base),
          local: ReaderMeta(local),
          remote: ReaderMeta(remote),
          owns: owns,
          localChangedAt: localAt,
          remoteChangedAt: remoteAt,
        );
        expect(kind(outcome), expected);
        expect(outcome.value, ReaderMeta(result));
      });
    }
  });
}
