import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/admin_chat_screen.dart';
import '../services/admin_contact_config_service.dart';
import '../services/feedback_service.dart';

/// Widget kontak admin: hanya gambar admin di pojok kanan bawah.
/// Saat diklik, muncul dialog pilihan: Email, WhatsApp, Instagram, Live Chat.
/// Posisi: fixed di bawah, di atas bottom nav "Saya".
/// Nilai email/WA/IG dari Firestore (bisa diubah admin).
class AdminContactWidget extends StatefulWidget {
  const AdminContactWidget({super.key});

  @override
  State<AdminContactWidget> createState() => _AdminContactWidgetState();
}

class _AdminContactWidgetState extends State<AdminContactWidget> {
  @override
  void initState() {
    super.initState();
    AdminContactConfigService.load();
  }

  Future<void> _launchEmail() async {
    final email = AdminContactConfigService.adminEmail;
    if (email.isEmpty) {
      _showError('Email admin belum dikonfigurasi');
      return;
    }
    final uri = Uri(scheme: 'mailto', path: email);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _showError('Tidak dapat membuka aplikasi email');
      }
    } catch (_) {
      if (mounted) _showError('Tidak dapat membuka aplikasi email');
    }
  }

  Future<void> _launchWhatsApp() async {
    final wa = AdminContactConfigService.adminWhatsApp;
    if (wa.isEmpty) {
      _showError('WhatsApp admin belum dikonfigurasi');
      return;
    }
    // Format: 628xxxxxxxxxx (tanpa +, tanpa spasi)
    final cleanWa = wa.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$cleanWa');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _showError('Tidak dapat membuka WhatsApp');
      }
    } catch (_) {
      if (mounted) _showError('Tidak dapat membuka WhatsApp');
    }
  }

  Future<void> _launchInstagram() async {
    final ig = AdminContactConfigService.adminInstagram;
    if (ig == null || ig.isEmpty) {
      _showError('Instagram belum dikonfigurasi');
      return;
    }
    final username = ig.startsWith('@') ? ig.substring(1) : ig.trim();
    final uri = Uri.parse('https://www.instagram.com/$username');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _showError('Tidak dapat membuka Instagram');
      }
    } catch (_) {
      if (mounted) _showError('Tidak dapat membuka Instagram');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showFeedbackDialog(BuildContext parentContext) {
    final controller = TextEditingController();
    String type = 'saran';
    showDialog<void>(
      context: parentContext,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Saran & Masukan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Berikan saran atau masukan untuk pengembangan aplikasi Traka.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(
                    labelText: 'Jenis',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'saran', child: Text('Saran')),
                    DropdownMenuItem(value: 'masukan', child: Text('Masukan')),
                    DropdownMenuItem(value: 'keluhan', child: Text('Keluhan')),
                  ],
                  onChanged: (v) => setState(() => type = v ?? 'saran'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Tulis saran atau masukan Anda...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Isi saran/masukan terlebih dahulu')),
                  );
                  return;
                }
                final ok = await FeedbackService.submit(text: text, type: type);
                if (!mounted) return;
                Navigator.pop(ctx);
                if (ok) {
                  ScaffoldMessenger.of(parentContext).showSnackBar(
                    const SnackBar(
                      content: Text('Terima kasih! Saran Anda telah dikirim.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  _showError('Gagal mengirim. Coba lagi.');
                }
              },
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );
  }

  void _openLiveChat() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const AdminChatScreen(),
      ),
    );
  }

  void _showContactDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Hubungi Admin',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.email, color: Theme.of(ctx).colorScheme.primary),
              title: const Text('Email'),
              subtitle: Text(AdminContactConfigService.adminEmail),
              onTap: () {
                Navigator.pop(ctx);
                _launchEmail();
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.chat_bubble_outline, color: Theme.of(ctx).colorScheme.primary),
              title: const Text('WhatsApp'),
              subtitle: Text(AdminContactConfigService.adminWhatsApp),
              onTap: () {
                Navigator.pop(ctx);
                _launchWhatsApp();
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.camera_alt, color: Colors.purple),
              title: const Text('Instagram'),
              subtitle: Text(
                AdminContactConfigService.adminInstagram ?? '(Belum dikonfigurasi)',
              ),
              onTap: AdminContactConfigService.adminInstagram != null
                  ? () {
                      Navigator.pop(ctx);
                      _launchInstagram();
                    }
                  : null,
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.chat_bubble_outline,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              title: const Text('Live Chat'),
              subtitle: const Text('Chat langsung dengan admin'),
              onTap: () {
                Navigator.pop(ctx);
                _openLiveChat();
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.feedback_outlined, color: Theme.of(ctx).colorScheme.primary),
              title: const Text('Saran & Masukan'),
              subtitle: const Text('Kirim saran atau masukan untuk aplikasi'),
              onTap: () {
                Navigator.pop(ctx);
                _showFeedbackDialog(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showContactDialog,
      child: Image.asset(
        'assets/images/admin.png',
        width: 48,
        height: 48,
        fit: BoxFit.contain,
      ),
    );
  }
}
