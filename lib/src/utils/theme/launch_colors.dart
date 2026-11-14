// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui';

/// Matches the backgroundColor in ios/Runner/Base.lproj/LaunchScreen.storyboard
/// so the Flutter splash continues the native launch screen without a flash.
/// The splash draws before any app theme exists, so it cannot use a scheme role.
const kLaunchScreenBackground = Color(0xFF0B0D1A);
