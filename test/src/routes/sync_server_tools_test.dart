import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/routes/router_config.dart';

void main() {
  test('iOS opens the sync server tools, never the Server tab screens', () {
    for (final location in [
      '/more/settings/server',
      '/more/settings/server/network',
      '/more/settings/backup',
      '/more/settings/downloads',
      '/more/settings/tracking',
      '/more/account',
      '/more/account/users',
    ]) {
      expect(isSyncServerToolLocation(location), isTrue, reason: location);
    }
    for (final location in [
      '/library/0',
      '/extension',
      '/more',
      '/more/settings',
      '/more/settings/serverx',
      '/manga/12',
      '/downloads',
    ]) {
      expect(isSyncServerToolLocation(location), isFalse, reason: location);
    }
  });
}
