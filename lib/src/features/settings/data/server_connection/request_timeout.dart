// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../constants/db_keys.dart';
import '../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'request_timeout.g.dart';

@riverpod
class ServerRequestTimeout extends _$ServerRequestTimeout
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(
    DBKeys.serverRequestTimeout,
    initial: DBKeys.serverRequestTimeout.initial,
  );

  void updateSeconds(int seconds) => update(seconds * 1000);
}

@riverpod
class AutoRefreshOnTimeout extends _$AutoRefreshOnTimeout
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(
    DBKeys.autoRefreshOnTimeout,
    initial: DBKeys.autoRefreshOnTimeout.initial,
  );
}

@riverpod
class AutoRefreshRetryDelay extends _$AutoRefreshRetryDelay
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(
    DBKeys.autoRefreshRetryDelay,
    initial: DBKeys.autoRefreshRetryDelay.initial,
  );

  void updateSeconds(int seconds) => update(seconds * 1000);
}
