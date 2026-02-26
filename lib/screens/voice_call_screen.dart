import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/voice_call_service.dart';
import '../theme/app_theme.dart';

/// Layar panggilan suara in-app (outgoing, incoming, active).
class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({
    super.key,
    required this.orderId,
    required this.remoteUid,
    required this.remoteName,
    this.remotePhotoUrl,
    required this.isCaller,
    this.callerName,
  });

  final String orderId;
  final String remoteUid;
  final String remoteName;
  final String? remotePhotoUrl;
  final bool isCaller;
  /// Nama pemanggil (untuk startCall). Jika null, pakai "Saya".
  final String? callerName;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  String _status = 'ringing'; // ringing | connecting | connected | ended
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    VoiceCallService.onCallStateChange = _onCallStateChange;
    VoiceCallService.onCallEnded = _onCallEnded;

    if (widget.isCaller) {
      _startCall();
    }
  }

  @override
  void dispose() {
    VoiceCallService.onCallStateChange = null;
    VoiceCallService.onCallEnded = null;
    super.dispose();
  }

  Future<void> _startCall() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _onCallEnded();
      return;
    }
    final ok = await VoiceCallService.startCall(
      orderId: widget.orderId,
      callerUid: uid,
      calleeUid: widget.remoteUid,
      callerName: widget.callerName ?? 'Saya',
      calleeName: widget.remoteName,
    );
    if (!ok && mounted) _onCallEnded();
  }

  Future<void> _acceptCall() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _onCallEnded();
      return;
    }
    final ok = await VoiceCallService.acceptCall(
      orderId: widget.orderId,
      calleeUid: uid,
    );
    if (!ok && mounted) _onCallEnded();
  }

  void _onCallStateChange(String status) {
    if (mounted) setState(() => _status = status);
  }

  void _onCallEnded() {
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _hangUp() async {
    HapticFeedback.mediumImpact();
    await VoiceCallService.endCall(widget.orderId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _rejectCall() async {
    HapticFeedback.mediumImpact();
    await VoiceCallService.rejectCall(widget.orderId);
    if (mounted) Navigator.of(context).pop();
  }

  String get _statusLabel {
    switch (_status) {
      case 'ringing':
        return widget.isCaller ? 'Memanggil...' : 'Panggilan masuk';
      case 'connecting':
        return 'Menghubungkan...';
      case 'connected':
        return 'Terhubung';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            // Avatar & nama
            CircleAvatar(
              radius: 56,
              backgroundColor: colorScheme.surfaceContainerHighest,
              backgroundImage: widget.remotePhotoUrl != null &&
                      widget.remotePhotoUrl!.isNotEmpty
                  ? NetworkImage(widget.remotePhotoUrl!)
                  : null,
              child: widget.remotePhotoUrl == null ||
                      widget.remotePhotoUrl!.isEmpty
                  ? Icon(
                      Icons.person,
                      size: 56,
                      color: colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            Text(
              widget.remoteName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _statusLabel,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            // Tombol
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (!widget.isCaller && _status == 'ringing') ...[
                    _buildActionButton(
                      icon: Icons.call_end,
                      label: 'Tolak',
                      color: Colors.red,
                      onTap: _rejectCall,
                    ),
                    _buildActionButton(
                      icon: Icons.call,
                      label: 'Terima',
                      color: Colors.green,
                      onTap: _acceptCall,
                    ),
                  ] else
                    _buildActionButton(
                      icon: Icons.call_end,
                      label: 'Tutup',
                      color: Colors.red,
                      onTap: _hangUp,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color.withValues(alpha: 0.2),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, size: 32, color: color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
