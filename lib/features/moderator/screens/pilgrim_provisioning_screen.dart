import 'package:flutter/material.dart';

import '../widgets/provisioning/provisioning_tab.dart';
import 'manage_pilgrims_screen.dart';

class PilgrimProvisioningScreen extends StatelessWidget {
  const PilgrimProvisioningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0,
          bottom: const TabBar(
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(text: 'Provision'),
              Tab(text: 'Manage'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ProvisioningTab(),
            ManagePilgrimsScreen(),
          ],
        ),
      ),
    );
  }
}
