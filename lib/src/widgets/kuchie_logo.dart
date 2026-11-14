// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

import '../constants/gen/assets.gen.dart';

class KuchieLogo extends StatelessWidget {
  const KuchieLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      isDark ? Assets.icons.darkIcon.path : Assets.icons.logoOnLight.path,
      width: size,
      height: size,
    );
  }
}
