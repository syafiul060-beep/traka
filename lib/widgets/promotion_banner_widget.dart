import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/promotion_model.dart';
import '../services/promotion_service.dart';
import '../screens/promo_list_screen.dart';

/// Banner promosi di beranda (penumpang/driver).
/// Menampilkan promosi teratas, tap untuk baca detail.
/// Tombol X untuk menutup banner sementara (sampai app ditutup).
class PromotionBannerWidget extends StatefulWidget {
  const PromotionBannerWidget({super.key, required this.role});

  final String role;

  @override
  State<PromotionBannerWidget> createState() => _PromotionBannerWidgetState();
}

class _PromotionBannerWidgetState extends State<PromotionBannerWidget> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return StreamBuilder<List<PromotionModel>>(
      stream: PromotionService.streamActivePromotions(widget.role),
      builder: (context, snap) {
        final list = snap.data ?? [];
        if (list.isEmpty) return const SizedBox.shrink();
        final p = list.first;
        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PromoDetailScreen(promotion: p),
                ),
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    if (p.imageUrl != null && p.imageUrl!.isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(11)),
                        child: CachedNetworkImage(
                          imageUrl: p.imageUrl!,
                          width: 80,
                          height: 56,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 80,
                            height: 56,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 80,
                            height: 56,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.campaign_outlined),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.campaign_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Info',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      onPressed: () => setState(() => _dismissed = true),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Tutup',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
