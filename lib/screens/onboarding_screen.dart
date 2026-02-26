import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_update_wrapper.dart';
import 'driver_screen.dart';
import 'penumpang_screen.dart';

const _prefOnboardingSeen = 'traka_onboarding_seen';

/// Intro screens untuk pengguna baru (faceVerificationUrl kosong).
/// Ditampilkan sekali setelah login pertama.
class OnboardingScreen extends StatefulWidget {
  final String role;

  const OnboardingScreen({super.key, required this.role});

  static Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefOnboardingSeen) ?? false;
  }

  static Future<void> markOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefOnboardingSeen, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    (
      title: 'Selamat datang di Traka',
      body: 'Aplikasi travel dan pengiriman barang terpercaya di Kalimantan. Pesan tiket travel atau kirim barang dengan mudah.',
      icon: Icons.directions_bus,
    ),
    (
      title: 'Verifikasi untuk keamanan',
      body: 'Lengkapi verifikasi data (foto wajah, KTP/SIM) dan nomor telepon di profil untuk menggunakan semua fitur.',
      icon: Icons.verified_user,
    ),
    (
      title: 'Siap memulai',
      body: 'Jelajahi rute travel, pesan tiket, atau kirim barang. Semua dalam satu aplikasi.',
      icon: Icons.rocket_launch,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onDone() async {
    await OnboardingScreen.markOnboardingSeen();
    if (!mounted) return;
    if (widget.role == 'penumpang') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: PenumpangScreen()),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: DriverScreen()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          p.icon,
                          size: 80,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          p.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      _pages.length,
                      (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _currentPage
                              ? colorScheme.primary
                              : colorScheme.outline.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _onDone,
                    child: Text(
                      _currentPage < _pages.length - 1 ? 'Lanjut' : 'Mulai',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
