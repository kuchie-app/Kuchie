import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/backup/backup_settings_repository.dart';
import '../../../domain/settings/settings.dart';

part 'backup_controller.g.dart';

@riverpod
Future<RestoreStatusDto?> restoreStatus(Ref ref, String restoreId) =>
    ref.watch(backupSettingsRepositoryProvider).getRestoreStatus(restoreId);
