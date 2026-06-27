import 'package:document_studio/shared/layout/breakpoints.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ResponsiveShell extends StatelessWidget {
  const ResponsiveShell({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.selectedNavIndex = 0,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final int selectedNavIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = layoutSizeForWidth(constraints.maxWidth);
        return switch (layout) {
          AppLayoutSize.compact => _CompactShell(
              title: title,
              actions: actions,
              body: body,
              selectedNavIndex: selectedNavIndex,
            ),
          AppLayoutSize.medium => _RailShell(
              title: title,
              actions: actions,
              body: body,
              extended: false,
              selectedNavIndex: selectedNavIndex,
            ),
          AppLayoutSize.expanded => _RailShell(
              title: title,
              actions: actions,
              body: body,
              extended: true,
              selectedNavIndex: selectedNavIndex,
            ),
        };
      },
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.title,
    required this.body,
    this.actions,
    required this.selectedNavIndex,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final int selectedNavIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedNavIndex,
        onDestinationSelected: (i) => _onNav(context, i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _RailShell extends StatelessWidget {
  const _RailShell({
    required this.title,
    required this.body,
    this.actions,
    required this.extended,
    required this.selectedNavIndex,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final bool extended;
  final int selectedNavIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            selectedIndex: selectedNavIndex,
            onDestinationSelected: (i) => _onNav(context, i),
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          if (actions != null) ...actions!,
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _onNav(BuildContext context, int index) {
  switch (index) {
    case 0:
      context.go('/');
    case 1:
      context.go('/settings');
  }
}
