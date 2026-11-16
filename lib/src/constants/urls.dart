// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Project and release destinations. They point at the official repository;
/// a fork that publishes its own releases overrides them with `--dart-define`.
abstract final class KuchieLinks {
  static const project = String.fromEnvironment(
    'KUCHIE_PROJECT_URL',
    defaultValue: 'https://github.com/kuchie-app/Kuchie',
  );
  static const releaseNotes = String.fromEnvironment(
    'KUCHIE_RELEASES_URL',
    defaultValue: 'https://github.com/kuchie-app/Kuchie/releases',
  );
  static const latestReleaseApi = String.fromEnvironment(
    'KUCHIE_RELEASE_API_URL',
    defaultValue:
        'https://api.github.com/repos/kuchie-app/Kuchie/releases/latest',
  );
  static const privacyPolicy = String.fromEnvironment('KUCHIE_PRIVACY_URL');
  static const translations = String.fromEnvironment('KUCHIE_TRANSLATIONS_URL');
}

enum AppUrls {
  serverHelp(url: 'https://github.com/Suwayomi/Suwayomi-Server'),
  serverExtensions(
    url: 'https://github.com/Suwayomi/Suwayomi-Server/blob/master/docs/Getting-Extensions.md',
  ),
  serverWebUIReleases(url: 'https://github.com/Suwayomi/Suwayomi-Tsumiru/releases'),
  flareSolverr(
    url: 'https://github.com/FlareSolverr/FlareSolverr?tab=readme-ov-file#installation',
  );

  const AppUrls({required this.url});

  final String url;
}
