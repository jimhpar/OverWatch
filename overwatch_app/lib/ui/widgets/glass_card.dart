import 'package:flutter/material.dart';
import '../../core/constants.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? focusedBorderColor;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final bool autofocus;

  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderColor,
    this.focusedBorderColor,
    this.padding,
    this.borderRadius = 16.0,
    this.autofocus = false,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final activeBorderColor = (_isFocused || _isHovered)
        ? (widget.focusedBorderColor ?? AppConstants.accentOrange)
        : (widget.borderColor ?? AppConstants.cardBorderColor);

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: (_isFocused || _isHovered)
              ? Matrix4.diagonal3Values(1.02, 1.02, 1.0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: AppConstants.surfaceDark.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: activeBorderColor,
              width: (_isFocused || _isHovered) ? 2.5 : 1.5,
            ),
            boxShadow: (_isFocused || _isHovered)
                ? [
                    BoxShadow(
                      color: activeBorderColor.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 2,
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              onTap: widget.onTap,
              child: Padding(
                padding: widget.padding ?? const EdgeInsets.all(20.0),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
