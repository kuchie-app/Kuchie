import 'package:material_ui/material_ui.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../data/collection_mode.dart';
import 'onboarding_motion.dart';

String collectionText(
  BuildContext context,
  String english,
  String indonesian,
) =>
    Localizations.localeOf(context).languageCode == 'id' ? indonesian : english;

String collectionModeLabel(BuildContext context, CollectionMode mode) =>
    mode == CollectionMode.local
    ? collectionText(context, 'Local', 'Lokal')
    : 'Server';

class CollectionChoiceStep extends StatelessWidget {
  const CollectionChoiceStep({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.appearance,
  });

  final CollectionMode? selected;
  final ValueChanged<CollectionMode> onSelected;
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
              'How would you like to read?',
              'Bagaimana Anda ingin membaca?',
            ),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 20),
        MangaModeChooser(
          first: MangaChoice(
            label: collectionModeLabel(context, CollectionMode.local),
            caption: collectionText(
              context,
              'Import comics, add sources, and save chapters on this iPhone.',
              'Impor komik, tambahkan sumber, dan simpan chapter di iPhone ini.',
            ),
            icon: Icons.phone_iphone_rounded,
            art: 'assets/kuchie/splash/kiri-ready.png',
          ),
          second: MangaChoice(
            label: collectionModeLabel(context, CollectionMode.server),
            caption: collectionText(
              context,
              'Connect to a Suwayomi server to read your existing collection.',
              'Hubungkan server Suwayomi untuk membaca koleksi Anda.',
            ),
            icon: Icons.cloud_outlined,
            art: 'assets/kuchie/character/loading.png',
          ),
          selected: switch (selected) {
            CollectionMode.local => 0,
            CollectionMode.server => 1,
            null => null,
          },
          onSelected: (index) => onSelected(
            index == 0 ? CollectionMode.local : CollectionMode.server,
          ),
        ),
        const SizedBox(height: 14),
        OnboardingEntrance(
          delay: const Duration(milliseconds: 650),
          child: Text(
            collectionText(
              context,
              'You can switch anytime. Each mode has its own library.',
              'Mode bisa diganti kapan saja. Koleksi tiap mode terpisah.',
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
