import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';

import '../models/chat_message_model.dart';
import '../models/order_model.dart';
import '../theme/responsive.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../services/audio_recorder_service.dart';
import '../services/chat_service.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/location_service.dart';
import '../services/order_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'cek_lokasi_driver_screen.dart';
import 'voice_call_screen.dart';

/// Halaman ruang chat penumpang dengan satu driver (seperti satu percakapan WhatsApp).
/// AppBar: foto + nama driver (dengan ikon verifikasi jika driver terverifikasi), icon Telp.
/// Body: daftar pesan + input kirim pesan. Tanpa kartu Dari/Tujuan dan tanpa tombol Batalkan.
class ChatRoomPenumpangScreen extends StatefulWidget {
  const ChatRoomPenumpangScreen({
    super.key,
    required this.orderId,
    required this.driverUid,
    required this.driverName,
    this.driverPhotoUrl,
    this.driverVerified = false,

    /// Jika diisi, pesan ini dikirim otomatis sekali saat chat dibuka (untuk jenis pesanan).
    this.sendJenisPesananMessage,
  });

  final String orderId;
  final String driverUid;
  final String driverName;
  final String? driverPhotoUrl;
  final bool driverVerified;
  final String? sendJenisPesananMessage;

  @override
  State<ChatRoomPenumpangScreen> createState() =>
      _ChatRoomPenumpangScreenState();
}

class _ChatRoomPenumpangScreenState extends State<ChatRoomPenumpangScreen> {
  OrderModel? _order;
  bool _orderLoading = true;
  bool _actionLoading = false;
  bool _popupShown = false; // Flag agar tidak double-schedule timer
  Timer? _kesepakatanPopupTimer; // Timer 3 detik sebelum popup kesepakatan
  Timer?
  _orderRefreshTimer; // Refresh order berkala agar deteksi saat driver kirim harga
  Timer? _passengerLocationUpdateTimer; // Update lokasi penumpang ke order saat menunggu jemput
  (double, double)? _lastPassengerLocationUpdate; // Lokasi terakhir yang di-push ke Firestore
  /// Foto driver dari widget atau hasil load Firestore (fallback).
  String? _driverPhotoUrl;
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _incomingCallSub;

  @override
  void initState() {
    super.initState();
    _driverPhotoUrl = widget.driverPhotoUrl;
    _focusNode.addListener(_onFocusChange);
    _loadOrder();
    // Refresh order tiap 5 detik agar ketika driver kirim kesepakatan harga kita deteksi dan jadwalkan popup 3 detik
    _orderRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_order != null &&
          _order!.agreedPrice != null &&
          !_order!.canPassengerAgree)
        return; // sudah setuju, stop refresh
      _loadOrder();
    });
    if (widget.driverPhotoUrl == null || widget.driverPhotoUrl!.isEmpty) {
      _loadDriverPhoto();
    }
    _markReceivedMessagesAsDeliveredAndRead();
    _listenIncomingCall();
    if (widget.sendJenisPesananMessage != null &&
        widget.sendJenisPesananMessage!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendJenisPesananMessageOnce();
      });
    }
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  /// Kirim sekali pesan jenis pesanan hanya jika ini pesan pertama di chat; selanjutnya pengguna isi manual.
  Future<void> _sendJenisPesananMessageOnce() async {
    final text = widget.sendJenisPesananMessage?.trim();
    if (text == null || text.isEmpty || widget.orderId.isEmpty) return;
    final alreadyHasMessage = await ChatService.hasAnyMessage(widget.orderId);
    if (alreadyHasMessage) return;
    await ChatService.sendMessage(widget.orderId, text);
  }

  /// Penerima (penumpang) buka chat: tandai pesan driver jadi delivered lalu read.
  Future<void> _markReceivedMessagesAsDeliveredAndRead() async {
    await ChatService.markAsDelivered(widget.orderId);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await ChatService.markAsRead(widget.orderId);
    // Update passengerLastReadAt di order document untuk menghilangkan badge unread
    await OrderService.setPassengerLastReadAt(widget.orderId);
  }

  Future<void> _loadDriverPhoto() async {
    final info = await ChatService.getUserInfo(widget.driverUid);
    final photoUrl = info['photoUrl'] as String?;
    if (mounted && (photoUrl != null && photoUrl.isNotEmpty)) {
      setState(() => _driverPhotoUrl = photoUrl);
    }
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    _kesepakatanPopupTimer?.cancel();
    _orderRefreshTimer?.cancel();
    _passengerLocationUpdateTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    // Dispose semua audio player
    for (final player in _audioPlayers.values) {
      player.dispose();
    }
    _audioPlayers.clear();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    final order = await OrderService.getOrderById(widget.orderId);
    if (mounted) {
      final shouldSchedulePopup =
          order != null &&
          order.canPassengerAgree &&
          order.agreedPrice != null &&
          !_popupShown;

      setState(() {
        _order = order;
        _orderLoading = false;
      });

      // Driver sudah kirim harga: jadwalkan popup konfirmasi kesepakatan setelah 3 detik, muncul terus sampai penumpang setuju
      if (shouldSchedulePopup) {
        _scheduleKesepakatanPopup();
      }

      // Order agreed & belum dijemput: mulai update lokasi penumpang ke Firestore (untuk live tracking driver)
      _startOrStopPassengerLocationUpdates();
    }
  }

  void _listenIncomingCall() {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    _incomingCallSub?.cancel();
    _incomingCallSub = FirebaseFirestore.instance
        .collection('voice_calls')
        .doc(widget.orderId)
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
            orderId: widget.orderId,
            remoteUid: widget.driverUid,
            remoteName: (d['callerName'] as String?) ?? widget.driverName,
            remotePhotoUrl: _driverPhotoUrl ?? widget.driverPhotoUrl,
            isCaller: false,
          ),
        ),
      );
    });
  }

  /// Mulai atau hentikan timer update lokasi penumpang ke order.
  void _startOrStopPassengerLocationUpdates() {
    final order = _order;
    final shouldUpdate = order != null &&
        order.status == OrderService.statusAgreed &&
        !order.hasDriverScannedPassenger;

    if (shouldUpdate && _passengerLocationUpdateTimer == null) {
      _passengerLocationUpdateTimer =
          Timer.periodic(const Duration(seconds: 30), (_) {
        _updatePassengerLocationToOrder();
      });
    } else if (!shouldUpdate && _passengerLocationUpdateTimer != null) {
      _passengerLocationUpdateTimer?.cancel();
      _passengerLocationUpdateTimer = null;
      _lastPassengerLocationUpdate = null;
    }
  }

  /// Ambil lokasi saat ini dan update ke order jika berubah ≥50m.
  Future<void> _updatePassengerLocationToOrder() async {
    if (!mounted || _order == null) return;
    if (_order!.status != OrderService.statusAgreed ||
        _order!.hasDriverScannedPassenger) {
      return;
    }
    try {
      final result = await LocationService.getCurrentPositionWithMockCheck();
      if (result.isFakeGpsDetected) {
        if (mounted) FakeGpsOverlayService.showOverlay();
        return;
      }
      final position = result.position;
      if (!mounted || position == null) return;
      final lat = position.latitude;
      final lng = position.longitude;
      final last = _lastPassengerLocationUpdate;
      final shouldUpdate = last == null ||
          Geolocator.distanceBetween(last.$1, last.$2, lat, lng) >= 50;
      if (shouldUpdate) {
        final ok = await OrderService.updatePassengerLocation(
          widget.orderId,
          passengerLat: lat,
          passengerLng: lng,
        );
        if (ok && mounted) {
          _lastPassengerLocationUpdate = (lat, lng);
        }
      }
    } catch (_) {}
  }

  /// Jadwalkan popup kesepakatan 3 detik lagi; setelah tampil, jika penumpang tutup (Batal) akan dijadwalkan lagi.
  void _scheduleKesepakatanPopup() {
    _kesepakatanPopupTimer?.cancel();
    _popupShown = true;
    _kesepakatanPopupTimer = Timer(const Duration(seconds: 3), () {
      _kesepakatanPopupTimer = null;
      if (!mounted) return;
      if (_order == null ||
          !_order!.canPassengerAgree ||
          _order!.agreedPrice == null) {
        _popupShown = false;
        return;
      }
      _showDialogKesepakatanPenumpangAuto();
    });
  }

  /// Format alamat: hanya kecamatan dan kabupaten, tanpa provinsi.
  String _formatAlamatKecamatanKabupaten(String alamat) {
    if (alamat.isEmpty) return alamat;
    final parts = alamat
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return alamat;

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

    if (kecamatan == null && kabupaten == null && parts.length >= 2) {
      kecamatan = parts[0];
      kabupaten = parts[1];
    } else if (kecamatan == null && parts.isNotEmpty) {
      kecamatan = parts[0];
    }

    final result = <String>[];
    if (kecamatan != null) result.add(kecamatan);
    if (kabupaten != null && kabupaten != kecamatan) result.add(kabupaten);

    return result.isEmpty ? alamat : result.join(', ');
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final orderId = widget.orderId;
    if (orderId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal mengirim: data pesanan tidak valid.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _textController.clear();
    final ok = await ChatService.sendMessage(orderId, text);
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
    _scrollToBottom(); // Scroll ke bawah (pesan terbaru)
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

    final orderId = widget.orderId;
    if (orderId.isEmpty) return;

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
      orderId,
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
      _scrollToBottom();
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
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final orderId = widget.orderId;
    if (orderId.isEmpty) return;

    final ok = await ChatService.sendImageMessage(orderId, File(image.path));
    if (!mounted) return;
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
      _scrollToBottom();
    }
  }

  /// Pick video dari gallery
  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    final orderId = widget.orderId;
    if (orderId.isEmpty) return;

    final ok = await ChatService.sendVideoMessage(orderId, File(video.path));
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal mengirim video. Periksa koneksi dan coba lagi.'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      _scrollToBottom();
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
        ? 'Barcode penumpang (tunjukkan ke driver)'
        : 'Barcode driver (scan saat sampai tujuan)';
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

  /// Ikon status pesan: 1 centang (sent), 2 centang abu (delivered), 2 centang biru (read).
  Widget _buildStatusIcon(String status, {required bool isMe}) {
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
        if (isMe) ...[
          const SizedBox(width: 6),
          _buildStatusIcon(msg.status, isMe: true),
        ],
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
            children: [_buildStatusIcon(msg.status, isMe: true)],
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
            children: [_buildStatusIcon(msg.status, isMe: true)],
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

  /// Scroll ke bawah (pesan terbaru) seperti WhatsApp standar
  void _scrollToBottom() {
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

  /// Dialog Kesepakatan otomatis: muncul 3 detik setelah driver kirim harga, muncul terus sampai penumpang setuju.
  void _showDialogKesepakatanPenumpangAuto() {
    if (_order == null ||
        !_order!.canPassengerAgree ||
        _order!.agreedPrice == null)
      return;
    final order = _order!;
    final harga = order.agreedPrice!;
    bool checkboxValue = false;

    void onBatalTapped() {
      Navigator.of(context).pop(); // Tutup dialog kesepakatan dulu
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx2) => AlertDialog(
          title: const Text('Konfirmasi'),
          content: const Text(
            'Apakah Anda ingin membatalkan kesepakatan ini / ingin membuat kesepakatan baru?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: const Text('Tidak'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx2, true),
              child: const Text('Ya'),
            ),
          ],
        ),
      ).then((yes) async {
        if (yes == true && mounted && _order != null) {
          await ChatService.sendMessage(
            _order!.id,
            'Penumpang membatalkan kesepakatan dan ingin membuat kesepakatan baru.',
          );
          if (mounted) {
            _popupShown = true; // Agar popup tidak muncul lagi
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Pesan telah dikirim ke driver. Driver dapat mengirim kesepakatan harga baru.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      });
    }

    // Teks dinamis sesuai jenis pesanan (penumpang sendiri / kerabat / kirim barang)
    final String dialogTitle = order.isKirimBarang
        ? 'Konfirmasi Tawaran Biaya Pengiriman'
        : order.isTravelKerabat
            ? 'Konfirmasi Tawaran Harga Perjalanan'
            : 'Konfirmasi Tawaran Harga Perjalanan';
    final String pengantar = order.isKirimBarang
        ? 'Driver mengirim tawaran biaya untuk pengiriman barang Anda:'
        : order.isTravelKerabat
            ? 'Driver mengirim tawaran harga untuk perjalanan Anda dan kerabat (${order.totalPenumpang} orang):'
            : 'Driver mengirim tawaran harga untuk perjalanan Anda:';
    final String labelHarga = order.isKirimBarang
        ? 'Biaya pengiriman yang ditawarkan'
        : order.isTravelKerabat
            ? 'Harga yang ditawarkan (${order.totalPenumpang} orang)'
            : 'Harga yang ditawarkan';
    final String catatanBayar = order.isKirimBarang
        ? 'Pembayaran langsung ke driver saat barang dijemput/diantar. Harga wajib sesuai kesepakatan.'
        : 'Pembayaran langsung ke driver saat bertemu. Harga wajib sesuai kesepakatan.';
    final String checkboxText = order.isKirimBarang
        ? 'Saya setuju dengan biaya pengiriman di atas. Jika driver meminta harga berbeda, saya akan melaporkan.'
        : order.isTravelKerabat
            ? 'Saya setuju dengan harga di atas untuk perjalanan kami (${order.totalPenumpang} orang). Jika driver meminta harga berbeda, saya akan melaporkan.'
            : 'Saya setuju dengan harga di atas untuk perjalanan saya. Jika driver meminta harga berbeda, saya akan melaporkan.';
    final hargaFormatted = harga.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              actionsPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              title: SizedBox(
                width: double.maxFinite,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dialogTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        order.orderTypeDisplayLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pengantar,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.maxFinite,
                      child: Text(
                        widget.driverName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                    SizedBox(
                      width: double.maxFinite,
                      child: Text(
                        '$labelHarga: Rp $hargaFormatted',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      catatanBayar,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: checkboxValue,
                      onChanged: (v) {
                        setDialogState(() {
                          checkboxValue = v ?? false;
                        });
                      },
                      title: Text(
                        checkboxText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => onBatalTapped(),
                  child: const Text('Tolak'),
                ),
                FilledButton(
                  onPressed: checkboxValue
                      ? () {
                          Navigator.pop(dialogContext);
                          _onSetujuiKesepakatan();
                        }
                      : null,
                  child: const Text('Setujui & Lanjutkan'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _onSetujuiKesepakatan() async {
    if (_order == null) return;

    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Izin lokasi diperlukan untuk menyelesaikan kesepakatan.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final result = await LocationService.getCurrentPositionWithMockCheck();
    if (result.isFakeGpsDetected) {
      if (mounted) FakeGpsOverlayService.showOverlay();
      return;
    }
    final position = result.position;
    if (position == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat memperoleh lokasi. Coba lagi.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    String locationText = '${position.latitude}, ${position.longitude}';
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if ((p.name ?? '').isNotEmpty) parts.add(p.name!);
        if ((p.thoroughfare ?? '').isNotEmpty) parts.add(p.thoroughfare!);
        if ((p.subLocality ?? '').isNotEmpty) parts.add(p.subLocality!);
        if ((p.administrativeArea ?? '').isNotEmpty) {
          parts.add(p.administrativeArea!);
        }
        if (parts.isNotEmpty) locationText = parts.join(', ');
      }
    } catch (_) {}

    setState(() => _actionLoading = true);
    final (ok, barcodePayload) = await OrderService.setPassengerAgreed(
      _order!.id,
      passengerLat: position.latitude,
      passengerLng: position.longitude,
      passengerLocationText: locationText,
    );
    if (!mounted) return;
    setState(() => _actionLoading = false);
    if (ok) {
      _popupShown = false;
      await ChatService.sendMessage(
        _order!.id,
        'Penumpang sudah mensetujui kesepakatan.',
      );
      if (barcodePayload != null && mounted) {
        await ChatService.sendBarcodeMessage(
          _order!.id,
          barcodePayload,
          'barcode_passenger',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kesepakatan berhasil. Pesanan aktif di menu Pesanan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadOrder();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage:
                  _driverPhotoUrl != null && _driverPhotoUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(_driverPhotoUrl!)
                  : null,
              child: _driverPhotoUrl == null || _driverPhotoUrl!.isEmpty
                  ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.driverName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.driverVerified) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.verified,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                  if (_order?.orderTypeDisplayLabel != null &&
                      _order!.orderTypeDisplayLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _order!.orderTypeDisplayLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
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
                if (confirmed == true && mounted) {
                  final err = await OrderService.hideChatForPassenger(widget.orderId);
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
          if (_order?.isKirimBarang == true)
            IconButton(
              icon: const Icon(Icons.location_on),
              tooltip: 'Cek lokasi driver',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CekLokasiDriverScreen(
                      orderId: widget.orderId,
                      order: _order,
                    ),
                  ),
                );
              },
            ),
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
              final callerName = _order?.passengerName ??
                  FirebaseAuth.instance.currentUser?.displayName ??
                  'Penumpang';
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => VoiceCallScreen(
                    orderId: widget.orderId,
                    remoteUid: widget.driverUid,
                    remoteName: widget.driverName,
                    remotePhotoUrl: _driverPhotoUrl ?? widget.driverPhotoUrl,
                    isCaller: true,
                    callerName: callerName,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/logo_traka.png'),
              fit: BoxFit.contain,
              opacity:
                  0.05, // Logo semi-transparent agar tidak mengganggu pembacaan pesan
              alignment: Alignment.center,
            ),
          ),
          child: Column(
            children: [
              if (_order != null && _order!.hasDriverScannedPassenger)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  color: Colors.green.shade50,
                  child: Row(
                    children: [
                      Icon(
                        Icons.directions_car,
                        color: Colors.green.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Perjalanan aktif. Saat sampai tujuan, buka Data Order > Driver lalu scan barcode driver.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: StreamBuilder<List<ChatMessageModel>>(
                  stream: ChatService.streamMessages(widget.orderId),
                  builder: (context, snap) {
                    // Loading hanya saat benar-benar masih waiting pertama kali dan belum ada data
                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
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
                              'Mulai obrolan dengan driver.',
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
                      padding: EdgeInsets.symmetric(
                        horizontal: context.responsive.spacing(16),
                        vertical: context.responsive.spacing(12),
                      ),
                      cacheExtent: 300,
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final msg = messages[i];
                        final isMe = user != null && msg.senderUid == user.uid;
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
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Tampilkan konten berdasarkan type
                                if (msg.isText)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Flexible(
                                        child: _buildTextContent(
                                          msg.text,
                                          isMe,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 6),
                                        _buildStatusIcon(
                                          msg.status,
                                          isMe: true,
                                        ),
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
                        color: _isRecordingLocked ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isRecordingLocked
                            ? 'Rekam terkunci: ${_recordingDuration}s'
                            : 'Rekam: ${_recordingDuration}s',
                        style: TextStyle(
                          color: _isRecordingLocked ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (_isRecordingLocked)
                        IconButton(
                          onPressed: () => _stopRecording(send: true),
                          icon: const Icon(Icons.send, color: Colors.green),
                          tooltip: 'Kirim pesan suara',
                        ),
                      TextButton(
                        onPressed: _cancelRecording,
                        child: const Text('Batal'),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: Theme.of(context).colorScheme.surface,
                child: Row(
                  children: [
                    // Tombol pick media (gambar/video)
                    IconButton(
                      onPressed: _showMediaPicker,
                      icon: const Icon(Icons.attach_file),
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Ketik pesan...',
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
                          if (_textController.text.trim().isNotEmpty) {
                            _sendMessage();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Keyboard tidak muncul → tombol pesan suara; keyboard muncul → tombol kirim teks
                    _focusNode.hasFocus
                        ? IconButton.filled(
                            onPressed: _textController.text.trim().isEmpty
                                ? null
                                : _sendMessage,
                            icon: const Icon(Icons.send),
                          )
                        : _buildVoiceButton(),
                  ],
                ),
              ),
              if (_orderLoading)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              // Tombol Kesepakatan tidak ditampilkan lagi karena sudah diganti dengan popup otomatis
            ],
          ),
        ),
      ),
    );
  }
}
