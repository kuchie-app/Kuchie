/// What the Library status icon and the Sync page show (design 3.1, 3.8).
sealed class SyncStatus {
  const SyncStatus();
}

/// No sync method is chosen; the Library title shows no icon.
final class SyncOff extends SyncStatus {
  const SyncOff();

  @override
  bool operator ==(Object other) => other is SyncOff;

  @override
  int get hashCode => (SyncOff).hashCode;
}

/// Everything known has been synced.
final class SyncIdle extends SyncStatus {
  const SyncIdle({this.lastSuccessAt});

  final DateTime? lastSuccessAt;

  @override
  bool operator ==(Object other) =>
      other is SyncIdle && other.lastSuccessAt == lastSuccessAt;

  @override
  int get hashCode => Object.hash(SyncIdle, lastSuccessAt);
}

/// A sync cycle is running.
final class SyncInProgress extends SyncStatus {
  const SyncInProgress();

  @override
  bool operator ==(Object other) => other is SyncInProgress;

  @override
  int get hashCode => (SyncInProgress).hashCode;
}

/// The server cannot be reached. Normal away from home, not an error:
/// changes queue up and go out when it is back.
final class SyncWaitingForServer extends SyncStatus {
  const SyncWaitingForServer({this.lastSuccessAt, this.pending = 0});

  final DateTime? lastSuccessAt;

  /// Changes waiting to be sent.
  final int pending;

  /// Unsynced for over a week: the Sync page shows one informational banner.
  bool isStale(DateTime now) =>
      lastSuccessAt != null &&
      now.difference(lastSuccessAt!) > const Duration(days: 7);

  @override
  bool operator ==(Object other) =>
      other is SyncWaitingForServer &&
      other.lastSuccessAt == lastSuccessAt &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(SyncWaitingForServer, lastSuccessAt, pending);
}

/// Local changes are queued and the server is reachable; a cycle will send
/// them shortly.
final class SyncPending extends SyncStatus {
  const SyncPending(this.count) : assert(count > 0);

  final int count;

  @override
  bool operator ==(Object other) =>
      other is SyncPending && other.count == count;

  @override
  int get hashCode => Object.hash(SyncPending, count);
}

/// Sync is paused until the user acts. Only these reasons qualify; anything
/// else retries on its own (design 3.8).
enum SyncActionReason {
  /// Expired login or changed password: "Sign in to the server again".
  loginExpired,

  /// A different or reset server answers at the saved address.
  serverChanged,
}

final class SyncActionNeeded extends SyncStatus {
  const SyncActionNeeded(this.reason);

  final SyncActionReason reason;

  @override
  bool operator ==(Object other) =>
      other is SyncActionNeeded && other.reason == reason;

  @override
  int get hashCode => Object.hash(SyncActionNeeded, reason);
}
