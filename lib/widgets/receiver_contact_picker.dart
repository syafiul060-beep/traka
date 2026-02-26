import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../services/registered_contacts_service.dart';
import '../theme/app_theme.dart';

/// Item: kontak + nomor HP (satu kontak bisa punya banyak nomor).
class _ContactPhoneItem {
  final Contact contact;
  final String phone;
  final String displayName;
  _ContactPhoneItem({
    required this.contact,
    required this.phone,
    required this.displayName,
  });
}

/// Modal picker kontak untuk pilih penerima Kirim Barang.
/// Kontak yang terdaftar Traka ditandai dengan badge.
void showReceiverContactPicker({
  required BuildContext context,
  required void Function(String phone, Map<String, dynamic>? receiverData)
      onSelect,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ReceiverContactPickerSheet(
      onSelect: (phone, data) {
        Navigator.of(ctx).pop();
        onSelect(phone, data);
      },
    ),
  );
}

class _ReceiverContactPickerSheet extends StatefulWidget {
  final void Function(String phone, Map<String, dynamic>? receiverData)
      onSelect;

  const _ReceiverContactPickerSheet({required this.onSelect});

  @override
  State<_ReceiverContactPickerSheet> createState() =>
      _ReceiverContactPickerSheetState();
}

class _ReceiverContactPickerSheetState extends State<_ReceiverContactPickerSheet> {
  List<_ContactPhoneItem> _items = [];
  Map<String, Map<String, dynamic>> _registered = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final contacts = await RegisteredContactsService.getContacts();
      if (!mounted) return;

      final items = <_ContactPhoneItem>[];
      final allPhones = <String>[];

      for (final c in contacts) {
        final phones = RegisteredContactsService.getPhonesFromContact(c);
        final name = c.displayName.trim().isEmpty ? 'Tanpa nama' : c.displayName;
        for (final p in phones) {
          items.add(_ContactPhoneItem(
            contact: c,
            phone: p,
            displayName: name,
          ));
          allPhones.add(p);
        }
      }

      final registered = <String, Map<String, dynamic>>{};
      for (var i = 0; i < allPhones.length; i += 50) {
        final batch = allPhones.skip(i).take(50).toList();
        final result =
            await RegisteredContactsService.checkRegistered(batch);
        registered.addAll(result);
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _registered = registered;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Gagal memuat kontak. Pastikan izin kontak diaktifkan.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: bottomInset + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Pilih penerima dari kontak',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            'Kontak dengan logo Traka sudah terdaftar',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Coba lagi'),
                            ),
                          ],
                        ),
                      )
                    : _items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Tidak ada kontak dengan nomor HP.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _items.length,
                            itemBuilder: (context, i) {
                              final item = _items[i];
                              final normalized =
                                  RegisteredContactsService.normalizePhone(
                                        item.phone,
                                      ) ??
                                      '';
                              final reg = _registered[normalized];
                              final isRegistered = reg != null;

                              return ListTile(
                                leading: _buildAvatar(item.contact, reg),
                                title: Text(
                                  item.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Text(
                                  item.phone,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: isRegistered
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_circle,
                                              size: 18,
                                              color: AppTheme.primary,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Traka',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : null,
                                onTap: () {
                                  widget.onSelect(
                                    item.phone,
                                    isRegistered
                                        ? {
                                            'uid': reg['uid'],
                                            'displayName': reg['displayName'] ??
                                                item.displayName,
                                            'photoUrl': reg['photoUrl'],
                                          }
                                        : null,
                                  );
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(Contact c, Map<String, dynamic>? reg) {
    final photoUrl = reg?['photoUrl'] as String?;
    final photoBytes = c.photo ?? c.thumbnail;

    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        backgroundImage: CachedNetworkImageProvider(photoUrl),
      );
    }
    if (photoBytes != null && photoBytes.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        backgroundImage: MemoryImage(photoBytes),
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppTheme.primary.withOpacity(0.2),
      child: Text(
        (c.displayName.isNotEmpty ? c.displayName[0] : '?').toUpperCase(),
        style: TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
    );
  }
}
