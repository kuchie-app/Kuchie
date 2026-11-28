// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:connectivity_plus_linux_portal/connectivity_plus_linux_portal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'src/constants/brand_icons.dart';
import 'src/constants/enum.dart';
import 'src/constants/inter_license.dart';
import 'src/features/account/data/account_bootstrap.dart';
import 'src/features/account/data/account_session_startup.dart';
import 'src/features/account/data/account_session_storage.dart';
import 'src/features/account/presentation/account_session_host.dart';
import 'src/features/auth/data/auth_coordinator.dart';
import 'src/features/auth/data/auth_credentials_store.dart';
import 'src/features/auth/data/auth_recovery_target.dart';
import 'src/features/auth/data/auth_session_transition.dart';
import 'src/features/auth/data/auth_state.dart';
import 'src/features/auth/data/basic_auth_migration.dart';
import 'src/features/auth/data/custom_headers_store.dart';
import 'src/features/auth/data/secure_credentials_provider.dart';
import 'src/features/local_collection/data/local_reading_stats.dart';
import 'src/features/notifications/data/background/notification_background_entry.dart';
import 'src/features/offline/data/account_storage_recovery_state.dart';
import 'src/features/offline/data/background/background_download_controller_shim.dart';
import 'src/features/offline/data/background/catchup_work_spec.dart';
import 'src/features/offline/data/background/record_seal.dart';
import 'src/features/offline/data/download_live_activity.dart';
import 'src/features/offline/data/offline_background_downloads.dart';
import 'src/features/offline/data/offline_download_coordinator.dart';
import 'src/features/offline/data/offline_repository.dart';
import 'src/features/offline/data/offline_runtime_storage.dart';
import 'src/features/offline/data/offline_server_identity_repository.dart';
import 'src/features/onboarding/data/collection_mode.dart';
import 'src/features/onboarding/data/onboarding_complete.dart';
import 'src/features/settings/data/preference_migrations.dart';
import 'src/features/settings/data/server_connection/auth_username.dart';
import 'src/features/settings/data/server_connection/basic_auth_credentials.dart';
import 'src/features/settings/data/server_connection/hosted_base_uri.dart';
import 'src/features/settings/data/server_connection/server_port.dart';
import 'src/features/settings/data/server_connection/server_url.dart';
import 'src/features/tracking/data/tracker_oauth.dart';
import 'src/features/tracking/data/tracker_oauth_browser_stub.dart'
    if (dart.library.js_interop) 'src/features/tracking/data/tracker_oauth_browser_web.dart';
import 'src/global_providers/global_providers.dart';
import 'src/global_providers/package_info.dart';
import 'src/kuchie_app.dart';
import 'src/routes/router_config.dart';
import 'src/utils/crash/crash_log.dart';
import 'src/utils/crash/diagnostics.dart';
import 'src/utils/crash/provider_failure_logger.dart';
import 'src/utils/crash/redact_tokens.dart';
import 'src/utils/desktop/desktop_window.dart';
import 'src/utils/extensions/custom_extensions.dart';
import 'src/utils/hive/graphql_cache_guard.dart';
import 'src/utils/logger/logger.dart';
import 'src/utils/misc/toast/toast.dart';
import 'src/utils/network/graphql_errors.dart';
import 'src/utils/platform/is_flatpak.dart';
import 'src/utils/soft_clear_image_cache.dart';
import 'src/widgets/app_error_app.dart';
import 'src/widgets/cover_cache/cover_cache.dart';
import 'src/widgets/ios/apple_glass_capability.dart';
import 'src/widgets/kuchie_startup_splash.dart';

// Native crash-log path; null on web or initialization failure.
String? _crashLogPath;

bool _appRendered = false;

// Android sends memory-pressure signals on backgrounding; retain a working set of covers.
class _KuchieWidgetsBinding extends WidgetsFlutterBinding {
  @override
  ImageCache createImageCache() => SoftClearImageCache(floorBytes: 64 << 20);

  static WidgetsBinding ensureInitialized() {
    // Must be the first binding created; a second binding construction asserts.
    _KuchieWidgetsBinding();
    return WidgetsBinding.instance;
  }
}

void main() {
  late final Zone startupZone;
  runZonedGuarded<Future<void>>(() {
    startupZone = Zone.current;
    // Only a failure of startup itself is fatal; work it did not await is logged instead.
    return _startApp().catchError(_onFatalError);
  }, (error, stack) => startupZone.run(() => _logCrash(error, stack)));
}

Future<void> _startApp() async {
  final binding = _KuchieWidgetsBinding.ensureInitialized();
  final startupChild = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? ValueNotifier<Widget?>(null)
      : null;
  if (startupChild != null) {
    prepareKuchieStartupFrame(binding);
    final loadingLabel = binding.platformDispatcher.locale.languageCode == 'id'
        ? 'Memuat Kuchie'
        : 'Loading Kuchie';
    runApp(
      ValueListenableBuilder<Widget?>(
        valueListenable: startupChild,
        builder: (_, child, _) => KuchieStartupSplash(
          ready: child != null,
          loadingLabel: loadingLabel,
          child: child,
        ),
      ),
    );
  }
  final appleGlassSupport = appleGlassCapability();
  if (kIsWeb) {
    await BrowserContextMenu.disableContextMenu();
  }
  // 256 MiB is a cache cap, not an allocation, and retains covers across tab switches.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  registerBrandIconsLicense();
  registerInterLicense();
  await _setUpCrashReporting();
  // Initialize after the binding and before starting any download service.
  initForegroundTaskService();
  // Android checks for new chapters; iOS runs Sync's background refresh.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    unawaited(Workmanager().initialize(notificationCallbackDispatcher));
  }
  if (isFlatpak) {
    ConnectivityPlusLinuxPortalPlugin.registerWith();
  }
  // Independent platform reads; load them together.
  final (packageInfo, sharedPreferences) = await (
    PackageInfo.fromPlatform(),
    SharedPreferences.getInstance(),
  ).wait;
  _logBoot(
    'start v${packageInfo.version}+${packageInfo.buildNumber} '
    '(${defaultTargetPlatform.name})',
  );
  // Restore the desktop window before the first frame.
  await initDesktopWindow(sharedPreferences);
  final legacyBoxBytes = await deleteLegacyGraphqlCacheBox();
  if (legacyBoxBytes != null) {
    _logBoot('deleted legacy graphql cache box: $legacyBoxBytes bytes');
  }

  unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
  GoRouter.optionURLReflectsImperativeAPIs = true;

  final container = _createSessionContainer(packageInfo, sharedPreferences);

  final secure = container.read(secureStorageProvider);

  // Load the seal key before any background credential reads or writes.
  if (!await RecordSeal.load(secure, create: true)) {
    _logBoot('background credentials key unavailable');
  }

  try {
    await migrateBasicAuthCredentials(prefs: sharedPreferences, secure: secure);
  } catch (e, st) {
    debugPrint('basic_auth migration failed: $e\n$st');
  }

  final view = PlatformDispatcher.instance.views.firstOrNull;
  await runPreferenceMigrations(
    sharedPreferences,
    preferenceMigrations(
      windowWidth: view == null
          ? 0
          : view.physicalSize.width / view.devicePixelRatio,
    ),
    onError: (name, error, stack) => logger.w(
      'preference migration $name failed',
      error: error,
      stackTrace: stack,
    ),
  );

  // Preload auth before image requests can cache tokenless 401s; sequential reads avoid repeated keychain prompts.
  try {
    await container.read(authCredentialsStoreProvider.future);
    await container.read(credentialsProvider.future);
    await container.read(customHttpHeadersProvider.future);
  } catch (e, st) {
    debugPrint('auth preload failed, falling back to empty state: $e\n$st');
  }

  try {
    await seedCollectionMode(sharedPreferences);
  } catch (e, st) {
    debugPrint('collection selection migration failed: $e\n$st');
  }

  try {
    await _seedTestConfig(container);
  } catch (e, st) {
    debugPrint('test-config seed failed: $e\n$st');
  }

  await CatchupStateStore(sharedPreferences).setIdentityAuthorized(false);
  var activeContainer = container;
  AccountSessionStartup? startup;
  ProviderSubscription<bool>? runtimeSubscription;
  Future<void>? restoreFlight;

  Future<void> restoreServer(ProviderContainer target) async {
    try {
      await restoreAccountSession(target);
      _logBoot(
        target.read(offlineEnabledProvider)
            ? 'offline storage ready'
            : 'offline off',
      );
    } catch (error, stack) {
      debugPrint('account storage initialization failed: $error\n$stack');
      _logBoot(
        'account storage initialization failed: ${redactTokens('$error')}',
      );
    }
  }

  void startServerServices(ProviderContainer target) {
    if (activeContainer != target ||
        !target.read(serverCollectionRuntimeEnabledProvider) ||
        startup != null) {
      return;
    }
    target.read(authCoordinatorProvider.notifier);
    startup = AccountSessionStartup(target)..start();
  }

  void watchServerRuntime(ProviderContainer target) {
    runtimeSubscription = target.listen(
      serverCollectionRuntimeEnabledProvider,
      (_, enabled) {
        if (!enabled) {
          startup?.dispose();
          startup = null;
          return;
        }
        unawaited(() async {
          await (restoreFlight ??= restoreServer(target));
          startServerServices(target);
        }());
      },
    );
  }

  if (container.read(serverCollectionRuntimeEnabledProvider)) {
    container.read(authCoordinatorProvider.notifier);
    await (restoreFlight = restoreServer(container));
  }
  container.read(authCredentialsStoreProvider.notifier).activateSession();
  startServerServices(container);
  watchServerRuntime(container);
  if (startupChild == null) {
    _setupDeepLinkListener(() => activeContainer);
  }

  Future<ProviderContainer> restartSession(ProviderContainer previous) async {
    startup?.dispose();
    startup = null;
    runtimeSubscription?.close();
    await restoreFlight;
    previous.read(offlineDownloadCoordinatorProvider)?.pause();
    await previous.read(backgroundDownloadControllerProvider).detachStorage();
    await OfflineDownloadCoordinator.stopAll();
    final oldStorage = previous.read(offlineRuntimeStorageProvider.notifier);
    await oldStorage.drain();
    await previous.read(authCredentialsStoreProvider.notifier).retire();
    final next = _createSessionContainer(
      packageInfo,
      sharedPreferences,
      coverCache: previous.read(coverCacheManagerProvider),
    );
    OfflineStorage? transferred;
    try {
      await Future.wait([
        next.read(authCredentialsStoreProvider.future),
        next.read(credentialsProvider.future),
        next.read(customHttpHeadersProvider.future),
      ]);
      next
          .read(authRecoveryTargetProvider.notifier)
          .set(previous.read(authRecoveryTargetProvider));
      next
          .read(needsReauthProvider.notifier)
          .set(previous.read(needsReauthProvider));
      await CatchupStateStore(sharedPreferences).setIdentityAuthorized(false);
      next
          .read(accountStorageRecoveryProvider.notifier)
          .update(previous.read(accountStorageRecoveryProvider));
      transferred = oldStorage.take();
      await next
          .read(offlineRuntimeStorageProvider.notifier)
          .replace(drain: () async {}, open: () async => transferred);
      next.read(authCredentialsStoreProvider.notifier).activateSession();
      activeContainer = next;
      restoreFlight = Future.value();
      startServerServices(next);
      watchServerRuntime(next);
      return next;
    } catch (_) {
      startup?.dispose();
      startup = null;
      runtimeSubscription?.close();
      try {
        final runtime = next.read(offlineRuntimeStorageProvider.notifier);
        if (next.read(offlineRuntimeStorageProvider) == null) {
          await transferred?.db.close();
        } else {
          await runtime.replace(
            drain: runtime.whenIdle,
            open: () async => null,
          );
        }
      } finally {
        next.dispose();
      }
      rethrow;
    }
  }

  Future<void> retainSession(ProviderContainer retained) async {
    startup?.dispose();
    startup = null;
    retained.read(authCredentialsStoreProvider.notifier).activateSession();
    final current = retained
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    await retained.read(offlineRuntimeStorageProvider.notifier).whenIdle();
    if (!current() || activeContainer != retained) return;
    retained.invalidate(backgroundDownloadControllerProvider);
    startServerServices(retained);
  }

  final glassCapability = await appleGlassSupport;
  _logBoot('runApp');
  final app = AccountSessionHost(
    initialContainer: container,
    restart: restartSession,
    onRetained: retainSession,
    sessionKey: (session) {
      final credentials = session.read(authCredentialsStoreProvider).value;
      return (
        session.read(authTypeKeyProvider),
        session.read(currentServerAddressProvider),
        session.read(credentialsProvider).value,
        credentials?.accountBinding,
        credentials?.uiAccessToken,
        credentials?.uiRefreshToken,
        credentials?.simpleLoginCookie,
        session.read(offlineRuntimeStorageProvider),
      );
    },
    builder: (changing) =>
        KuchieApp(glassCapability: glassCapability, sessionChanging: changing),
    loading: AccountSessionLoading(glassCapability: glassCapability),
    errorBuilder: (error) =>
        AppErrorApp(message: redactTokens('$error'), logPath: _crashLogPath),
  );
  // Read in the background; History in both collections shows reading time.
  unawaited(LocalReadingStats.instance.load());
  if (startupChild == null) {
    runApp(app);
  } else {
    startupChild.value = app;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _appRendered = true;
    _logBoot('first frame');
    if (startupChild != null) {
      _setupDeepLinkListener(() => activeContainer);
    }
  });
}

ProviderContainer _createSessionContainer(
  PackageInfo packageInfo,
  SharedPreferences preferences, {
  CacheManager? coverCache,
}) => ProviderContainer(
  observers: [ProviderFailureLogger()],
  retry: (retryCount, error) => isConnectionError(error)
      ? null
      : ProviderContainer.defaultRetry(retryCount, error),
  overrides: [
    packageInfoProvider.overrideWithValue(packageInfo),
    sharedPreferencesProvider.overrideWithValue(preferences),
    if (coverCache != null)
      coverCacheManagerProvider.overrideWithValue(coverCache),
    authSessionTransitionProvider.overrideWith(
      (ref) => ref.read(accountSessionStorageProvider),
    ),
  ],
);

void _logBoot(String stage) {
  writeCrashLog(
    _crashLogPath,
    '[${DateTime.now().toIso8601String()}] boot: $stage\n',
  );
}

// Error handlers must never throw while reporting a startup failure.
Future<void> _setUpCrashReporting() async {
  _crashLogPath = await initCrashLog();
  setDiagnosticSink((line) => writeCrashLog(_crashLogPath, line));
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _logCrash(details.exception, details.stack);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    _logCrash(error, stack);
    return true;
  };
  ErrorWidget.builder = (details) => AppErrorApp(
    message: redactTokens(details.exceptionAsString()),
    logPath: _crashLogPath,
  );
}

void _logCrash(Object error, StackTrace? stack) {
  // Some exceptions have empty toString(); retain their runtime type.
  final body = redactTokens('${error.runtimeType}: $error\n$stack');
  debugPrint('Kuchie error: $body');
  writeCrashLog(
    _crashLogPath,
    '[${DateTime.now().toIso8601String()}] $body\n\n',
  );
}

void _onFatalError(Object error, StackTrace stack) {
  _logCrash(error, stack);
  // After the first frame, a late startup failure must not replace the running app.
  if (_appRendered) return;
  try {
    runApp(
      AppErrorApp(
        message: redactTokens(error.toString()),
        logPath: _crashLogPath,
      ),
    );
  } catch (_) {}
}

void _setupDeepLinkListener(ProviderContainer Function() currentContainer) {
  var downloadOpenRequest = 0;
  Future<void> handleUri(Uri uri) async {
    if (isDownloadLiveActivityLink(uri)) {
      final tab = uri.queryParameters['tab'];
      Future<void> openDownloads() async {
        final target = currentContainer();
        if (supportsLocalCollection) {
          final modes = target.read(collectionModeProvider.notifier);
          if (tab == 'local') {
            await modes.select(CollectionMode.local);
            if (currentContainer() == target) {
              target
                  .read(routerConfigProvider)
                  .go(
                    localCollectionLocation('downloads', ++downloadOpenRequest),
                  );
            }
            return;
          }
          if (target.read(onboardingCompleteProvider) != true) return;
          await modes.select(CollectionMode.server);
          if (currentContainer() != target) return;
        }
        target
            .read(routerConfigProvider)
            .go(
              '${const DownloadsRoute().location}?tab=$tab&open=${++downloadOpenRequest}',
            );
      }

      if (_appRendered) {
        await openDownloads();
      } else {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(openDownloads()),
        );
      }
      return;
    }
    final container = currentContainer();
    if (!container.read(serverCollectionRuntimeEnabledProvider)) return;
    final current = container
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    if (!current()) return;
    try {
      final toast = container.read(toastProvider);
      final outcome = await container
          .read(trackerOAuthProvider)
          .handleCallback(uri);
      if (!current()) return;
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      if (outcome == TrackerOAuthOutcome.rejected) {
        toast?.showError(context.l10n.trackerOAuthLinkInvalid);
      } else if (outcome == TrackerOAuthOutcome.failed) {
        toast?.showError(context.l10n.errorSomethingWentWrong);
      }
    } catch (_) {
      debugPrint('Tracker sign-in callback could not be processed');
    }
  }

  if (kIsWeb) {
    final uri = Uri.base;
    final base = Uri.parse(readHostedBaseUri());
    final redirect = Uri.parse(
      currentContainer().read(trackerOAuthProvider).redirect,
    );
    if (uri.path == redirect.path && uri.hasQuery) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await handleUri(uri);
        } finally {
          clearTrackerOAuthUrl(base.toString());
          final context = rootNavigatorKey.currentContext;
          if (context != null && context.mounted) {
            const TrackingSettingsRoute().go(context);
          }
        }
      });
    }
    return;
  }

  final appLinks = AppLinks();
  appLinks
      .getInitialLink()
      .then((uri) {
        // On iOS the stream also delivers the launch URL for Live Activities.
        if (uri != null && !isDownloadLiveActivityLink(uri)) {
          unawaited(handleUri(uri));
        }
      })
      .catchError((e) {
        debugPrint('AppLinks initial link could not be read');
      });

  appLinks.uriLinkStream.listen(
    (uri) => unawaited(handleUri(uri)),
    onError: (_) => debugPrint('AppLinks link stream failed'),
  );
}

Future<void> _seedTestConfig(ProviderContainer container) async {
  if (!kDebugMode) return;
  const url = String.fromEnvironment('TEST_SERVER_URL');
  if (url.isEmpty) return;
  const user = String.fromEnvironment('TEST_USER');
  const pass = String.fromEnvironment('TEST_PASS');

  await container.read(serverExternalUrlProvider.notifier).update(url);
  if (url.startsWith('https')) {
    // Reverse-proxied HTTPS servers need no additional port.
    await container.read(serverPortToggleProvider.notifier).update(false);
  }
  container.read(authTypeKeyProvider.notifier).update(AuthType.uiLogin);
  if (user.isNotEmpty) {
    container.read(authUsernameProvider.notifier).update(user);
  }

  if (pass.isEmpty) return; // server set; user logs in manually if no password.
  await container.read(backgroundDownloadControllerProvider).changeIdentity(
    () async {
      await container
          .read(authCoordinatorProvider.notifier)
          .loginUi(
            gqlClient: container.read(unauthenticatedGraphQlClientProvider),
            username: user,
            password: pass,
            serverBaseUrl: url,
          );
    },
  );
}
