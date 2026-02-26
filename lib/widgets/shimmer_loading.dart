import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Placeholder shimmer saat data loading — lebih informatif dari spinner.
class ShimmerLoading extends StatelessWidget {
  const ShimmerLoading({
    super.key,
    this.child,
    this.baseColor,
    this.highlightColor,
  });

  final Widget? child;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = baseColor ??
        (isDark ? Theme.of(context).colorScheme.surfaceContainerHighest : Theme.of(context).colorScheme.outline.withOpacity(0.3));
    final highlight = highlightColor ??
        (isDark ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.surfaceContainerHighest);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: child ?? _defaultPlaceholder(context),
    );
  }

  Widget _defaultPlaceholder(BuildContext context) {
    final fillColor = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Theme.of(context).colorScheme.outline.withOpacity(0.3);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(40),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 20,
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 120,
                      height: 16,
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            height: 80,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 80,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}
