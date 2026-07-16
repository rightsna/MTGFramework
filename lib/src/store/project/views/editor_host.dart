import 'package:flutter/material.dart';

/// Wraps one of the existing editor screens — which intentionally have no AppBar
/// of their own — in a Scaffold with a titled, back-enabled AppBar. This lets
/// the editors be pushed inside the project navigation stack without modifying
/// the editor screens themselves (nesting Scaffolds is fine in Flutter).
class EditorHost extends StatelessWidget {
  const EditorHost({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: subtitle == null
            ? Text(title)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16)),
                  Text(subtitle!,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
      ),
      body: child,
    );
  }
}
