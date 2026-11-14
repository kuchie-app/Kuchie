import 'urls.dart';

const isGooglePlayBuild = bool.fromEnvironment(
  'KUCHIE_GOOGLE_PLAY',
  defaultValue: false,
);

const supportsClientReleaseChecks =
    !isGooglePlayBuild && KuchieLinks.latestReleaseApi != '';
