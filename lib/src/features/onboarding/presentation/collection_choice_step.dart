import 'package:material_ui/material_ui.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import 'onboarding_motion.dart';

String collectionText(
  BuildContext context,
  String english,
  String indonesian,
) =>
    Localizations.localeOf(context).languageCode == 'id' ? indonesian : english;

/// How a fresh install starts (Kuchie 2.0): the library is always on this
/// iPhone; a Suwayomi server, if there is one, joins through Sync.
enum StartChoice {
  /// Start reading here.
  local,

  /// Start here and connect a Suwayomi server for Sync right away.
  connectServer,
}

class CollectionChoiceStep extends StatelessWidget {
  const CollectionChoiceStep({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.appearance,
  });

  final StartChoice? selected;
  final ValueChanged<StartChoice> onSelected;
  final Widget appearance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        OnboardingEntrance(
          child: Text(
            context.l10n.onboardingWelcomeTitle,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 6),
        OnboardingEntrance(
          delay: const Duration(milliseconds: 90),
          child: Text(
            collectionText(
              context,
              'Your library lives on this iPhone.',
              'Library Anda tersimpan di iPhone ini.',
            ),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 20),
        MangaModeChooser(
          first: MangaChoice(
            label: collectionText(context, 'Start here', 'Mulai di sini'),
            caption: collectionText(
              context,
              'Import comics, add sources, and save chapters on this iPhone.',
              'Impor komik, tambahkan sumber, dan simpan chapter di iPhone ini.',
            ),
            icon: Icons.phone_iphone_rounded,
            art: 'assets/kuchie/splash/kiri-ready.png',
          ),
          second: MangaChoice(
            label: collectionText(context, 'Add a server', 'Tambah server'),
            caption: collectionText(
              context,
              'Have Suwayomi? Sync your library, progress and downloads with it.',
              'Punya Suwayomi? Sinkronkan library, progres, dan unduhan.',
            ),
            icon: Icons.cloud_sync_outlined,
            art: 'assets/kuchie/character/loading.png',
          ),
          selected: switch (selected) {
            StartChoice.local => 0,
            StartChoice.connectServer => 1,
            null => null,
          },
          onSelected: (index) => onSelected(
            index == 0 ? StartChoice.local : StartChoice.connectServer,
          ),
        ),
        const SizedBox(height: 14),
        OnboardingEntrance(
          delay: const Duration(milliseconds: 650),
          child: Text(
            collectionText(
              context,
              'You can connect a server later in More → Sync.',
              'Server bisa dihubungkan nanti di Lainnya → Sinkronisasi.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 6),
        OnboardingEntrance(
          delay: const Duration(milliseconds: 720),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(context.l10n.appearance),
            leading: const Icon(Icons.palette_outlined),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            expansionAnimationStyle: context.motionStyle,
            children: [appearance],
          ),
        ),
      ],
    );
  }
}
