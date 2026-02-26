import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/support_message_model.dart';
import '../models/support_ticket_model.dart';
import '../services/support_chat_service.dart';

/// Halaman live chat support: auto-reply bot, antrian, sambungan ke admin.
/// Menampilkan nama admin saat terhubung.
/// [initialMessage]: pesan awal yang diisi di kotak input (untuk laporkan harga dll).
class AdminChatScreen extends StatefulWidget {
  final String? initialMessage;

  const AdminChatScreen({super.key, this.initialMessage});

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  late final TextEditingController _textController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialMessage ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    final ok = await SupportChatService.sendUserMessage(user.uid, text);
    if (!mounted) return;
    if (!ok) {
      _textController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SupportChatService.lastBlockedReason ??
                'Gagal mengirim pesan. Periksa koneksi dan coba lagi.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ),
      );
      return;
    }
    _scrollToBottom();
  }

  void _requestAdmin() {
    _textController.text = 'hubungi admin';
    _sendMessage();
  }

  void _scrollToBottom() {
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

  /// Bubble chat dengan tampilan jelas berbeda: Pengguna (kanan, biru) vs Admin/Bot (kiri, warna beda).
  /// Fallback: jika senderType hilang (pesan lama), deteksi dari senderUid vs currentUserId.
  Widget _buildChatBubble(
      BuildContext context, SupportMessageModel msg, String currentUserId) {
    final isBot = msg.isFromBot;
    final isAdmin = msg.isFromAdmin || (msg.senderUid != currentUserId && msg.senderUid != 'bot');
    // Pengguna = senderUid sama dengan currentUserId (fallback untuk data tanpa senderType)
    final isMe = msg.senderUid == currentUserId;

    // Pengguna: kanan, primary (biru), teks putih
    if (isMe) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Text(
            msg.text,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    // Admin: kiri, warna teal/hijau (beda dari pengguna), label "Admin"
    if (isAdmin) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final adminBg = isDark
          ? Colors.teal.shade900.withOpacity(0.4)
          : Colors.teal.shade50;
      final adminBorder = isDark ? Colors.teal.shade700 : Colors.teal.shade200;
      final adminAccent = isDark ? Colors.teal.shade300 : Colors.teal.shade700;
      final adminText = isDark ? Colors.teal.shade100 : Colors.teal.shade900;

      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: adminBg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(color: adminBorder, width: 1),
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, size: 14, color: adminAccent),
                  const SizedBox(width: 4),
                  Text(
                    'Admin',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: adminAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                msg.text,
                style: TextStyle(fontSize: 15, color: adminText),
              ),
            ],
          ),
        ),
      );
    }

    // Bot/Sistem: kiri, abu-abu terang, label "Sistem"
    if (isBot) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Sistem',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                msg.text,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sesi tidak valid. Silakan login kembali.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: StreamBuilder<SupportTicketModel?>(
          stream: SupportChatService.streamTicket(user.uid),
          builder: (context, snap) {
            final ticket = snap.data;
            final isConnected = ticket?.isConnected ?? false;
            final adminName = ticket?.assignedAdminName;
            final isInQueue = ticket?.isInQueue ?? false;
            final queuePos = ticket?.queuePosition ?? 0;

            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Icon(
                    isConnected ? Icons.person : Icons.support_agent,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isConnected && adminName != null
                            ? 'Dilayani oleh: $adminName'
                            : 'Admin Traka',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        isConnected
                            ? '● Online'
                            : isInQueue
                                ? 'Antrian #$queuePos'
                                : 'Live Chat',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<SupportMessageModel>>(
                stream: SupportChatService.streamMessages(user.uid),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final messages = snap.data ?? [];

                  if (messages.isEmpty) {
                    return _buildEmptyState(context);
                  }

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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final msg = messages[i];
                      return _buildChatBubble(context, msg, user.uid);
                    },
                  );
                },
              ),
            ),
            _buildQueueBanner(context, user.uid),
            _buildInputSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
            const SizedBox(height: 20),
            Text(
              'Belum ada pesan',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ketik pesan untuk memulai. Anda akan mendapat balasan otomatis terlebih dahulu.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Atau tap "Hubungi Admin" di bawah untuk berbicara dengan tim kami.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueBanner(BuildContext context, String userId) {
    return StreamBuilder<SupportTicketModel?>(
      stream: SupportChatService.streamTicket(userId),
      builder: (context, snap) {
        final ticket = snap.data;
        // Sembunyikan jika sudah terhubung admin atau tidak dalam antrian
        if (ticket == null || ticket.isConnected || !ticket.isInQueue) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Anda antrian #${ticket.queuePosition}. Admin akan segera melayani.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputSection(BuildContext context) {
    return StreamBuilder<SupportTicketModel?>(
      stream: SupportChatService.streamTicket(
          FirebaseAuth.instance.currentUser?.uid ?? ''),
      builder: (context, snap) {
        final ticket = snap.data;
        final showAdminButton = ticket == null ||
            ticket.isBot ||
            ticket.isClosed ||
            (ticket.isInQueue && ticket.queuePosition <= 1);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.5),
              ),
            ),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showAdminButton && (ticket?.isConnected != true)) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _requestAdmin,
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: const Text('Hubungi Admin'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        foregroundColor: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: 'Ketik pesan...',
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 4,
                        minLines: 1,
                        onSubmitted: (_) {
                          if (_textController.text.trim().isNotEmpty) {
                            _sendMessage();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () {
                        if (_textController.text.trim().isNotEmpty) {
                          _sendMessage();
                        }
                      },
                      icon: const Icon(Icons.send_rounded),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        );
      },
    );
  }
}
