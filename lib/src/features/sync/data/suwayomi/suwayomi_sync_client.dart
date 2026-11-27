import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/db_keys.dart';
import '../../../../constants/endpoints.dart';
import '../../../../constants/enum.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/graphql/legacy_user_fields_link.dart';
import '../../../../utils/network/graphql_errors.dart';
import '../../../../utils/network/timeout_http_client.dart';
import '../../../auth/data/auth_coordinator.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../../auth/data/custom_headers_store.dart';
import '../../../auth/data/suwayomi_auth_link.dart';
import '../../../settings/data/server_connection/basic_auth_credentials.dart';
import '../../../settings/data/server_connection/request_timeout.dart';
import '../../../settings/data/server_connection/server_port.dart';
import '../../../settings/data/server_connection/server_url.dart';

/// GraphQL clients for Sync, one per server address.
///
/// Sync runs while the Local library is the app's collection, so it cannot
/// lean on the Server collection's runtime (`AccountSessionStartup`, the
/// endpoint resolver, the unreachable banner). It shares only what is the
/// same server: the address and port settings, the stored credentials, and
/// the auth coordinator's on-demand token refresh, which works without the
/// Server runtime (spike S4: Bearer, Basic and the simple-login cookie all
/// work from a plain HTTP client).
class SuwayomiSyncClient {
  SuwayomiSyncClient({
    required this.addresses,
    required GraphQLClient Function(String baseUrl) build,
  }) : _build = build;

  /// Base URLs to try, in order: the main address, then the backup address
  /// (design 3.8). Never empty.
  final List<String> addresses;

  final GraphQLClient Function(String baseUrl) _build;
  final _clients = <String, GraphQLClient>{};

  /// The client for one of [addresses].
  GraphQLClient at(String baseUrl) => _clients[baseUrl] ??= _build(baseUrl);
}

/// The main address first, then the LAN address when it is set and differs.
List<String> syncServerAddresses({String? main, String? lan}) {
  final ordered = <String>[];
  for (final address in [main ?? DBKeys.serverUrl.initial, lan]) {
    final normalised = normaliseServerUrl(address);
    if (normalised != null && !ordered.contains(normalised)) {
      ordered.add(normalised);
    }
  }
  return ordered;
}

final suwayomiSyncClientProvider = Provider<SuwayomiSyncClient>((ref) {
  final authType = ref.watch(authTypeKeyProvider) ?? DBKeys.authType.initial;
  final timeoutMs =
      ref.watch(serverRequestTimeoutProvider) ??
      DBKeys.serverRequestTimeout.initial;
  final port = ref.watch(serverPortProvider);
  final addPort = ref.watch(serverPortToggleProvider).ifNull();
  // Rebuild on credential changes; values are read per request.
  ref.watch(credentialsProvider);
  ref.watch(customHttpHeadersProvider);

  final httpClients = <TimeoutHttpClient>[];
  ref.onDispose(() {
    for (final client in httpClients) {
      client.close();
    }
  });

  Map<String, String> custom() =>
      ref.read(customHttpHeadersProvider).value ?? const {};

  String endpoint(String baseUrl) => Endpoints.baseApi(
    baseUrl: baseUrl,
    port: port,
    addPort: addPort,
    isGraphQl: true,
  );

  /// Without auth: token refresh must not recurse through the auth link.
  final unauthenticatedClients = <String, GraphQLClient>{};
  GraphQLClient unauthenticated(String baseUrl) =>
      unauthenticatedClients[baseUrl] ??= () {
        final http = TimeoutHttpClient(Duration(milliseconds: timeoutMs));
        httpClients.add(http);
        return GraphQLClient(
          link: HttpLink(
            endpoint(baseUrl),
            httpClient: http,
            httpResponseDecoder: kuchieHttpResponseDecoder,
            defaultHeaders: applyCustomHeaders(const {}, custom()),
          ),
          queryRequestTimeout: Duration(milliseconds: timeoutMs + 2000),
          cache: GraphQLCache(),
          defaultPolicies: DefaultPolicies(
            query: Policies(fetch: FetchPolicy.noCache),
          ),
        );
      }();

  Link? auth(String baseUrl) {
    final coordinator = ref.read(authCoordinatorProvider.notifier);
    switch (authType) {
      case AuthType.none:
        return null;
      case AuthType.basic:
        return AuthLink(
          getToken: () async {
            final stored = await ref.read(credentialsProvider.future);
            return stored.isNotBlank ? stored : null;
          },
        );
      case AuthType.simpleLogin:
      case AuthType.uiLogin:
        return SuwayomiAuthLink(
          authType: () => authType,
          getHeaders: () async {
            final Map<String, String>? base;
            if (authType == AuthType.uiLogin) {
              final token = await coordinator.usableUiAccessToken(
                gqlClient: () => unauthenticated(baseUrl),
                trigger: 'sync',
              );
              base = token == null ? null : {'Authorization': 'Bearer $token'};
            } else {
              final snapshot = await ref.read(
                authCredentialsStoreProvider.future,
              );
              base = snapshot.simpleLoginCookieHeader;
            }
            if (base == null) return custom().isEmpty ? null : {...custom()};
            return applyCustomHeaders({...base}, custom());
          },
          refreshAccessToken: () async => authType != AuthType.uiLogin
              ? const RefreshAuthFailure()
              : coordinator.refreshUiAccessToken(
                  gqlClient: unauthenticated(baseUrl),
                  trigger: 'sync',
                ),
          // The reachability probe reports the failure and the engine pauses
          // with "Sign in again"; the Server collection's banner stays out.
          onNeedsReauth: () {},
        );
    }
  }

  GraphQLClient build(String baseUrl) {
    final http = TimeoutHttpClient(Duration(milliseconds: timeoutMs));
    httpClients.add(http);
    Link link = HttpLink(
      endpoint(baseUrl),
      followRedirects: true,
      httpClient: http,
      httpResponseDecoder: kuchieHttpResponseDecoder,
      defaultHeaders: applyCustomHeaders({
        'Content-Type': 'application/json; charset=utf-8',
      }, custom()),
    );
    if (auth(baseUrl) case final authLink?) link = authLink.concat(link);
    // Older servers (Stable v2.4.2366) have no `user { … }` fields.
    return GraphQLClient(
      link: LegacyUserFieldsLink().concat(link),
      queryRequestTimeout: Duration(milliseconds: timeoutMs + 2000),
      cache: GraphQLCache(),
      defaultPolicies: DefaultPolicies(
        query: Policies(fetch: FetchPolicy.noCache),
        mutate: Policies(fetch: FetchPolicy.noCache),
      ),
    );
  }

  return SuwayomiSyncClient(
    addresses: syncServerAddresses(
      main: ref.watch(serverExternalUrlProvider),
      lan: ref.watch(serverLanUrlProvider),
    ),
    build: build,
  );
});
