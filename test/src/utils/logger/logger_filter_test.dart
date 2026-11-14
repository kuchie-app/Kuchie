// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/utils/logger/logger.dart';
import 'package:logger/logger.dart' as l;

l.LogEvent _event(l.Level level) => l.LogEvent(level, 'message');

void main() {
  test('release builds keep warnings and errors for the crash log', () {
    final filter = KuchieLogFilter(debug: false);
    expect(filter.shouldLog(_event(l.Level.info)), isFalse);
    expect(filter.shouldLog(_event(l.Level.debug)), isFalse);
    expect(filter.shouldLog(_event(l.Level.warning)), isTrue);
    expect(filter.shouldLog(_event(l.Level.error)), isTrue);
    expect(filter.shouldLog(_event(l.Level.fatal)), isTrue);
  });

  test('debug builds log every level', () {
    final filter = KuchieLogFilter(debug: true);
    expect(filter.shouldLog(_event(l.Level.trace)), isTrue);
    expect(filter.shouldLog(_event(l.Level.info)), isTrue);
    expect(filter.shouldLog(_event(l.Level.error)), isTrue);
  });
}
