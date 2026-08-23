import 'package:flutter/material.dart';
import 'top_bar.dart';

class ScrollScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBackButton;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool addBottomNavPadding;

  const ScrollScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.showBackButton = false,
    this.onBack,
    this.actions,
    required this.children,
    this.padding = const EdgeInsets.all(28.0),
    this.addBottomNavPadding = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TopBar(
          title: title,
          subtitle: subtitle,
          showBackButton: showBackButton,
          onBack: onBack,
          actions: actions,
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...children,
                if (addBottomNavPadding) const SizedBox(height: 90),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
