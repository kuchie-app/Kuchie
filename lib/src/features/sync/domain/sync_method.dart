/// Where the Local library syncs to. Local is always the source of truth;
/// a method only mirrors it.
enum SyncMethod {
  none,
  suwayomi,

  /// After 2.0: needs App Store or TestFlight distribution (spike S6).
  icloud;

  /// The stored name; unknown or missing values mean sync is off.
  static SyncMethod fromName(String? name) =>
      values.firstWhere((method) => method.name == name, orElse: () => none);
}
