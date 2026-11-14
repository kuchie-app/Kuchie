import 'package:material_ui/material_ui.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/kuchie_character_motion.dart';
import '../../../widgets/kuchie_motion_reveal.dart';
import '../data/collection_mode.dart';

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
        Center(
          child: KuchieMotionReveal(
            child: KuchieCharacterMotion(
              phase: KuchieCharacterPhase.intro,
              width: MediaQuery.sizeOf(context).height < 500 ? 92 : 140,
              play: false,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.onboardingWelcomeTitle,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          collectionText(
            context,
            'How would you like to read?',
            'Bagaimana Anda ingin membaca?',
          ),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        _ModePanel(
          title: collectionModeLabel(context, CollectionMode.local),
          description: collectionText(
            context,
            'Import comics, add sources, and save chapters on this iPhone.',
            'Impor komik, tambahkan sumber, dan simpan chapter di iPhone ini.',
          ),
          icon: Icons.phone_iphone_rounded,
          selected: selected == CollectionMode.local,
          onTap: () => onSelected(CollectionMode.local),
        ),
        const SizedBox(height: 10),
        _ModePanel(
          title: collectionModeLabel(context, CollectionMode.server),
          description: collectionText(
            context,
            'Connect to a Suwayomi server to read your existing collection.',
            'Hubungkan server Suwayomi untuk membaca koleksi Anda.',
          ),
          icon: Icons.cloud_outlined,
          selected: selected == CollectionMode.server,
          onTap: () => onSelected(CollectionMode.server),
        ),
        const SizedBox(height: 12),
        Text(
          collectionText(
            context,
            'You can switch anytime. Each mode has its own library.',
            'Mode bisa diganti kapan saja. Koleksi tiap mode terpisah.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(context.l10n.appearance),
          leading: const Icon(Icons.palette_outlined),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          expansionAnimationStyle: context.motionStyle,
          children: [appearance],
        ),
      ],
    );
  }
}

class _ModePanel extends StatelessWidget {
  const _ModePanel({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(20);
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: context.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : colors.surfaceContainer,
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
          borderRadius: radius,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(icon, size: 28, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? colors.primary : colors.outline,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
