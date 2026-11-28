import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../global_providers/global_providers.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../auth/data/custom_headers_store.dart';
import '../../auth/data/secure_credentials_provider.dart';
import '../../offline/data/background/record_seal.dart';
import '../../settings/data/server_connection/basic_auth_credentials.dart';
import 'sync_engine.dart';
import 'sync_engine_provider.dart';

/// The iOS `BGAppRefreshTask` identifier; also listed in Info.plist under
/// `BGTaskSchedulerPermittedIdentifiers` and registered in AppDelegate.
const kSyncBackgroundTask = 'app.kuchie.reader.sync';

/// How often to ask iOS for a background sync. iOS decides when, if ever
/// (design 4.4: best effort; foreground sync is the main path).
const syncBackgroundFrequency = Duration(minutes: 30);

/// Asks iOS for periodic background syncs while sync is on, and stops
/// asking when it is off.
Future<void> scheduleBackgroundSync(bool enabled) async {
  if (kIsWeb || !Platform.isIOS) return;
  if (enabled) {
    await Workmanager().registerPeriodicTask(
      kSyncBackgroundTask,
      kSyncBackgroundTask,
      frequency: syncBackgroundFrequency,
      initialDelay: syncBackgroundFrequency,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } else {
    await Workmanager().cancelByUniqueName(kSyncBackgroundTask);
  }
}

/// One sync cycle without UI, in the background isolate iOS wakes. Returns
/// whether iOS should count the run as a success.
Future<bool> runBackgroundSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
  try {
    // Credentials the sync client reads, loaded as main() does.
    await RecordSeal.load(container.read(secureStorageProvider));
    await container.read(authCredentialsStoreProvider.future);
    await container.read(credentialsProvider.future);
    await container.read(customHttpHeadersProvider.future);
    final engine = container.read(syncEngineProvider);
    if (!engine.enabled) return true;
    final report = await engine.sync();
    return report.outcome != SyncOutcome.failed;
  } catch (_) {
    return false;
  } finally {
    container.dispose();
  }
}
