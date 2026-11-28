import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Where the Local library is the app's one collection (Kuchie 2.0): the
/// iOS app, which embeds the Mihon runtime. A Suwayomi server is only ever
/// a sync target there. Other platforms keep the Server collection until
/// they get a Local runtime.
bool get supportsLocalCollection =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Whether the Server collection's runtime (session startup, endpoint
/// resolver, offline storage) runs: never on iOS, where Sync has its own
/// light client (design 4.5).
final serverCollectionRuntimeEnabledProvider = Provider<bool>(
  (ref) => !supportsLocalCollection,
);
