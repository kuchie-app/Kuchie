import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:kuchie/src/constants/db_keys.dart';
import 'package:kuchie/src/constants/enum.dart';
import 'package:kuchie/src/features/auth/data/auth_credentials_store.dart';
import 'package:kuchie/src/features/offline/data/offline_server_identity.dart';
import 'package:kuchie/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:kuchie/src/features/settings/data/server_connection/basic_auth_credentials.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_sync_client.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StoredBasic extends Credentials {
  @override
  Future<String?> build() async => 'Basic c3Bpa2U6cGFzcw==';
}

/// A loopback stand-in for Suwayomi's GraphQL endpoint that records each
/// request and answers the identity query.
class FakeSuwayomi {
  late final HttpServer server;
  final requests =
      <({String path, Map<String, String> headers, String body})>[];

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      final headers = <String, String>{};
      request.headers.forEach(
        (name, values) => headers[name] = values.join(','),
      );
      requests.add((path: request.uri.path, headers: headers, body: body));
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'data': {
              '__typename': 'Query',
              'metas': {
                '__typename': 'GlobalMetaNodeList',
                'nodes': [
                  {
                    '__typename': 'GlobalMetaType',
                    'key': kKuchieServerIdMetaKey,
                    'value': 'id-1',
                  },
                ],
              },
            },
          }),
        );
      await request.response.close();
    });
  }
}

void main() {
  group('syncServerAddresses', () {
    test('main first, then the LAN address', () {
      expect(
        syncServerAddresses(
          main: 'https://manga.example.com/',
          lan: 'http://192.168.1.20',
        ),
        ['https://manga.example.com', 'http://192.168.1.20'],
      );
    });

    test('drops a LAN address that is missing or the same', () {
      expect(syncServerAddresses(main: 'http://192.168.1.20'), [
        'http://192.168.1.20',
      ]);
      expect(syncServerAddresses(main: 'http://192.168.1.20', lan: ''), [
        'http://192.168.1.20',
      ]);
      expect(
        syncServerAddresses(
          main: 'http://192.168.1.20/',
          lan: 'http://192.168.1.20',
        ),
        ['http://192.168.1.20'],
      );
    });

    test('falls back to the default address', () {
      expect(syncServerAddresses(), hasLength(1));
    });
  });

  test('builds one client per address', () {
    final built = <String>[];
    final client = SuwayomiSyncClient(
      addresses: const ['a', 'b'],
      build: (base) {
        built.add(base);
        return GraphQLClient(
          link: HttpLink('http://$base'),
          cache: GraphQLCache(),
        );
      },
    );
    expect(identical(client.at('a'), client.at('a')), isTrue);
    client.at('b');
    expect(built, ['a', 'b']);
  });

  group('suwayomiSyncClientProvider', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late FakeSuwayomi fake;

    setUp(() async {
      // The test binding answers every HTTP request with 400; these tests
      // talk to a real loopback server instead.
      final mocked = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = mocked);
      fake = FakeSuwayomi();
      await fake.start();
      addTearDown(() => fake.server.close(force: true));
    });

    Future<ProviderContainer> containerFor(
      AuthType authType, {
      List<Override> overrides = const [],
    }) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        DBKeys.serverExternalUrl.name: 'http://127.0.0.1',
        DBKeys.serverPort.name: fake.server.port,
        DBKeys.serverPortToggle.name: true,
        DBKeys.authType.name: authType.index,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides,
        ],
      );
      addTearDown(container.dispose);
      await container.read(authCredentialsStoreProvider.future);
      return container;
    }

    Future<String?> readIdentity(ProviderContainer container) {
      final client = container.read(suwayomiSyncClientProvider);
      return OfflineServerIdentityRepository(
        client.at(client.addresses.first),
      ).read();
    }

    test('talks to the configured address without auth', () async {
      final container = await containerFor(AuthType.none);
      expect(container.read(suwayomiSyncClientProvider).addresses, [
        'http://127.0.0.1',
      ]);
      expect(await readIdentity(container), 'id-1');
      final request = fake.requests.single;
      expect(request.path, '/api/graphql');
      expect(request.headers['content-type'], contains('application/json'));
      expect(request.headers.containsKey('authorization'), isFalse);
    });

    test('sends the stored Basic credentials', () async {
      final container = await containerFor(
        AuthType.basic,
        overrides: [credentialsProvider.overrideWith(StoredBasic.new)],
      );
      await container.read(credentialsProvider.future);
      expect(await readIdentity(container), 'id-1');
      expect(
        fake.requests.single.headers['authorization'],
        'Basic c3Bpa2U6cGFzcw==',
      );
    });

    test(
      'sends the UI login access token while the Server collection is off',
      () async {
        final container = await containerFor(AuthType.uiLogin);
        final store = container.read(authCredentialsStoreProvider.notifier);
        await store.withIdentityChange(() async {
          await store.saveUiLoginTokens(accessToken: 'A', refreshToken: 'R');
        });
        expect(await readIdentity(container), 'id-1');
        expect(fake.requests.single.headers['authorization'], 'Bearer A');
      },
    );
  });
}
