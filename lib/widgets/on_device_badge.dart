import 'package:flutter/material.dart';

/// "Runs on your phone" marker.
///
/// The wording is deliberately "on-device", never "NPU accelerated":
/// llama.cpp on Android runs on CPU (and GPU via Vulkan where available), not
/// the Hexagon NPU, and claiming otherwise in front of judges who can check
/// would be a bad trade for a word.
class OnDeviceBadge extends StatelessWidget {
  const OnDeviceBadge({
    super.key,
    this.label = 'Computed on your phone',
    this.icon = Icons.phonelink_lock_outlined,
    this.dense = false,
  });

  final String label;
  final IconData icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: dense ? 12 : 14,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: (dense
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.labelMedium)
                ?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
