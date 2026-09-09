import 'package:flutter/material.dart';

/// Bordered surface used everywhere instead of Material elevation.
///
/// Defined as a widget rather than via ThemeData.cardTheme because the type of
/// that field (CardTheme vs CardThemeData) changed across Flutter 3.x, and
/// this project should build on whatever version the hackathon machine has.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);

    return Material(
      color: color ?? scheme.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: radius,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: borderColor ?? scheme.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }
}
