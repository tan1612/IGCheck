import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum AppButtonType { primary, secondary, danger, outline }

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonType type;
  final IconData? icon;
  final double? width;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.type = AppButtonType.primary,
    this.icon,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Color backgroundColor;
    Color foregroundColor;
    BorderSide borderSide = BorderSide.none;

    switch (type) {
      case AppButtonType.primary:
        backgroundColor = theme.primaryColor;
        foregroundColor = Colors.white;
        break;
      case AppButtonType.secondary:
        backgroundColor = const Color(0xFFF3E5F5); // Soft Violet
        foregroundColor = theme.primaryColor;
        break;
      case AppButtonType.danger:
        backgroundColor = const Color(0xFFFFEBEE); // Soft Red
        foregroundColor = const Color(0xFFFF3B30);
        break;
      case AppButtonType.outline:
        backgroundColor = Colors.transparent;
        foregroundColor = theme.primaryColor;
        borderSide = BorderSide(color: theme.primaryColor, width: 1.5);
        break;
    }

    return SizedBox(
      width: width ?? double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: (isLoading || onPressed == null) ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          side: borderSide,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CupertinoActivityIndicator(
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: foregroundColor),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: foregroundColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
