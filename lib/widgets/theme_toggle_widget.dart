import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/theme_service.dart';

/// Widget toggle tema (terang/gelap) dengan switch dan info.
/// Posisi: di halaman Saya, sebelah kiri gambar admin.
/// Geser kanan = gelap, geser kiri = terang. Default: terang.
class ThemeToggleWidget extends StatelessWidget {
  const ThemeToggleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeModeNotifier,
      builder: (_, themeMode, __) {
        final isDark = themeMode == ThemeMode.dark;
        return Tooltip(
          message: isDark
              ? 'Geser ke kiri untuk tema terang'
              : 'Geser ke kanan untuk tema gelap',
          child: InkWell(
            onTap: () => _showInfo(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDark ? Icons.dark_mode : Icons.light_mode,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tema Gelap',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        isDark ? 'Aktif' : 'Nonaktif',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: isDark,
                    onChanged: (v) {
                      HapticFeedback.lightImpact();
                      ThemeService.setThemeMode(
                        v ? ThemeMode.dark : ThemeMode.light,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInfo(BuildContext context) {
    final isDark = ThemeService.current == ThemeMode.dark;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pengaturan Tema'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Geser switch ke kanan untuk mengaktifkan tema gelap. '
              'Geser ke kiri untuk kembali ke tema terang.',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tema saat ini: ${isDark ? "Gelap" : "Terang"}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(ctx).colorScheme.primary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }
}
