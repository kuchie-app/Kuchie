// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/endpoints.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../widgets/popup_widgets/app_dialog.dart';
import '../../../../../../widgets/popup_widgets/pop_button.dart';
import '../../../../../auth/data/auth_coordinator.dart';
import '../../../../../auth/presentation/auth_failure_text.dart';
import '../../../../../auth/presentation/sign_in_action.dart';
import '../../../../data/server_connection/server_port.dart';
import '../../../../data/server_connection/server_url.dart';

// Keep alive so preloaded credentials remain available to synchronous request builders.
final formKey = GlobalKey<FormState>();

class CredentialsPopup extends HookConsumerWidget {
  const CredentialsPopup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = useTextEditingController();
    final password = useTextEditingController();
    final saving = useState(false);
    final error = useState<String?>(null);
    Future<void> doSave() async {
      if (!(formKey.currentState?.validate()).ifNull()) return;
      saving.value = true;
      error.value = null;
      try {
        await performSignIn(
          ref,
          authType: AuthType.basic,
          serverBaseUrl: Endpoints.baseApi(
            baseUrl: ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial,
            port: ref.read(serverPortProvider),
            addPort: ref.read(serverPortToggleProvider).ifNull(),
            appendApiToUrl: false,
          ),
          username: username.text,
          password: password.text,
        );
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (!context.mounted) return;
        error.value = authFailureText(context, classifyAuthError(e).kind);
      } finally {
        if (context.mounted) saving.value = false;
      }
    }

    return AdaptiveAppAlert(
      title: Text(context.l10n.credentials),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: username,
              validator: (value) =>
                  value.isBlank ? (context.l10n.errorUserName) : null,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: context.l10n.userName,
                border: const OutlineInputBorder(),
              ),
            ),
            const Gap(4),
            TextFormField(
              controller: password,
              validator: (value) =>
                  value.isBlank ? (context.l10n.errorPassword) : null,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => doSave(),
              decoration: InputDecoration(
                hintText: context.l10n.password,
                border: const OutlineInputBorder(),
              ),
            ),
            if (error.value != null) ...[
              const Gap(8),
              Text(
                error.value!,
                style: TextStyle(color: context.theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        const PopButton(),
        ElevatedButton(
          onPressed: saving.value ? null : doSave,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
