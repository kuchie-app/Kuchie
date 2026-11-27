import 'dart:async';

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/network/graphql_errors.dart';
import '../../../auth/data/auth_coordinator.dart';
import '../../../offline/data/offline_server_identity_repository.dart';
import '../sync_state_store.dart';
import 'suwayomi_sync_client.dart';

/// What a sync preflight found at the configured addresses (design 3.8).
sealed class SuwayomiReachability {
  const SuwayomiReachability();
}

/// The server answered with valid credentials.
final class SuwayomiReachable extends SuwayomiReachability {
  const SuwayomiReachable(this.baseUrl, this.serverIdentity);

  /// The address that answered; the cycle uses it for every request.
  final String baseUrl;

  /// The Kuchie instance ID on the server; null on a server Kuchie has not
  /// connected to yet (the connect flow creates it).
  final String? serverIdentity;

  @override
  String toString() => 'SuwayomiReachable($baseUrl, $serverIdentity)';
}

/// No address answered: away from home, offline or the server is down.
/// Normal, not an error; changes stay queued.
final class SuwayomiUnreachable extends SuwayomiReachability {
  const SuwayomiUnreachable([this.lastError]);

  /// The last address's failure, for the sync log.
  final Object? lastError;

  @override
  String toString() => 'SuwayomiUnreachable($lastError)';
}

/// The server refused the stored credentials: expired login or a changed
/// password. Sync pauses until the reader signs in again.
final class SuwayomiAuthFailed extends SuwayomiReachability {
  const SuwayomiAuthFailed(this.baseUrl);

  final String baseUrl;

  @override
  String toString() => 'SuwayomiAuthFailed($baseUrl)';
}

/// A different or reset server answers at the address. Sync pauses and asks
/// whether to reconnect or disconnect; it never merges into another library.
final class SuwayomiIdentityChanged extends SuwayomiReachability {
  const SuwayomiIdentityChanged(
    this.baseUrl, {
    required this.expected,
    this.actual,
  });

  final String baseUrl;
  final String expected;

  /// Null when the server has no Kuchie identity: it was reset.
  final String? actual;

  @override
  String toString() =>
      'SuwayomiIdentityChanged($baseUrl, expected $expected, got $actual)';
}

/// Reads the server's Kuchie identity at one address. Throws when the server
/// cannot be reached or refuses the credentials.
typedef ServerIdentityReader = Future<String?> Function(String baseUrl);

class SuwayomiReachabilityProbe {
  const SuwayomiReachabilityProbe({
    required this.addresses,
    required this.readIdentity,
    this.expectedIdentity,
    this.perAddressTimeout = const Duration(seconds: 6),
  });

  /// In order: main, then backup.
  final List<String> addresses;
  final ServerIdentityReader readIdentity;

  /// The identity saved when the server was connected; null before that.
  final String? expectedIdentity;

  /// Keeps an unanswered main address (a LAN address away from home) from
  /// holding up the backup address for a full request timeout.
  final Duration perAddressTimeout;

  /// Tries each address in turn. Reading the identity needs credentials on a
  /// protected server, so it checks them too; `aboutServer` would not, since
  /// it stays public under every auth mode (spike S4).
  Future<SuwayomiReachability> probe() async {
    Object? lastError;
    for (final address in addresses) {
      final String? identity;
      try {
        identity = await readIdentity(address).timeout(perAddressTimeout);
      } catch (error) {
        if (isSyncAuthFailure(error)) return SuwayomiAuthFailed(address);
        // Anything else is this address failing, a connection error or not
        // (a proxy page, a server that is not Suwayomi); try the next one.
        lastError = error;
        continue;
      }
      final expected = expectedIdentity;
      if (expected != null && identity != expected) {
        return SuwayomiIdentityChanged(
          address,
          expected: expected,
          actual: identity,
        );
      }
      return SuwayomiReachable(address, identity);
    }
    return SuwayomiUnreachable(lastError);
  }
}

/// Whether [error] means the server refused the credentials: an
/// `Unauthorized` GraphQL error (sent with HTTP 200 for expired tokens,
/// spike S4), HTTP 401, Basic auth's anonymous 404, or a UI login whose
/// refresh token was rejected.
bool isSyncAuthFailure(Object error) {
  // Repositories' `getData` wraps the client's exception for display.
  if (error is OperationMessageException) {
    return isSyncAuthFailure(error.exception);
  }
  if (error is AccessTokenUnavailable) {
    return error.outcome is RefreshAuthFailure;
  }
  if (error is OperationException &&
      error.linkException is AccessTokenUnavailable) {
    return isSyncAuthFailure(error.linkException!);
  }
  return isAuthenticationRequired(error) || isBasicGatedNotFound(error);
}

final suwayomiReachabilityProvider = Provider<SuwayomiReachabilityProbe>((ref) {
  final client = ref.watch(suwayomiSyncClientProvider);
  return SuwayomiReachabilityProbe(
    addresses: client.addresses,
    expectedIdentity: ref.watch(syncStateStoreProvider).serverIdentity,
    readIdentity: (baseUrl) =>
        OfflineServerIdentityRepository(client.at(baseUrl)).read(),
  );
});
