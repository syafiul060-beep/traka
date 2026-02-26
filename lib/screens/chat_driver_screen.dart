import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';

import '../models/chat_message_model.dart';
import '../models/order_model.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../services/audio_recorder_service.dart';
import '../services/chat_service.dart';
import '../services/driver_contribution_service.dart';
import '../services/order_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'contribution_driver_screen.dart';
import 'scan_barcode_driver_screen.dart';
import 'voice_call_screen.dart';

/// Halaman chat driver dengan penumpang.
/// Dipakai dari: tab Chat di driver_screen, atau saat driver buka pesanan.
/// [orderId]: opsional; bila null, di-load pesanan aktif pertama untuk driver ini.
class ChatDriverScreen extends StatefulWidget {
  const ChatDriverScreen({super.key, this.orderId});

  final String? orderId;

  @override
  State<ChatDriverScreen> createState() => _ChatDriverScreenState();
}

class _ChatDriverScreenState extends State<ChatDriverScreen> {
  OrderModel? _order;
  bool _loading = true;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Audio recording state
  bool _isRecording = false;
  bool _isRecordingLocked = false; // Untuk locked recording (geser ke atas)
  bool _isButtonPressed = false; // Untuk animasi tombol membesar
  double _buttonDragOffset = 0.0; // Offset Y untuk animasi tombol naik
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  Offset? _panStartPosition; // Untuk tracking posisi awal saat pan

  // Audio player untuk playback
  final Map<String, AudioPlayer> _audioPlayers = {};
  final Map<String, bool> _audioPlaying = {};
  // Kontribusi driver: wajib bayar → disable kirim & Kesepakatan
  StreamSubscription<DriverContributionStatus>? _contributionSub;
  bool _mustPayContribution = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _incomingCallSub;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _loadOrder();
    _contributionSub = DriverContributionService.streamContributionStatus()
        .listen((s) {
          if (mounted)
            setState(() => _mustPayContribution = s.mustPayContribution);
        });
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _contributionSub?.cancel();
    _incomingCallSub?.cancel();
    // Dispose semua audio player
    for (final player in _audioPlayers.values) {
      player.dispose();
    }
    _audioPlayers.clear();
    super.dispose();
  }

  Future<void> _markReceivedMessagesAsDeliveredAndRead() async {
    if (_order == null) return;
    await ChatService.markAsDelivered(_order!.id);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await ChatService.markAsRead(_order!.id);
    // Update driverLastReadAt di order document untuk menghilangkan badge unread
    await OrderService.setDriverLastReadAt(_order!.id);
  }

  Future<void> _loadOrder() async {
    final orderId = widget.orderId;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      if (orderId != null) {
        final order = await OrderService.getOrderById(
          orderId,
        ).timeout(const Duration(seconds: 10), onTimeout: () => null);
        if (mounted) {
          setState(() {
            _order = order;
            _loading = false;
          });
          if (order != null) {
            _markReceivedMessagesAsDeliveredAndRead();
            _listenIncomingCall();
          }
        }
        return;
      }

      final order = await OrderService.getFirstActiveOrderForDriver(
        user.uid,
      ).timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (mounted) {
        setState(() {
          _order = order;
          _loading = false;
        });
        if (order != null) {
          _markReceivedMessagesAsDeliveredAndRead();
          _listenIncomingCall();
        }
      }
    } catch (e) {
      // Jika ada error, tetap set loading ke false agar tidak stuck
      if (mounted) {
        setState(() {
          _order = null;
          _loading = false;
        });
        // Tampilkan error jika perlu (opsional)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat pesanan: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _listenIncomingCall() {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final orderId = _order?.id;
    if (myUid == null || orderId == null) return;
    _incomingCallSub?.cancel();
    _incomingCallSub = FirebaseFirestore.instance
        .collection('voice_calls')
        .doc(orderId)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final d = snap.data()!;
      if ((d['calleeUid'] as String?) != myUid) return;
      if ((d['status'] as String?) != 'ringing') return;
      _incomingCallSub?.cancel();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VoiceCallScreen(
            orderId: orderId,
            remoteUid: _order!.passengerUid,
            remoteName: (d['callerName'] as String?) ?? _order!.passengerName,
            remotePhotoUrl: _order!.passengerPhotoUrl,
            isCaller: false,
          ),
        ),
      );
    });
  }

  Future<void> _sendMessage() async {
    if (_order == null) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    final ok = await ChatService.sendMessage(_order!.id, text);
    if (!mounted) return;
    if (!ok) {
      _textController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatService.lastBlockedReason ??
                'Gagal mengirim pesan. Periksa koneksi dan coba lagi.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    // Scroll ke bawah (pesan terbaru) setelah kirim
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController
              .position
              .maxScrollExtent, // Scroll ke bawah (pesan terbaru)
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Format alamat: hanya kecamatan dan kabupaten, tanpa provinsi.
  String _formatAlamatKecamatanKabupaten(String alamat) {
    if (alamat.isEmpty) return alamat;

    // Split berdasarkan koma
    final parts = alamat
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return alamat;

    // Cari bagian yang mengandung "Kecamatan" atau "Kec."
    String? kecamatan;
    String? kabupaten;

    for (final part in parts) {
      final lower = part.toLowerCase();
      if (lower.contains('kecamatan') || lower.contains('kec.')) {
        kecamatan = part;
      } else if (lower.contains('kabupaten') ||
          lower.contains('kab.') ||
          lower.contains('kota ') ||
          (lower.contains('kota') && !lower.contains('kabupaten'))) {
        kabupaten = part;
      }
    }

    // Jika tidak ditemukan pattern, ambil 2 bagian pertama (biasanya kecamatan, kabupaten)
    if (kecamatan == null && kabupaten == null && parts.length >= 2) {
      kecamatan = parts[0];
      kabupaten = parts[1];
    } else if (kecamatan == null && parts.isNotEmpty) {
      kecamatan = parts[0];
    }

    // Gabungkan kecamatan dan kabupaten, hilangkan provinsi
    final result = <String>[];
    if (kecamatan != null) result.add(kecamatan);
    if (kabupaten != null && kabupaten != kecamatan) result.add(kabupaten);

    return result.isEmpty ? alamat : result.join(', ');
  }

  /// Format angka Rupiah dengan titik pemisah ribuan (1.000.000, 250.000).
  static String _formatRupiahThousands(String digitsOnly) {
    if (digitsOnly.isEmpty) return '';
    final digits = digitsOnly.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return '';
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Dialog kesepakatan harga: input harga + checkbox konfirmasi.
  /// Menampilkan nama penumpang, tujuan awal & akhir, dan kirim pesan otomatis ke chat.
  Future<void> _showDialogKesepakatanHarga() async {
    if (_order == null) return;
    final priceController = TextEditingController();
    priceController.addListener(() {
      final digits = priceController.text.replaceAll(RegExp(r'[^\d]'), '');
      final formatted = _formatRupiahThousands(digits);
      if (priceController.text != formatted) {
        priceController.value = priceController.value.copyWith(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    });
    final formKey = GlobalKey<FormState>();
    bool hargaDisepakati = false;
    final order = _order!;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          title: SizedBox(
            width: double.maxFinite,
            child: Text(
              'Kesepakatan dan Harga Travel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nama penumpang
                  SizedBox(
                    width: double.maxFinite,
                    child: Text(
                      order.passengerName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Tujuan awal (hanya kecamatan & kabupaten)
                  if (order.originText.isNotEmpty) ...[
                    SizedBox(
                      width: double.maxFinite,
                      child: Text(
                        'Dari: ${_formatAlamatKecamatanKabupaten(order.originText)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  // Tujuan akhir (hanya kecamatan & kabupaten)
                  if (order.destText.isNotEmpty) ...[
                    SizedBox(
                      width: double.maxFinite,
                      child: Text(
                        'Tujuan: ${_formatAlamatKecamatanKabupaten(order.destText)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Label input harga (abu-abu, 1 baris)
                  SizedBox(
                    width: double.maxFinite,
                    child: Text(
                      'Masukkan harga yang disepakati (Rp):',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      hintText: 'Contoh: 1.500.000',
                      border: OutlineInputBorder(),
                      prefixText: 'Rp ',
                    ),
                    validator: (v) {
                      final n = int.tryParse(
                        v?.replaceAll(RegExp(r'[^\d]'), '') ?? '',
                      );
                      if (n == null || n < 0)
                        return 'Masukkan harga yang valid';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Harga akan tercatat. Penumpang bayar langsung saat bertemu. Jangan minta harga berbeda.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Checkbox (1 baris)
                  CheckboxListTile(
                    value: hargaDisepakati,
                    onChanged: (value) {
                      setDialogState(() {
                        hargaDisepakati = value ?? false;
                      });
                    },
                    title: const Text('Harga sudah disepakati bersama'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: hargaDisepakati
                  ? () async {
                      if (!formKey.currentState!.validate()) return;
                      final priceText = priceController.text.replaceAll(
                        RegExp(r'[^\d]'),
                        '',
                      );
                      final price = double.tryParse(priceText);
                      if (price == null || price < 0) return;
                      Navigator.pop(dialogContext);

                      // Kirim harga ke order
                      final ok = await OrderService.setDriverAgreedPrice(
                        order.id,
                        price,
                      );
                      if (!mounted) return;

                      if (ok) {
                        // Format harga untuk pesan (titik pemisah ribuan)
                        final hargaFormatted = price
                            .toStringAsFixed(0)
                            .replaceAllMapped(
                              RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                              (Match m) => '${m[1]}.',
                            );
                        // Kategori: Travel (1 orang) / Travel (X orang - dengan kerabat) / Kirim Barang
                        final String kategoriPesan = order.isKirimBarang
                            ? 'Kirim Barang'
                            : order.isTravelKerabat
                            ? 'Travel (${1 + (order.jumlahKerabat ?? 1)} orang - dengan kerabat)'
                            : 'Travel (1 orang)';
                        // Pesan otomatis 5 baris; baris kelima "Ongkosnya Rp ..." ditampilkan hijau tebal di chat
                        final messageText =
                            '${order.passengerName}\n'
                            'Untuk pesan $kategoriPesan\n'
                            'Dari ${order.originText}\n'
                            'Tujuan ${order.destText}\n'
                            'Ongkosnya Rp $hargaFormatted';
                        await ChatService.sendMessage(order.id, messageText);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Harga kesepakatan telah dikirim. Menunggu penumpang setuju.',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        _loadOrder();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Gagal mengirim harga. Coba lagi.'),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  : null,
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );
  }

  /// Mulai rekam audio (hold to record)
  Future<void> _startRecording({bool isLocked = false}) async {
    if (_isRecording) return;

    // Getaran saat pertama kali mulai rekam
    HapticFeedback.mediumImpact();

    final path = await AudioRecorderService.startRecording();
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tidak dapat mengakses mikrofon. Periksa izin aplikasi.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isRecording = true;
      _isRecordingLocked = isLocked;
      _recordingDuration = 0;
    });

    // Timer untuk update durasi rekaman
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordingDuration = AudioRecorderService.currentDuration;
        });
      }
    });
  }

  /// Stop rekam audio dan kirim
  Future<void> _stopRecording({bool send = true}) async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    final result = await AudioRecorderService.stopRecording();
    setState(() {
      _isRecording = false;
      _isRecordingLocked = false;
      _isButtonPressed = false;
      _buttonDragOffset = 0.0;
      _recordingDuration = 0;
    });

    if (!send || result == null) {
      // Jika tidak dikirim, hapus file rekaman
      if (result != null) {
        try {
          await result.file.delete();
        } catch (e) {
          // Ignore error saat hapus file
        }
      }
      return;
    }

    if (_order == null) return;

    // Validasi file sebelum kirim
    if (!await result.file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File audio tidak ditemukan. Coba rekam lagi.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Validasi durasi minimal 1 detik
    if (result.duration < 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Durasi rekaman terlalu pendek. Minimal 1 detik.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      // Hapus file yang terlalu pendek
      try {
        await result.file.delete();
      } catch (e) {
        // Ignore
      }
      return;
    }

    // Kirim audio dengan loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Mengirim pesan suara...'),
            ],
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    final ok = await ChatService.sendAudioMessage(
      _order!.id,
      result.file,
      result.duration,
    );

    if (!mounted) return;

    // Tutup loading indicator
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatService.lastBlockedReason ??
                'Gagal mengirim pesan suara. Periksa koneksi dan coba lagi.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// Cancel rekaman (hapus tanpa kirim)
  Future<void> _cancelRecording() async {
    await _stopRecording(send: false);
  }

  /// Build tombol voice dengan gesture seperti WhatsApp
  Widget _buildVoiceButton() {
    return GestureDetector(
      onPanStart: (details) {
        _panStartPosition = details.globalPosition;
        setState(() {
          _isButtonPressed = true;
          _buttonDragOffset = 0.0;
        });
        _startRecording();
      },
      onPanUpdate: (details) {
        if (!_isRecording || _panStartPosition == null) return;

        // Hitung offset Y (negatif = naik ke atas)
        final dy = _panStartPosition!.dy - details.globalPosition.dy;

        // Update posisi tombol (maksimal naik 200px)
        setState(() {
          _buttonDragOffset = dy.clamp(0.0, 200.0);
        });

        // Jika digeser ke atas lebih dari 50px, lock recording
        if (dy > 50 && !_isRecordingLocked) {
          // Lock recording
          HapticFeedback.mediumImpact();
          setState(() {
            _isRecordingLocked = true;
          });
        } else if (dy <= 50 && _isRecordingLocked) {
          // Unlock recording
          setState(() {
            _isRecordingLocked = false;
          });
        }
      },
      onPanEnd: (details) {
        setState(() {
          _isButtonPressed = false;
          _buttonDragOffset = 0.0;
        });
        _panStartPosition = null;

        // Jika tidak locked, kirim langsung saat dilepas
        if (_isRecording && !_isRecordingLocked) {
          _stopRecording(send: true);
        }
        // Jika locked, tetap rekam (user harus klik tombol kirim)
      },
      onPanCancel: () {
        setState(() {
          _isButtonPressed = false;
          _buttonDragOffset = 0.0;
        });
        _panStartPosition = null;
        // Jika tidak locked, kirim langsung saat cancel
        if (_isRecording && !_isRecordingLocked) {
          _stopRecording(send: true);
        }
      },
      child: Transform.translate(
        offset: Offset(0, -_buttonDragOffset),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          width: _isButtonPressed ? 56 : 48,
          height: _isButtonPressed ? 56 : 48,
          decoration: BoxDecoration(
            color: _isRecordingLocked
                ? Colors.green
                : Theme.of(context).colorScheme.primary, // Biru, hijau jika locked
            shape: BoxShape.circle,
            boxShadow: _isButtonPressed
                ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: IconButton(
            icon: Icon(
              _isRecordingLocked ? Icons.lock : Icons.mic,
              color: Colors.white,
            ),
            onPressed: null, // Disabled, hanya gesture yang bekerja
          ),
        ),
      ),
    );
  }

  /// Pick gambar dari gallery
  Future<void> _pickImage() async {
    if (_order == null) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Memeriksa gambar...'),
          duration: Duration(seconds: 3),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    final ok = await ChatService.sendImageMessage(_order!.id, File(image.path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatService.lastBlockedReason ??
                'Gagal mengirim gambar. Periksa koneksi dan coba lagi.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// Pick video dari gallery
  Future<void> _pickVideo() async {
    if (_order == null) return;

    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    final ok = await ChatService.sendVideoMessage(_order!.id, File(video.path));
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal mengirim video. Periksa koneksi dan coba lagi.'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// Tampilkan dialog pilih gambar atau video
  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih Gambar'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Pilih Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarcodeMessage(ChatMessageModel msg, {required bool isMe}) {
    final title = msg.isBarcodePassenger
        ? 'Barcode penumpang (scan di lokasi jemput)'
        : 'Barcode driver';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: isMe ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showBarcodeFullScreen(msg.text, title),
          child: QrImageView(
            data: msg.text,
            version: QrVersions.auto,
            size: 120,
            backgroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  void _showBarcodeFullScreen(String payload, String title) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 280,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Teks pesan: "Tujuan" / "Tujuan: " biru tebal; baris tarif/biaya & "Ongkosnya Rp ..." hijau tebal.
  Widget _buildTextContent(String text, bool isMe) {
    final baseColor = isMe ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final blueBold = TextStyle(
      fontSize: 15,
      color: isMe ? const Color(0xFFBBDEFB) : Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.bold,
    );
    final greenBold = TextStyle(
      fontSize: 15,
      color: isMe
          ? const Color(0xFFA5D6A7)
          : (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFA5D6A7)
              : const Color(0xFF2E7D32)),
      fontWeight: FontWeight.bold,
    );
    final baseStyle = TextStyle(fontSize: 15, color: baseColor);
    final lines = text.split('\n');
    final widgets = <Widget>[];
    final isTarifLine = (String t) =>
        t == 'Mohon informasi tarif untuk rute ini.' ||
        t == 'Mohon informasi biaya pengiriman untuk rute ini.';
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (line.isNotEmpty) widgets.add(Text(line, style: baseStyle));
        continue;
      }
      // Baris tarif/biaya/ongkos: hijau tebal
      if (isTarifLine(trimmed) || trimmed.startsWith('Ongkosnya Rp ')) {
        widgets.add(Text(trimmed, style: greenBold));
        continue;
      }
      // Baris "Tujuan: ..." atau "Tujuan ...": kata "Tujuan" biru tebal, sisanya normal
      if (trimmed.startsWith('Tujuan: ') || trimmed.startsWith('Tujuan ')) {
        final prefix = trimmed.startsWith('Tujuan: ') ? 'Tujuan: ' : 'Tujuan ';
        final rest = trimmed.substring(prefix.length);
        widgets.add(
          RichText(
            text: TextSpan(
              style: baseStyle,
              children: [
                TextSpan(text: prefix, style: blueBold),
                if (rest.isNotEmpty) TextSpan(text: rest, style: baseStyle),
              ],
            ),
          ),
        );
        continue;
      }
      widgets.add(Text(line, style: baseStyle));
    }
    if (widgets.length == 1) return widgets.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _buildStatusIcon(String status) {
    final isRead = status == ChatService.statusRead;
    final isDelivered = status == ChatService.statusDelivered;
    final color = isRead ? const Color(0xFFBBDEFB) : Theme.of(context).colorScheme.surface;
    final icon = (isDelivered || isRead) ? Icons.done_all : Icons.done;
    return Icon(icon, size: 16, color: color);
  }

  /// Widget untuk pesan audio
  Widget _buildAudioMessage(ChatMessageModel msg, {required bool isMe}) {
    final isPlaying = _audioPlaying[msg.id] ?? false;
    final duration = msg.audioDuration ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => _toggleAudioPlayback(msg),
        ),
        const SizedBox(width: 4),
        Text(
          _formatDuration(duration),
          style: TextStyle(
            fontSize: 13,
            color: isMe ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (isMe) ...[const SizedBox(width: 6), _buildStatusIcon(msg.status)],
      ],
    );
  }

  /// Widget untuk pesan gambar
  void _openFullScreenImage(String? url) {
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => FullScreenImageViewer(imageUrl: url),
      ),
    );
  }

  Widget _buildImageMessage(ChatMessageModel msg, {required bool isMe}) {
    final imageUrl = msg.mediaUrl ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _openFullScreenImage(imageUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 200,
                height: 200,
                color: Theme.of(context).colorScheme.outline,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                width: 200,
                height: 200,
                color: Theme.of(context).colorScheme.outline,
                child: const Icon(Icons.error),
              ),
            ),
          ),
        ),
        if (isMe) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [_buildStatusIcon(msg.status)],
          ),
        ],
      ],
    );
  }

  /// Widget untuk pesan video
  Widget _buildVideoMessage(ChatMessageModel msg, {required bool isMe}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Container(
                width: 200,
                height: 200,
                color: Theme.of(context).colorScheme.onSurface,
                child: msg.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: msg.thumbnailUrl!,
                        fit: BoxFit.cover,
                      )
                    : const Center(
                        child: Icon(
                          Icons.videocam,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
              ),
              const Center(
                child: Icon(
                  Icons.play_circle_filled,
                  color: Colors.white70,
                  size: 48,
                ),
              ),
            ],
          ),
        ),
        if (isMe) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [_buildStatusIcon(msg.status)],
          ),
        ],
      ],
    );
  }

  /// Toggle audio playback
  Future<void> _toggleAudioPlayback(ChatMessageModel msg) async {
    if (msg.audioUrl == null) return;

    final messageId = msg.id;
    final isPlaying = _audioPlaying[messageId] ?? false;

    if (isPlaying) {
      // Stop playback
      final player = _audioPlayers[messageId];
      await player?.stop();
      setState(() {
        _audioPlaying[messageId] = false;
      });
    } else {
      // Start playback
      AudioPlayer player;
      if (_audioPlayers.containsKey(messageId)) {
        player = _audioPlayers[messageId]!;
      } else {
        player = AudioPlayer();
        _audioPlayers[messageId] = player;
        await player.setUrl(msg.audioUrl!);
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            if (mounted) {
              setState(() {
                _audioPlaying[messageId] = false;
              });
            }
          }
        });
      }

      await player.play();
      if (mounted) {
        setState(() {
          _audioPlaying[messageId] = true;
        });
      }
    }
  }

  /// Format durasi audio (detik) menjadi string MM:SS
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final passengerName = _order?.passengerName ?? 'Penumpang';
    final passengerPhotoUrl = _order?.passengerPhotoUrl;
    final passengerUid = _order?.passengerUid;

    return Scaffold(
      appBar: AppBar(
        title: passengerUid != null
            ? FutureBuilder<Map<String, dynamic>>(
                future: ChatService.getUserInfo(passengerUid),
                builder: (context, snap) {
                  final verified = snap.data?['verified'] == true;
                  return Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        backgroundImage:
                            passengerPhotoUrl != null &&
                                    passengerPhotoUrl.isNotEmpty
                                ? CachedNetworkImageProvider(passengerPhotoUrl)
                                : null,
                        child: passengerPhotoUrl == null ||
                                passengerPhotoUrl.isEmpty
                            ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          passengerName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.verified,
                          size: 20,
                          color: Colors.green.shade700,
                        ),
                      ],
                    ],
                  );
                },
              )
            : Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage:
                        passengerPhotoUrl != null &&
                                passengerPhotoUrl.isNotEmpty
                            ? CachedNetworkImageProvider(passengerPhotoUrl)
                            : null,
                    child: passengerPhotoUrl == null ||
                                passengerPhotoUrl.isEmpty
                            ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                            : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      passengerName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
        elevation: 0,
        actions: [
          if (_order != null)
            IconButton(
              icon: const Icon(Icons.call),
              tooltip: 'Panggilan suara (aktif setelah kesepakatan harga dan driver dalam radius 5 km)',
              onPressed: () async {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null || _order == null) return;
                final (canUse, reason) = await OrderService.canUseVoiceCall(_order!);
                if (!mounted) return;
                if (!canUse) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(reason), backgroundColor: Colors.orange),
                  );
                  return;
                }
                final callerName = FirebaseAuth.instance.currentUser?.displayName ?? 'Driver';
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => VoiceCallScreen(
                      orderId: _order!.id,
                      remoteUid: _order!.passengerUid,
                      remoteName: _order!.passengerName,
                      remotePhotoUrl: _order!.passengerPhotoUrl,
                      isCaller: true,
                      callerName: callerName,
                    ),
                  ),
                );
              },
            ),
          if (_order?.status == OrderService.statusCancelled)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Hapus chat',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Hapus Chat'),
                    content: const Text(
                      'Hapus obrolan ini dari daftar Pesan? Pesanan yang dibatalkan tetap tersimpan di Data Order.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Batal'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Hapus'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted && _order != null) {
                  final err = await OrderService.hideChatForDriver(_order!.id);
                  if (mounted) {
                    if (err == null) {
                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err), backgroundColor: Colors.red),
                      );
                    }
                  }
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/logo_traka.png'),
              fit: BoxFit.contain,
              opacity:
                  0.05, // Logo semi-transparent agar tidak mengganggu pembacaan pesan
              alignment: Alignment.center,
            ),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _order == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Tidak ada pesanan aktif.\nChat akan ditampilkan ketika ada pesanan.',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: StreamBuilder<List<ChatMessageModel>>(
                        stream: ChatService.streamMessages(_order!.id),
                        builder: (context, snap) {
                          // Loading hanya saat benar-benar masih waiting pertama kali dan belum ada data
                          if (snap.connectionState == ConnectionState.waiting &&
                              !snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          // Ambil data messages
                          final messages = snap.data ?? [];

                          // Jika belum ada pesan, tampilkan pemberitahuan yang profesional
                          if (messages.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline,
                                    size: 64,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Belum ada pesan.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Mulai obrolan dengan penumpang.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          // Jika ada pesan, tampilkan daftar pesan
                          // Auto-scroll ke bawah (pesan terbaru) saat pertama kali load
                          if (messages.isNotEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) {
                                _scrollController.jumpTo(
                                  _scrollController.position.maxScrollExtent,
                                );
                              }
                            });
                          }

                          return ListView.builder(
                            controller: _scrollController,
                            reverse:
                                false, // Pesan terbaru di bawah (tidak di-reverse)
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            itemCount: messages.length,
                            itemBuilder: (context, i) {
                              final msg = messages[i];
                              final isMe =
                                  user != null && msg.senderUid == user.uid;
                              return Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                        0.75,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Tampilkan konten berdasarkan type
                                      if (msg.isText)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Flexible(
                                              child: _buildTextContent(
                                                msg.text,
                                                isMe,
                                              ),
                                            ),
                                            if (isMe) ...[
                                              const SizedBox(width: 6),
                                              _buildStatusIcon(msg.status),
                                            ],
                                          ],
                                        )
                                      else if (msg.isAudio)
                                        _buildAudioMessage(msg, isMe: isMe)
                                      else if (msg.isImage)
                                        _buildImageMessage(msg, isMe: isMe)
                                      else if (msg.isVideo)
                                        _buildVideoMessage(msg, isMe: isMe)
                                      else if (msg.isBarcode)
                                        _buildBarcodeMessage(msg, isMe: isMe),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    // Indikator rekaman audio
                    if (_isRecording)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        color: _isRecordingLocked
                            ? (Theme.of(context).brightness == Brightness.dark
                                ? Colors.green.shade900.withOpacity(0.5)
                                : Colors.green.shade50)
                            : (Theme.of(context).brightness == Brightness.dark
                                ? Colors.red.shade900.withOpacity(0.5)
                                : Colors.red.shade50),
                        child: Row(
                          children: [
                            Icon(
                              _isRecordingLocked ? Icons.lock : Icons.mic,
                              color: _isRecordingLocked
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isRecordingLocked
                                  ? 'Rekam terkunci: ${_recordingDuration}s'
                                  : 'Rekam: ${_recordingDuration}s',
                              style: TextStyle(
                                color: _isRecordingLocked
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (_isRecordingLocked)
                              IconButton(
                                onPressed: () => _stopRecording(send: true),
                                icon: const Icon(
                                  Icons.send,
                                  color: Colors.green,
                                ),
                                tooltip: 'Kirim pesan suara',
                              ),
                            TextButton(
                              onPressed: _cancelRecording,
                              child: const Text('Batal'),
                            ),
                          ],
                        ),
                      ),
                    // Banner wajib bayar kontribusi: disable kirim & Kesepakatan
                    if (_mustPayContribution)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        color: Colors.orange.shade50,
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Bayar kontribusi untuk balas pesan dan kesepakatan.',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final ok = await Navigator.of(context)
                                    .push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ContributionDriverScreen(),
                                      ),
                                    );
                                if (ok == true && mounted) setState(() {});
                              },
                              child: const Text('Bayar'),
                            ),
                          ],
                        ),
                      ),
                    // Tombol Scan barcode penumpang (di atas Kesepakatan)
                    if (_order != null && _order!.hasPassengerBarcode)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        color: Theme.of(context).colorScheme.surface,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.of(context)
                                .push<bool>(
                                  MaterialPageRoute(
                                    builder: (ctx) =>
                                        const ScanBarcodeDriverScreen(),
                                  ),
                                );
                            if (result == true && mounted) _loadOrder();
                          },
                          icon: const Icon(Icons.qr_code_scanner, size: 20),
                          label: const Text('Scan barcode penumpang'),
                        ),
                      ),
                    // Tombol Kesepakatan dan harga travel (hijau, di atas form ketik pesan)
                    if (_order != null &&
                        _order!.canDriverAgree &&
                        !_mustPayContribution)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        color: Theme.of(context).colorScheme.surface,
                        child: FilledButton.icon(
                          onPressed: _showDialogKesepakatanHarga,
                          icon: const Icon(Icons.handshake, size: 20),
                          label: const Text('Kesepakatan dan harga travel'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      color: Theme.of(context).colorScheme.surface,
                      child: Row(
                        children: [
                          // Tombol pick media (gambar/video)
                          IconButton(
                            onPressed: _mustPayContribution
                                ? null
                                : _showMediaPicker,
                            icon: const Icon(Icons.attach_file),
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              focusNode: _focusNode,
                              readOnly: _mustPayContribution,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: _mustPayContribution
                                    ? 'Bayar kontribusi untuk balas pesan'
                                    : 'Ketik pesan...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) {
                                if (!_mustPayContribution &&
                                    _textController.text.trim().isNotEmpty) {
                                  _sendMessage();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Keyboard tidak muncul → tombol pesan suara; keyboard muncul → tombol kirim teks
                          _focusNode.hasFocus
                              ? IconButton.filled(
                                  onPressed:
                                      _mustPayContribution ||
                                          _textController.text.trim().isEmpty
                                      ? null
                                      : _sendMessage,
                                  icon: const Icon(Icons.send),
                                )
                              : (_mustPayContribution
                                    ? IconButton(
                                        onPressed: null,
                                        icon: Icon(
                                          Icons.mic,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      )
                                    : _buildVoiceButton()),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
