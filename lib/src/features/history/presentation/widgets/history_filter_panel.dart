// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'history_filter.dart';

class HistoryFilterPanel extends StatelessWidget {
  const HistoryFilterPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.filter,
                  style: context.theme.textTheme.titleMedium,
                ),
              ),
              const HistoryFilterResetButton(),
            ],
          ),
          const HistoryFilterOptions(),
        ],
      ),
    );
  }
}
