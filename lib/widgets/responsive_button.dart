import 'package:flutter/material.dart';

class ResponsiveButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double widthFactor; // fraction (0..1) de la largeur parent
  const ResponsiveButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.widthFactor = 0.85,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final w = maxW * widthFactor;
        return SizedBox(
          width: w,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
