import 'package:flutter/material.dart';

/// Default duration for dashboard tab page transitions.
const dashboardTabAnimDuration = Duration(milliseconds: 350);

/// Default curve for dashboard tab page transitions.
const dashboardTabAnimCurve = Curves.easeInOut;

/// Wraps a dashboard tab so [PageView] keeps its state when off-screen.
class KeepAliveTab extends StatefulWidget {
  const KeepAliveTab({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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
  });

  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final List<Widget> children;
  final Color? backgroundColor;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final pageView = PageView(
      clipBehavior: Clip.hardEdge,
      controller: controller,
      physics: physics ?? const PageScrollPhysics(),
      onPageChanged: onPageChanged,
      children: [
        for (var i = 0; i < children.length; i++)
          KeepAliveTab(
            key: ValueKey<int>(i),
            child: children[i],
          ),
      ],
    );
    final bg = backgroundColor;
    if (bg == null) return pageView;
    return ColoredBox(color: bg, child: pageView);
  }
}
