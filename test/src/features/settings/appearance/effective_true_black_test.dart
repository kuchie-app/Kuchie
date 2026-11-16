import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/constants/app_theme.dart';
import 'package:kuchie/src/features/settings/presentation/appearance/widgets/is_true_black/is_true_black_tile.dart';

void main() {
  test('pure black defaults on only for Indigo Night with Liquid Glass', () {
    bool resolve(bool? saved, AppTheme theme, bool glass) =>
        effectiveTrueBlack(saved: saved, theme: theme, appleGlass: glass);

    expect(resolve(null, AppTheme.indigoNight, true), isTrue);
    expect(resolve(null, AppTheme.indigoNight, false), isFalse);
    expect(resolve(null, AppTheme.values.last, true), isFalse);
    // A saved choice always wins.
    expect(resolve(false, AppTheme.indigoNight, true), isFalse);
    expect(resolve(true, AppTheme.values.last, false), isTrue);
  });
}
