// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/shell/update_banner_state.dart';
import '../data/updates/updates_repository.dart';
import '../domain/update_status/update_status_model.dart';

({bool running, String label}) updateStatusOf(
  AsyncValue<UpdateProgressDto?> progress,
  String idleLabel,
) {
  final running = (progress.value?.isUpdateChecking).ifNull();
  return (
    running: running,
    label: running
        ? "${progress.value?.updateChecked.padLeft()}"
              "/${progress.value?.total.padLeft()}"
        : idleLabel,
  );
}

void toggleLibraryUpdate(WidgetRef ref, bool running) {
  if (running) {
    ref.read(updatesRepositoryProvider).stopUpdates();
  } else {
    ref.read(updateOptimisticProvider.notifier).arm();
    ref.read(updatesRepositoryProvider).fetchUpdates();
  }
}
