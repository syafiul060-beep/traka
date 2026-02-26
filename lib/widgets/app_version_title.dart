import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Widget untuk menampilkan versi aplikasi di AppBar (mengikuti pubspec.yaml).
class AppVersionTitle extends StatelessWidget {
  const AppVersionTitle({
    super.key,
    this.style,
  });

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '1.0.0';
        return Text(
          'Versi $version',
          style: style ??
              TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
        );
      },
    );
  }
}
