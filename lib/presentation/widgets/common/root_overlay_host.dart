import 'package:flutter/widgets.dart';

/// Provides an overlay for the floating text fields and their editing menus.
class RootOverlayHost extends StatelessWidget {
  const RootOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Overlay.wrap updates its entry in the same build, not in a post-frame
    // callback. Live desktop resize must not leave the content a frame behind.
    return Overlay.wrap(child: child);
  }
}
