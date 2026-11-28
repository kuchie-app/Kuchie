// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:workmanager/workmanager.dart';

import '../../../sync/controller/sync_background.dart';
import 'notification_worker.dart';

const kNewChapterCheckTask = 'kuchie.newChapterCheck';

// Manual checks need a separate unique-work name to avoid suppressing the periodic schedule.
const kNewChapterPeriodicName = 'kuchie.newChapterCheck.periodic';
const kNewChapterCheckNowName = 'kuchie.newChapterCheck.now';

// Follow-up work uses its own identity while waiting for server downloads, preserving periodic scheduling.
const kNewChapterFollowUpName = 'kuchie.newChapterCheck.followup';

// WorkManager requires a top-level vm:entry-point callback in the new isolate.
// One dispatcher serves every background task: new-chapter checks (Android)
// and Sync's background refresh (iOS).
@pragma('vm:entry-point')
void notificationCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case kNewChapterCheckTask:
        return runNewChapterCheck();
      case kSyncBackgroundTask:
        return runBackgroundSync();
      default:
        return true;
    }
  });
}
