import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/db_keys.dart';
import '../../../global_providers/global_providers.dart';
import 'onboarding_complete.dart';

enum CollectionMode { local, server }

const _modeKey = 'collectionMode';
final _modesByName = CollectionMode.values.asNameMap();

bool get supportsLocalCollection =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

CollectionMode? readCollectionMode(SharedPreferences preferences) =>
    _modesByName[preferences.getString(_modeKey)];

Future<void> seedCollectionMode(SharedPreferences preferences) async {
  if (!supportsLocalCollection || readCollectionMode(preferences) != null) {
    return;
  }
  if (hasSavedServer(preferences)) {
    await preferences.setString(_modeKey, CollectionMode.server.name);
  } else if (preferences.getBool(DBKeys.onboardingComplete.name) == true) {
    await preferences.setBool(DBKeys.onboardingComplete.name, false);
    await preferences.remove('onboarding.step');
  }
}

final collectionModeProvider =
    NotifierProvider<CollectionModeController, CollectionMode?>(
      CollectionModeController.new,
    );

class CollectionModeController extends Notifier<CollectionMode?> {
  @override
  CollectionMode? build() => supportsLocalCollection
      ? readCollectionMode(ref.watch(sharedPreferencesProvider))
      : CollectionMode.server;

  Future<void> select(CollectionMode mode) async {
    if (!supportsLocalCollection || state == mode) return;
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setString(_modeKey, mode.name);
    if (ref.mounted && readCollectionMode(preferences) == mode) state = mode;
  }
}

final serverCollectionRuntimeEnabledProvider = Provider<bool>((ref) {
  if (!supportsLocalCollection) return true;
  return ref.watch(collectionModeProvider) == CollectionMode.server &&
      ref.watch(onboardingCompleteProvider) == true;
});
