import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/auth/data/auth_coordinator.dart';
import 'package:kuchie/src/features/offline/data/offline_server_identity.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_reachability.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_sync_client.dart';
import 'package:kuchie/src/features/sync/data/sync_state_store.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const main_ = 'https://manga.example.com';
const backup = 'http://192.168.1.20';

OperationException unauthorized() => OperationException(
  graphqlErrors: [
    const GraphQLError(
      message: 'Exception while fetching data (/metas) : Unauthorized',
    ),
  ],
);

/// Answers per address: an identity, or an error to throw.
ServerIdentityReader reader(Map<String, Object?> answers, List<String> calls) =>
    (address) async {
      calls.add(address);
      final answer = answers[address];
      if (answer is Exception || answer is Error) throw answer!;
      return answer as String?;
    };

void main() {
  group('SuwayomiReachabilityProbe', () {
    Future<(SuwayomiReachability, List<String>)> probe(
      Map<String, Object?> answers, {
      String? expected = 'id-1',
    }) async {
      final calls = <String>[];
      final result = await SuwayomiReachabilityProbe(
        addresses: const [main_, backup],
        readIdentity: reader(answers, calls),
        expectedIdentity: expected,
        perAddressTimeout: const Duration(milliseconds: 50),
      ).probe();
      return (result, calls);
    }

    test('the main address answers', () async {
      final (result, calls) = await probe({main_: 'id-1'});
      expect(result, isA<SuwayomiReachable>());
      result as SuwayomiReachable;
      expect((result.baseUrl, result.serverIdentity), (main_, 'id-1'));
      expect(calls, [main_]);
    });

    test(
      'falls back to the backup address when the main one is down',
      () async {
        final (result, calls) = await probe({
          main_: const SocketException('No route to host'),
          backup: 'id-1',
        });
        expect((result as SuwayomiReachable).baseUrl, backup);
        expect(calls, [main_, backup]);
      },
    );

    test('a main address that never answers times out to the backup', () async {
      final calls = <String>[];
      final result = await SuwayomiReachabilityProbe(
        addresses: const [main_, backup],
        readIdentity: (address) {
          calls.add(address);
          return address == main_
              ? Completer<String?>().future
              : Future.value('id-1');
        },
        expectedIdentity: 'id-1',
        perAddressTimeout: const Duration(milliseconds: 20),
      ).probe();
      expect((result as SuwayomiReachable).baseUrl, backup);
      expect(calls, [main_, backup]);
    });

    test(
      'unreachable when no address answers, keeping the last error',
      () async {
        final down = const SocketException('Connection refused');
        final (result, calls) = await probe({
          main_: const SocketException('No route to host'),
          backup: down,
        });
        expect(result, isA<SuwayomiUnreachable>());
        expect((result as SuwayomiUnreachable).lastError, down);
        expect(calls, [main_, backup]);
      },
    );

    test(
      'a server that is not Suwayomi counts as that address failing',
      () async {
        final (result, _) = await probe({
          main_: const FormatException('<html>captive portal</html>'),
          backup: 'id-1',
        });
        expect((result as SuwayomiReachable).baseUrl, backup);
      },
    );

    test('refused credentials stop at the first address', () async {
      for (final error in <Object>[
        unauthorized(),
        AccessTokenUnavailable(const RefreshAuthFailure()),
        OperationException(
          linkException: AccessTokenUnavailable(const RefreshAuthFailure()),
        ),
      ]) {
        final (result, calls) = await probe({main_: error, backup: 'id-1'});
        expect(result, isA<SuwayomiAuthFailed>(), reason: '$error');
        expect((result as SuwayomiAuthFailed).baseUrl, main_);
        expect(calls, [main_]);
      }
    });

    test(
      'a refresh that could not reach the server is not an auth failure',
      () async {
        final (result, _) = await probe({
          main_: AccessTokenUnavailable(
            RefreshOutcome.transientFailure(const SocketException('down')),
          ),
          backup: 'id-1',
        });
        expect((result as SuwayomiReachable).baseUrl, backup);
      },
    );

    test('another server at the same address', () async {
      final (result, _) = await probe({main_: 'id-2'});
      result as SuwayomiIdentityChanged;
      expect(
        (result.baseUrl, result.expected, result.actual),
        (main_, 'id-1', 'id-2'),
      );
    });

    test('a reset server has no identity', () async {
      final (result, _) = await probe({main_: null});
      expect((result as SuwayomiIdentityChanged).actual, isNull);
    });

    test('before connecting, any identity is accepted', () async {
      final (result, _) = await probe({main_: null}, expected: null);
      expect((result as SuwayomiReachable).serverIdentity, isNull);
    });

    test('describes itself for the sync log', () {
      expect(
        [
          const SuwayomiReachable(main_, 'a'),
          const SuwayomiUnreachable(),
          const SuwayomiAuthFailed(main_),
          const SuwayomiIdentityChanged(main_, expected: 'a'),
        ].map((r) => '$r'),
        [
          'SuwayomiReachable($main_, a)',
          'SuwayomiUnreachable(null)',
          'SuwayomiAuthFailed($main_)',
          'SuwayomiIdentityChanged($main_, expected a, got null)',
        ],
      );
    });
  });

  group('suwayomiReachabilityProvider', () {
    /// Serves the identity query like Suwayomi, per address.
    GraphQLClient server(FutureOr<Response> Function(Request) answer) =>
        GraphQLClient(
          link: Link.function((request, [forward]) async* {
            yield await answer(request);
          }),
          cache: GraphQLCache(),
          defaultPolicies: DefaultPolicies(
            query: Policies(fetch: FetchPolicy.noCache),
          ),
        );

    Response identity(String value) => Response(
      response: const {},
      data: {
        '__typename': 'Query',
        'metas': {
          '__typename': 'GlobalMetaNodeList',
          'nodes': [
            {
              '__typename': 'GlobalMetaType',
              'key': kKuchieServerIdMetaKey,
              'value': value,
            },
          ],
        },
      },
    );

    Future<SuwayomiReachability> probeWith(
      Map<String, GraphQLClient> servers, {
      String? saved,
    }) async {
      SharedPreferences.setMockInitialValues({
        SyncStateStore.serverIdentityKey: ?saved,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          suwayomiSyncClientProvider.overrideWithValue(
            SuwayomiSyncClient(
              addresses: servers.keys.toList(),
              build: (base) => servers[base]!,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container.read(suwayomiReachabilityProvider).probe();
    }

    test(
      'reads the identity meta and compares it with the saved one',
      () async {
        final requests = <Request>[];
        final result = await probeWith({
          main_: server((request) {
            requests.add(request);
            return identity('id-1');
          }),
        }, saved: 'id-1');
        expect(result, isA<SuwayomiReachable>());
        expect(requests.single.variables, {'key': kKuchieServerIdMetaKey});
      },
    );

    test('an Unauthorized GraphQL error is a login problem', () async {
      final result = await probeWith({
        main_: server(
          (_) => Response(
            response: const {},
            errors: const [
              GraphQLError(
                message:
                    'Exception while fetching data (/metas) : Unauthorized',
              ),
            ],
          ),
        ),
      }, saved: 'id-1');
      expect(result, isA<SuwayomiAuthFailed>());
    });

    test('a connection error moves on to the backup address', () async {
      final result = await probeWith({
        main_: server(
          (_) => throw ServerException(
            originalException: const SocketException('No route to host'),
          ),
        ),
        backup: server((_) => identity('id-2')),
      }, saved: 'id-1');
      result as SuwayomiIdentityChanged;
      expect((result.baseUrl, result.actual), (backup, 'id-2'));
    });
  });
}
