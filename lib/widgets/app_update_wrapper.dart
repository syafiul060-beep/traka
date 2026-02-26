import 'package:flutter/material.dart';

import '../screens/force_update_screen.dart';
import '../services/app_update_service.dart';

/// Wrapper yang cek minVersion dan tampilkan In-App Update (flexible) jika tersedia.
/// Gunakan untuk membungkus screen tujuan setelah login/splash.
class AppUpdateWrapper extends StatefulWidget {
  const AppUpdateWrapper({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AppUpdateWrapper> createState() => _AppUpdateWrapperState();
}

class _AppUpdateWrapperState extends State<AppUpdateWrapper> {
  bool? _updateRequired;

  @override
  void initState() {
    super.initState();
    _checkMinVersion();
  }

  Future<void> _checkMinVersion() async {
    final required = await AppUpdateService.isUpdateRequired();
    if (!mounted) return;
    setState(() => _updateRequired = required);
    if (!required) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppUpdateService.checkAndPromptFlexibleUpdate();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_updateRequired == true) {
      return const ForceUpdateScreen();
    }
    if (_updateRequired == false) {
      return widget.child;
    }
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
