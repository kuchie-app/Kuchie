import 'package:material_ui/material_ui.dart';

import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../domain/diagram/sync_methods.dart';
import 'sync_hero_card.dart';

/// The seven common questions from design 3.2.
const syncFaq = <(SyncCopy, SyncCopy)>[
  (
    (en: 'What is Sync?', id: 'Apa itu Sinkronisasi?'),
    (
      en: 'Sync keeps your library, reading progress and bookmarks the same on this iPhone and your own Suwayomi server. The library stays on your iPhone, so Kuchie works even when the server is down.',
      id: 'Sinkronisasi menyamakan library, progres baca, dan bookmark antara iPhone dan server Suwayomi milikmu. Library tetap tersimpan di iPhone, jadi Kuchie bisa dipakai walau server mati.',
    ),
  ),
  (
    (en: 'What syncs?', id: 'Apa saja yang disinkronkan?'),
    (
      en: 'Library and categories, reading progress and history, chapter bookmarks, and reader settings per series. Ratings, tags and notes can be turned on under Advanced.',
      id: 'Library dan kategori, progres baca dan riwayat, bookmark chapter, dan setelan reader per series. Rating, tag, dan catatan bisa dinyalakan di Lanjutan.',
    ),
  ),
  (
    (en: "What doesn't sync?", id: 'Apa yang tidak disinkronkan?'),
    (
      en: "Downloaded files aren't copied automatically. Series from imported files and from the Kuchie repo stay on this iPhone, because the server doesn't have their source.",
      id: 'File unduhan tidak disalin otomatis. Series dari file import dan repo Kuchie tetap hanya di iPhone, karena server tidak punya source-nya.',
    ),
  ),
  (
    (
      en: "What if the server is down or I'm away from home?",
      id: 'Bagaimana kalau server mati atau aku di luar rumah?',
    ),
    (
      en: 'Kuchie keeps working from the data on your iPhone. Chapters are read straight from the source through the extensions on your iPhone, and changes go out once the server can be reached again.',
      id: 'Kuchie tetap jalan dari data di iPhone. Chapter dibaca langsung dari source lewat extension di iPhone, dan perubahan dikirim saat server terjangkau lagi.',
    ),
  ),
  (
    (en: 'Where are downloads kept?', id: 'Unduhan disimpan di mana?'),
    (
      en: "While connected, downloads go to the server so your iPhone doesn't fill up. Use Save for offline to read without internet. Older downloads on your iPhone can move to the server from Storage.",
      id: 'Saat terhubung ke server, unduhan disimpan di server supaya iPhone tidak penuh. Pakai Simpan untuk offline kalau ingin membaca tanpa internet. Unduhan lama di iPhone bisa dipindahkan ke server lewat Penyimpanan.',
    ),
  ),
  (
    (
      en: 'Do extensions need installing twice?',
      id: 'Apakah extension perlu dipasang dua kali?',
    ),
    (
      en: 'No. Install puts the extension on your iPhone and on the server at once.',
      id: 'Tidak. Tombol Pasang memasang extension di iPhone dan di server sekaligus.',
    ),
  ),
  (
    (
      en: 'How do I stop using the server?',
      id: 'Bagaimana cara berhenti memakai server?',
    ),
    (
      en: "Open Suwayomi server, then Disconnect. Your library and progress stay on your iPhone, and chapters on the server aren't deleted.",
      id: 'Buka Server Suwayomi, lalu Putuskan koneksi. Library dan progres tetap di iPhone, dan chapter di server tidak dihapus.',
    ),
  ),
];

class SyncFaq extends StatelessWidget {
  const SyncFaq({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsGroupCard(
      children: [
        for (final (question, answer) in syncFaq)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(syncCopy(context, question)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              expandedAlignment: Alignment.centerLeft,
              children: [
                Text(
                  syncCopy(context, answer),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
