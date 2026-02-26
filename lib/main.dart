import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'screens/driver_screen.dart';
import 'screens/force_update_screen.dart';
import 'screens/maintenance_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/fake_gps_overlay_service.dart';
import 'services/route_notification_service.dart';
import 'screens/penumpang_screen.dart';
import 'screens/reverify_face_screen.dart';
import 'screens/splash_screen.dart';
import 'services/verification_service.dart';
import 'services/app_update_service.dart';
import 'services/device_service.dart';
import 'services/maintenance_service.dart';
import 'services/fcm_service.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'services/permission_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_update_wrapper.dart';
import 'widgets/fake_gps_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    debugPrint('Firebase init error: $e');
    debugPrint('$st');
    runApp(_ErrorApp(message: 'Gagal memuat Firebase: $e'));
    return;
  }

  // Firestore cache: 100 MB untuk hemat memori di HP rendah (default Firestore)
  final firestore = FirebaseFirestore.instance;
  firestore.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024, // 100 MB
  );

  await ThemeService.init();

  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const TrakaApp());

  // Init Crashlytics di background
  FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

  // Init di background (tidak blok tampilan)
  _initInBackground();
}

/// Minta izin notifikasi di background (tidak blok UI).
void _requestNotificationInBackground() {
  Future(() async {
    final status = await ph.Permission.notification.status;
    if (!status.isGranted) {
      await ph.Permission.notification.request();
    }
  });
}

/// Inisialisasi non-kritis di background setelah UI tampil.
void _initInBackground() {
  Future(() async {
    try {
      await FcmService.init();
    } catch (_) {}
    try {
      await RouteNotificationService.init();
    } catch (_) {}
  });
}

/// Tampilan error jika Firebase/init gagal (hindari layar hitam).
class _ErrorApp extends StatelessWidget {
  final String message;

  const _ErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Terjadi kesalahan',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  'Pastikan google-services.json dan firebase_options.dart sesuai dengan app id.traka.app.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TrakaApp extends StatelessWidget {
  const TrakaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeModeNotifier,
      builder: (_, themeMode, __) {
        return MaterialApp(
          title: 'Traka Travel Kalimantan',
          debugShowCheckedModeBanner: false,
          supportedLocales: const [Locale('id', 'ID'), Locale('en')],
          locale: const Locale('id', 'ID'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (locale, supported) {
            if (locale != null && locale.languageCode == 'id') {
              return const Locale('id', 'ID');
            }
            return const Locale('id', 'ID');
          },
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          builder: (context, child) {
        final media = MediaQuery.of(context);
        final shortestSide = media.size.shortestSide;
        // Ukuran font tidak mengikuti pengaturan HP pengguna; hanya sesuaikan layar kecil.
        final scale = shortestSide < 340
            ? 0.88
            : shortestSide < 380
                ? 0.92
                : shortestSide < 420
                    ? 0.96
                    : 1.0;
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: FakeGpsOverlayService.fakeGpsDetected,
            builder: (context, showFakeGpsOverlay, _) {
              return Stack(
                children: [
                  child!,
                  if (showFakeGpsOverlay)
                    const Positioned.fill(
                      child: FakeGpsOverlay(),
                    ),
                ],
              );
            },
          ),
        );
      },
          home: const SplashScreenWrapper(),
          routes: {'/login': (context) => const LoginScreen()},
        );
      },
    );
  }
}

/// Wrapper untuk splash screen + cek auth status
class SplashScreenWrapper extends StatefulWidget {
  const SplashScreenWrapper({super.key});

  @override
  State<SplashScreenWrapper> createState() => _SplashScreenWrapperState();
}

class _SplashScreenWrapperState extends State<SplashScreenWrapper> {
  @override
  void initState() {
    super.initState();
    // Splash 600ms, lalu cek auth lalu izin minimal (jika sudah login)
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) _checkAuthAndRequestPermissions();
    });
  }

  /// Cek auth dulu. Jika belum login: langsung ke login (tanpa minta izin).
  /// Jika sudah login: minta izin minimal (lokasi + device ID) lalu lanjut.
  Future<void> _checkAuthAndRequestPermissions() async {
    if (!mounted) return;
    final updateRequired = await AppUpdateService.isUpdateRequired();
    if (updateRequired && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ForceUpdateScreen()),
      );
      return;
    }
    if (!mounted) return;
    final (maintenanceEnabled, maintenanceMessage) = await MaintenanceService.check();
    if (maintenanceEnabled && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MaintenanceScreen(message: maintenanceMessage),
        ),
      );
      return;
    }
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
        ),
      );
      return;
    }
    // User sudah login: butuh lokasi + device ID untuk home
    final granted = await PermissionService.requestEssentialForHome(context);
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Izin lokasi dan device ID diperlukan. Buka aplikasi lagi dan berikan izin.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    if (mounted) _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
        ),
      );
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;
      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
          ),
        );
        return;
      }

      final data = userDoc.data();
      final role = data?['role'] as String?;
      final suspendedAt = data?['suspendedAt'];
      if (suspendedAt != null) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block, size: 64, color: Colors.red.shade700),
                      const SizedBox(height: 16),
                      const Text(
                        'Akun Diblokir',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        (data?['suspendedReason'] as String?) ?? 'Akun Anda telah dibekukan. Hubungi admin untuk informasi lebih lanjut.',
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
                          ),
                        ),
                        child: const Text('Kembali ke Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        return;
      }
      final storedDeviceId = data?['deviceId'] as String?;
      final currentDeviceId = await DeviceService.getDeviceId();

      // Cek apakah device ID saat ini sudah digunakan oleh akun lain dengan role yang SAMA
      // (1 akun hanya boleh login di 1 device, tapi 1 device boleh punya 1 driver + 1 penumpang)
      if (currentDeviceId != null &&
          currentDeviceId.isNotEmpty &&
          role != null) {
        final usersWithSameDeviceAndRole = await FirebaseFirestore.instance
            .collection('users')
            .where('deviceId', isEqualTo: currentDeviceId)
            .where('role', isEqualTo: role)
            .limit(1)
            .get();

        // Jika ada user lain dengan role yang sama yang menggunakan device ID yang sama, logout dan arahkan ke login
        if (usersWithSameDeviceAndRole.docs.isNotEmpty) {
          final otherUserDoc = usersWithSameDeviceAndRole.docs.first;
          final otherUserId = otherUserDoc.id;

          // Jika bukan akun yang sedang login, berarti device sudah dipakai akun lain dengan role yang sama
          if (otherUserId != user.uid) {
            await FirebaseAuth.instance.signOut();
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
              ),
            );
            return;
          }
        }
      }

      // Re-login wajib jika device ID berbeda (user harus verifikasi wajah di login screen)
      final deviceChanged =
          currentDeviceId != null &&
          currentDeviceId.isNotEmpty &&
          storedDeviceId != null &&
          storedDeviceId.isNotEmpty &&
          currentDeviceId != storedDeviceId;

      if (deviceChanged) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
          ),
        );
        return;
      }

      if (role == 'penumpang' || role == 'driver') {
        FcmService.saveTokenForUser(user.uid);
        final faceUrl = (data?['faceVerificationUrl'] as String?)?.trim();
        final hasFacePhoto = faceUrl != null && faceUrl.isNotEmpty;
        final seenOnboarding = await OnboardingScreen.hasSeenOnboarding();
        final needsReverify = VerificationService.needsFaceReverify(data ?? {});

        if (!hasFacePhoto && !seenOnboarding) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => AppUpdateWrapper(
                child: OnboardingScreen(role: role ?? 'penumpang'),
              ),
            ),
          );
        } else if (hasFacePhoto && needsReverify) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => AppUpdateWrapper(
                child: ReverifyFaceScreen(
                  role: role ?? 'penumpang',
                  onSuccess: () {
                    if (!context.mounted) return;
                    if (role == 'penumpang') {
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
                  },
                ),
              ),
            ),
          );
        } else if (role == 'penumpang') {
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
        _requestNotificationInBackground();
      } else {
        await FirebaseAuth.instance.signOut();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const AppUpdateWrapper(child: LoginScreen()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
