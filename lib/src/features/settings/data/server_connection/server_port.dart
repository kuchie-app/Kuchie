// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../constants/db_keys.dart';
import '../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../offline/data/background/background_download_controller_shim.dart';
import 'server_url.dart';

part 'server_port.g.dart';

@riverpod
class ServerPort extends _$ServerPort with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.serverPort);

  @override
  Future<void> update(int? value) async {
    if (value == state) return;
    final lease = ref.keepAlive();
    try {
      await ref.read(backgroundDownloadControllerProvider).changeIdentity(
        () async {
          await clearCredentialsForServerChange(ref);
          super.update(value);
        },
      );
    } finally {
      lease.close();
    }
  }
}

@riverpod
class ServerPortToggle extends _$ServerPortToggle
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(
    DBKeys.serverPortToggle,
    initial: kIsWeb ? false : DBKeys.serverPortToggle.initial,
  );

  @override
  Future<void> update(bool? value) async {
    if (value == state) return;
    final lease = ref.keepAlive();
    try {
      await ref.read(backgroundDownloadControllerProvider).changeIdentity(
        () async {
          await clearCredentialsForServerChange(ref);
          super.update(value);
        },
      );
    } finally {
      lease.close();
    }
  }
}
