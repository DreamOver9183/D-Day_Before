import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// White rounded card with a soft shadow and no outline.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: softCardShadow(scheme),
      ),
      child: Material(
        color: softCardColor(scheme),
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}
