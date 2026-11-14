import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/settings/presentation/backup/widgets/backup_and_restore/backup_and_restore_section.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/utils/misc/toast/toast.dart';
import 'package:material_ui/material_ui.dart';

class _BackupFilePicker extends FilePickerPlatform {
  _BackupFilePicker({this.error});

  final PlatformException? error;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    if (error case final error?) throw error;
    return null;
  }
}

void main() {
  Future<void> openRestorePicker(
    WidgetTester tester,
    FilePickerPlatform picker,
  ) async {
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ProviderScope(
              overrides: [toastProvider.overrideWithValue(Toast(context))],
              child: const BackupAndRestoreSection(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();
  }

  testWidgets('closing the restore picker leaves backup settings quietly', (
    tester,
  ) async {
    await openRestorePicker(tester, _BackupFilePicker());

    try {
      expect(find.text('Restore backup'), findsOneWidget);
      expect(find.byType(ToastWidget), findsNothing);
    } finally {
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('restore still reports a failure from the file picker', (
    tester,
  ) async {
    await openRestorePicker(
      tester,
      _BackupFilePicker(error: PlatformException(code: 'picker_unavailable')),
    );

    final toast = tester.widget<ToastWidget>(find.byType(ToastWidget));
    expect(toast.isError, isTrue);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
