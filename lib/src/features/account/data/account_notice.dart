import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../global_providers/global_providers.dart';
import '../../offline/data/offline_server_identity.dart';
import '../../settings/data/server_connection/server_port.dart';
import '../../settings/data/server_connection/server_url.dart';

enum AccountNoticeKind { passwordUnconfirmed, passwordSignInRequired }

final accountNoticeProvider =
    NotifierProvider<AccountNotice, AccountNoticeKind?>(AccountNotice.new);

class AccountNotice extends Notifier<AccountNoticeKind?> {
  late String _key;

  @override
  AccountNoticeKind? build() {
    _key =
        'account.notice/${serverAddress(baseUrl: ref.watch(serverExternalUrlProvider), port: ref.watch(serverPortProvider), addPort: ref.watch(serverPortToggleProvider) ?? false)}';
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    for (final value in AccountNoticeKind.values) {
      if (value.name == saved) return value;
    }
    return null;
  }

  Future<void> set(AccountNoticeKind? notice) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_key, notice?.name ?? '');
    if (ref.mounted) state = notice;
  }
}
