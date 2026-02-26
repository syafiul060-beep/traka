import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme/app_theme.dart';

/// Kontrol map: toggle satelit/normal + zoom in/out.
/// Dipakai di penumpang_screen dan driver_screen.
class MapTypeZoomControls extends StatelessWidget {
  const MapTypeZoomControls({
    super.key,
    required this.mapType,
    required this.onToggleMapType,
    required this.onZoomIn,
    required this.onZoomOut,
    this.topOffset = 60,
  });

  final MapType mapType;
  final VoidCallback onToggleMapType;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final double topOffset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: topOffset,
      right: 16,
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggleMapType,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                mapType == MapType.normal ? Icons.satellite : Icons.map,
                color: AppTheme.primary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.add,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: onZoomIn,
                ),
              ),
              Container(width: 36, height: 1, color: colorScheme.outline),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.remove,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: onZoomOut,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
