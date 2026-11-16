// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../../auth/data/credential_snapshot.dart';
import '../../../auth/data/secure_credentials_provider.dart';

part 'basic_auth_credentials.g.dart';

@Riverpod(keepAlive: true)
class Credentials extends _$Credentials {
  @override
  Future<String?> build() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final vault = credentialSnapshot(ref.read(secureStorageProvider), prefs);
    await vault.ensureLoaded(prefs);
    return vault[kBasicCredentialsKey];
  }

  /// [forEpoch] discards or undoes writes across a server switch; omit when clearing.
  Future<void> set(String? value, {int? forEpoch}) async {
    await ref.read(authCredentialsStoreProvider.notifier).replaceCredentials((
      epoch,
    ) async {
      await future;
      final credentials = ref.read(authCredentialsStoreProvider.notifier);
      if (epoch != credentials.serverEpoch) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final vault = credentialSnapshot(ref.read(secureStorageProvider), prefs);
      await vault.update({kBasicCredentialsKey: value}, prefs);
      if (epoch != credentials.serverEpoch) {
        // A server switch must not retain the previous server's Basic credential.
        await vault.update({kBasicCredentialsKey: null}, prefs);
        return;
      }
      state = AsyncData(value);
    }, forEpoch: forEpoch);
  }
}
