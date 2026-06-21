import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Default duration for dashboard tab page transitions.
const dashboardTabAnimDuration = Duration(milliseconds: 350);

/// Default curve for dashboard tab page transitions.
const dashboardTabAnimCurve = Curves.easeInOut;

/// Wraps a dashboard tab so [PageView] keeps its state when off-screen.
class KeepAliveTab extends StatefulWidget {
  const KeepAliveTab({
    super.key,
    required this.child,
    this.keepAlive = true,
  });

  final Widget child;

  /// When false, the tab may be disposed once scrolled off-screen.
  final bool keepAlive;

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Rebuild keep-alive tabs when the app language changes.
    context.locale;
    return widget.child;
  }
}

/// Builds [child] only while [mount] is true so heavy subtrees (e.g. MapKit)
/// are torn down when the user leaves the tab.
class DeferredDashboardTab extends StatelessWidget {
  const DeferredDashboardTab({
    super.key,
    required this.mount,
    required this.child,
    this.placeholder,
  });

  final bool mount;
  final Widget child;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    if (mount) return child;
    return placeholder ?? const SizedBox.expand();
  }
}

/// Dashboard [PageView] with keep-alive tab children and stable keys.
class DashboardTabPageView extends StatelessWidget {
  const DashboardTabPageView({
    super.key,
    required this.controller,
    required this.onPageChanged,
    required this.children,
    this.backgroundColor,
    this.physics,
    this.keepAliveForTab,
  });

  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final List<Widget> children;
  final Color? backgroundColor;
  final ScrollPhysics? physics;

  /// Per-tab keep-alive flags aligned with [children]. Omitted indices default
  /// to true (preserves moderator dashboard behaviour).
  final List<bool>? keepAliveForTab;

  @override
  Widget build(BuildContext context) {
    final pageView = NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
        return false;
      },
      child: PageView(
        clipBehavior: Clip.hardEdge,
        controller: controller,
        physics: physics ?? const PageScrollPhysics(),
        onPageChanged: onPageChanged,
        children: [
          for (var i = 0; i < children.length; i++)
            KeepAliveTab(
              key: ValueKey<int>(i),
              keepAlive: _keepAliveForIndex(i),
              child: children[i],
            ),
        ],
      ),
    );
    final bg = backgroundColor;
    if (bg == null) return pageView;
    return ColoredBox(color: bg, child: pageView);
  }

  bool _keepAliveForIndex(int index) {
    final flags = keepAliveForTab;
    if (flags == null || index >= flags.length) return true;
    return flags[index];
  }
}
