// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/kuchie_character_motion.dart';

class BrowseNoSearchResults extends StatelessWidget {
  const BrowseNoSearchResults({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KuchieCharacterMotion(phase: KuchieCharacterPhase.noResults),
            const SizedBox(height: 16),
            Text(
              context.l10n.noSearchResults,
              style: context.theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.tryDifferentSearchTerm,
              style: context.theme.textTheme.bodyMedium?.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
